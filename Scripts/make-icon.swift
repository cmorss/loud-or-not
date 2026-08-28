import AppKit
import CoreImage

// Draws the app icon: a dark screen whose border glows the way the real overlay does,
// wrapped around a voice waveform whose peak has gone red.
//
// Every size is drawn from scratch rather than downsampled from one big image, because
// the rim glow and the thin bars turn to mush when they are resampled to 16pt.

/// Apple's icon shape is a squircle, not a rounded rectangle: the corners ease into the
/// straight edges instead of meeting a circular arc. A superellipse of degree 5 is the
/// usual approximation.
func squircle(in rect: CGRect, degree: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2
    let b = rect.height / 2
    let exponent = 2 / degree
    let steps = 512
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let cosT = cos(t)
        let sinT = sin(t)
        let x = rect.midX + a * copysign(pow(abs(cosT), exponent), cosT)
        let y = rect.midY + b * copysign(pow(abs(sinT), exponent), sinT)
        if step == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func newContext(size: CGFloat) -> CGContext {
    let context = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high
    return context
}

private let ciContext = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])

/// A ring of the given thickness sitting on the outline, painted with the glow ramp.
/// Blurring it is what turns a hard band into light spilling off the edge; stacking
/// translucent strokes instead leaves visible contour rings.
func glowRing(size: CGFloat, outline: CGPath, thickness: CGFloat, blur: CGFloat, gradient: CGGradient, across: CGRect) -> CGImage {
    let context = newContext(size: size)
    context.addPath(outline)
    context.setLineWidth(thickness)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: across.minX, y: across.minY),
        end: CGPoint(x: across.maxX, y: across.maxY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    let ring = CIImage(cgImage: context.makeImage()!)
    guard blur > 0 else { return ciContext.createCGImage(ring, from: ring.extent)! }
    let filter = CIFilter(name: "CIGaussianBlur")!
    filter.setValue(ring, forKey: kCIInputImageKey)
    filter.setValue(blur, forKey: kCIInputRadiusKey)
    return ciContext.createCGImage(filter.outputImage!, from: ring.extent)!
}

func barPath(x: CGFloat, height: CGFloat, width: CGFloat, centerY: CGFloat) -> CGPath {
    let rect = CGRect(x: x, y: centerY - height / 2, width: width, height: height)
    return CGPath(roundedRect: rect, cornerWidth: width / 2, cornerHeight: width / 2, transform: nil)
}

func makeIcon(size: CGFloat) -> CGImage {
    let context = newContext(size: size)

    // Everything below is expressed against Apple's 1024pt grid, where the artwork itself
    // is an 824pt square centred in the canvas and the rest is breathing room for shadow.
    let scale = size / 1024
    func u(_ value: CGFloat) -> CGFloat { value * scale }

    let body = CGRect(x: u(100), y: u(108), width: u(824), height: u(824))
    let bodyPath = squircle(in: body)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: u(-14)), blur: u(30), color: rgb(0, 0, 0, 0.34))
    context.addPath(bodyPath)
    context.setFillColor(rgb(0, 0, 0, 1))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(bodyPath)
    context.clip()

    let space = CGColorSpaceCreateDeviceRGB()
    let screen = CGGradient(
        colorsSpace: space,
        colors: [rgb(0.21, 0.23, 0.27), rgb(0.07, 0.08, 0.10)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        screen,
        start: CGPoint(x: body.midX, y: body.maxY),
        end: CGPoint(x: body.midX, y: body.minY),
        options: []
    )

    // The overlay's own ramp, so the icon glows in the colours you actually see on screen.
    let rim = CGGradient(
        colorsSpace: space,
        colors: [rgb(1.00, 0.86, 0.15), rgb(1.00, 0.55, 0.08), rgb(1.00, 0.16, 0.12)] as CFArray,
        locations: [0, 0.5, 1]
    )!

    // Three passes: a wide haze spilling towards the middle, a tighter halo, and a hard
    // line on the edge itself. The clip keeps the outward half of each, so the light only
    // ever falls inwards.
    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    let passes: [(thickness: CGFloat, blur: CGFloat, alpha: CGFloat)] = [
        (86, 38, 0.80),
        (34, 12, 0.85),
        (11, 0, 1.00),
    ]
    for pass in passes {
        let ring = glowRing(
            size: size,
            outline: bodyPath,
            thickness: u(pass.thickness),
            blur: u(pass.blur),
            gradient: rim,
            across: body
        )
        context.saveGState()
        context.setAlpha(pass.alpha)
        context.draw(ring, in: canvas)
        context.restoreGState()
    }

    // Bars, tallest in the middle, so it reads as a voice rather than as a chart. At 16pt
    // five of them smear into one blob, so the smallest size gets a simplified three.
    let white = rgb(0.96, 0.96, 0.97)
    let amber = rgb(1.00, 0.78, 0.20)
    let red = rgb(1.00, 0.24, 0.18)
    let tiny = size < 32
    let barWidth = u(tiny ? 116 : 62)
    let gap = u(tiny ? 84 : 42)
    let heights: [CGFloat] = (tiny ? [250, 424, 250] : [170, 300, 424, 300, 170]).map(u)
    let colors: [CGColor] = tiny ? [amber, red, amber] : [white, amber, red, amber, white]

    let count = heights.count
    let peak = count / 2
    let totalWidth = barWidth * CGFloat(count) + gap * CGFloat(count - 1)
    var x = body.midX - totalWidth / 2

    for index in 0..<count {
        let path = barPath(x: x, height: heights[index], width: barWidth, centerY: body.midY)
        context.saveGState()
        if index == peak {
            // The peak is the whole point of the app, so let it burn a little.
            context.setShadow(offset: .zero, blur: u(46), color: rgb(1.00, 0.20, 0.14, 0.95))
        }
        context.addPath(path)
        context.setFillColor(colors[index])
        context.fillPath()
        context.restoreGState()
        x += barWidth + gap
    }

    // A faint wash across the top keeps the dark face from looking flat.
    let gloss = CGGradient(
        colorsSpace: space,
        colors: [rgb(1, 1, 1, 0.10), rgb(1, 1, 1, 0)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gloss,
        start: CGPoint(x: body.midX, y: body.maxY),
        end: CGPoint(x: body.midX, y: body.midY),
        options: []
    )

    context.restoreGState()
    return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode \(url.lastPathComponent)")
    }
    try! data.write(to: url)
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(1)
}

let output = URL(fileURLWithPath: arguments[1])
try? FileManager.default.removeItem(at: output)
try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let variants: [(point: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
    (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

for variant in variants {
    let pixels = variant.point * variant.scale
    let suffix = variant.scale == 2 ? "@2x" : ""
    let name = "icon_\(variant.point)x\(variant.point)\(suffix).png"
    write(makeIcon(size: CGFloat(pixels)), to: output.appendingPathComponent(name))
}

print("Wrote \(variants.count) images to \(output.path)")
