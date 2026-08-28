import CoreGraphics
import Foundation

/// Builds the soft border falloff used as a layer mask: opaque at the screen edge,
/// fading to nothing `thickness` points inward, with rounded corners.
enum GlowMask {
    /// The mask is a smooth gradient, so half resolution is indistinguishable and
    /// keeps a full-screen mask in the single-digit megabytes.
    static let resolutionScale: Double = 0.5

    static func make(size: CGSize, thickness: Double, cornerRadius: Double, falloff: Double = 2.0) -> CGImage? {
        let width = max(2, Int(size.width * resolutionScale))
        let height = max(2, Int(size.height * resolutionScale))
        let depthLimit = max(1, thickness * resolutionScale)
        let radius = max(0, cornerRadius * resolutionScale)

        let halfWidth = Double(width) / 2
        let halfHeight = Double(height) / 2
        let boxX = max(0, halfWidth - radius)
        let boxY = max(0, halfHeight - radius)

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBufferPointer { buffer in
            for y in 0..<height {
                let pointY = abs(Double(y) + 0.5 - halfHeight) - boxY
                let rowStart = y * width * 4
                for x in 0..<width {
                    let pointX = abs(Double(x) + 0.5 - halfWidth) - boxX
                    let outside = (max(pointX, 0) * max(pointX, 0) + max(pointY, 0) * max(pointY, 0)).squareRoot()
                    let signedDistance = outside + min(max(pointX, pointY), 0) - radius
                    let depth = -signedDistance
                    let ramp = min(max(1 - depth / depthLimit, 0), 1)
                    let value = UInt8(min(255, max(0, pow(ramp, falloff) * 255)))
                    let index = rowStart + x * 4
                    buffer[index] = value
                    buffer[index + 1] = value
                    buffer[index + 2] = value
                    buffer[index + 3] = value
                }
            }
        }

        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

enum GlowPalette {
    /// Calm yellow when you have just crossed the line, angry red when you are shouting.
    static func color(for intensity: Double) -> CGColor {
        let stops: [(position: Double, rgb: (Double, Double, Double))] = [
            (0.0, (1.00, 0.86, 0.15)),
            (0.5, (1.00, 0.55, 0.08)),
            (1.0, (1.00, 0.16, 0.12)),
        ]
        let t = min(max(intensity, 0), 1)
        var lower = stops[0]
        var upper = stops[stops.count - 1]
        for index in 1..<stops.count where stops[index].position >= t {
            lower = stops[index - 1]
            upper = stops[index]
            break
        }
        let span = upper.position - lower.position
        let local = span > 0 ? (t - lower.position) / span : 0
        return CGColor(
            srgbRed: lower.rgb.0 + (upper.rgb.0 - lower.rgb.0) * local,
            green: lower.rgb.1 + (upper.rgb.1 - lower.rgb.1) * local,
            blue: lower.rgb.2 + (upper.rgb.2 - lower.rgb.2) * local,
            alpha: 1
        )
    }
}
