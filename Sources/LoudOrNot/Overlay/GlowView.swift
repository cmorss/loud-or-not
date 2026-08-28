import AppKit
import LoudOrNotCore
import QuartzCore

/// Draws the pulsing border. Frequency, colour and thickness are all continuous functions
/// of intensity, driven by a phase accumulator so the pulse speeds up smoothly instead of
/// restarting whenever the level changes.
final class GlowView: NSView {
    private enum Metrics {
        static let thinThickness: Double = 55
        static let wideThickness: Double = 130
        static let cornerRadius: Double = 34
    }

    /// Called once the glow has finished fading out, so the window can be ordered away.
    var onFadedOut: (() -> Void)?

    private let thinLayer = CALayer()
    private let wideLayer = CALayer()
    private let thinMask = CALayer()
    private let wideMask = CALayer()

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var phase: Double = 0
    private var presence: Double = 0
    private var renderIntensity: Double = 0
    private var targetEngaged = false
    private var targetIntensity: Double = 0
    private var maskedSize: CGSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        for (glow, mask) in [(thinLayer, thinMask), (wideLayer, wideMask)] {
            glow.mask = mask
            glow.opacity = 0
            glow.backgroundColor = GlowPalette.color(for: 0)
            mask.contentsGravity = .resize
            layer?.addSublayer(glow)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var isFlipped: Bool { true }

    func setState(engaged: Bool, intensity: Double) {
        targetEngaged = engaged
        targetIntensity = min(max(intensity, 0), 1)
        if engaged { startDisplayLink() }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [thinLayer, wideLayer, thinMask, wideMask] {
            layer.frame = bounds
        }
        CATransaction.commit()
        rebuildMasksIfNeeded()
    }

    private func rebuildMasksIfNeeded() {
        let size = bounds.size
        guard size.width > 1, size.height > 1, size != maskedSize else { return }
        maskedSize = size

        DispatchQueue.global(qos: .userInitiated).async {
            let thin = GlowMask.make(
                size: size, thickness: Metrics.thinThickness, cornerRadius: Metrics.cornerRadius
            )
            let wide = GlowMask.make(
                size: size, thickness: Metrics.wideThickness, cornerRadius: Metrics.cornerRadius
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, self.maskedSize == size else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.thinMask.contents = thin
                self.wideMask.contents = wide
                CATransaction.commit()
            }
        }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        lastTimestamp = CACurrentMediaTime()
        let link = displayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step() {
        let now = CACurrentMediaTime()
        let deltaTime = min(max(now - lastTimestamp, 0), 1.0 / 15)
        lastTimestamp = now

        let targetPresence = targetEngaged ? 1.0 : 0.0
        let presenceTau = targetPresence > presence ? 0.18 : 0.6
        presence += (targetPresence - presence) * (1 - exp(-deltaTime / presenceTau))
        renderIntensity += (targetIntensity - renderIntensity) * (1 - exp(-deltaTime / 0.35))

        phase += 2 * .pi * LevelMath.pulseFrequency(intensity: renderIntensity) * deltaTime
        if phase > 2 * .pi { phase -= 2 * .pi }

        if !targetEngaged, presence < 0.004 {
            presence = 0
            renderIntensity = 0
            phase = 0
            apply()
            stopDisplayLink()
            onFadedOut?()
            return
        }
        apply()
    }

    private func apply() {
        let pulse = 0.5 + 0.5 * sin(phase - .pi / 2)
        let low = LevelMath.lerp(0.12, 0.35, renderIntensity)
        let high = LevelMath.lerp(0.60, 1.00, renderIntensity)
        let alpha = LevelMath.lerp(low, high, pulse) * presence
        let color = GlowPalette.color(for: renderIntensity)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        thinLayer.backgroundColor = color
        wideLayer.backgroundColor = color
        thinLayer.opacity = Float(alpha * LevelMath.lerp(1.0, 0.15, renderIntensity))
        wideLayer.opacity = Float(alpha * LevelMath.lerp(0.15, 1.0, renderIntensity))
        CATransaction.commit()
    }
}
