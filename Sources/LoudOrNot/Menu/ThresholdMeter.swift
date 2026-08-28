import AppKit
import LoudOrNotCore
import SwiftUI

/// A segmented input meter in the style of the microphone level in System Settings.
/// Segments light up green, yellow, then red as your voice crosses the thresholds, and
/// the two thresholds are markers you drag along the same scale.
struct ThresholdMeter: View {
    var levelDB: Double
    var warnDB: Double
    var loudDB: Double
    var setWarnDB: (Double) -> Void
    var setLoudDB: (Double) -> Void

    private enum Handle { case warn, loud }
    @State private var dragging: Handle?
    @State private var isOverHandle = false

    private let trackHeight: CGFloat = 18
    private let handleHeight: CGFloat = 26
    private let segmentCount = 32
    private let segmentGap: CGFloat = 2
    private let labelWidth: CGFloat = 30
    private let labelHeight: CGFloat = 13
    /// Plain yellow washes out against the panel material, so the warn colour is a
    /// deeper amber.
    private let warnColor = Color(red: 0.82, green: 0.58, blue: 0.04)
    private let loudColor = Color(red: 0.90, green: 0.16, blue: 0.13)
    /// Unlit zone segments are hollow: a full-strength outline so the colour is legible
    /// at a glance, over a wash faint enough that a lit segment still reads as solid.
    private let unlitZoneFillOpacity: Double = 0.14
    /// A press has to land this close to a marker to move it, so a stray click on the
    /// bar cannot fling a threshold across the scale.
    private let grabRadius: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            VStack(alignment: .leading, spacing: 3) {
                ZStack(alignment: .leading) {
                    segments
                    handle(color: warnColor, x: position(warnDB) * width, isActive: dragging == .warn)
                    handle(color: loudColor, x: position(loudDB) * width, isActive: dragging == .loud)
                }
                .frame(width: width, height: handleHeight)
                .contentShape(Rectangle())
                .gesture(dragGesture(width: width))
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        setHovering(handle(near: point.x, width: width) != nil)
                    case .ended:
                        setHovering(false)
                    }
                }

                labels(width: width)
            }
        }
        .frame(height: handleHeight + labelHeight + 3)
    }

    /// Each threshold's value rides along underneath its marker, nudged apart when the
    /// two markers come close enough for the numbers to collide.
    private func labels(width: CGFloat) -> some View {
        var warnX = position(warnDB) * width - labelWidth / 2
        var loudX = position(loudDB) * width - labelWidth / 2
        let minimumGap = labelWidth + 2
        if loudX - warnX < minimumGap {
            let center = (warnX + loudX) / 2
            warnX = center - minimumGap / 2
            loudX = center + minimumGap / 2
        }
        warnX = min(max(warnX, 0), width - labelWidth)
        loudX = min(max(loudX, 0), width - labelWidth)

        return ZStack(alignment: .topLeading) {
            label(warnDB, color: warnColor).offset(x: warnX)
            label(loudDB, color: loudColor).offset(x: loudX)
        }
        .frame(width: width, height: labelHeight, alignment: .topLeading)
    }

    private func label(_ value: Double, color: Color) -> some View {
        Text(String(format: "%.0f", value))
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: labelWidth, alignment: .center)
    }

    private var segments: some View {
        HStack(spacing: segmentGap) {
            ForEach(0..<segmentCount, id: \.self) { index in
                let style = style(forSegment: index)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(style.fill)
                    .overlay {
                        if let outline = style.outline {
                            RoundedRectangle(cornerRadius: 1.5)
                                .strokeBorder(outline, lineWidth: 1)
                        }
                    }
            }
        }
        .frame(height: trackHeight)
        .animation(.linear(duration: 0.06), value: levelDB)
    }

    private struct SegmentStyle {
        var fill: Color
        var outline: Color?
    }

    /// Lit segments are solid; unlit ones in the warn and loud zones are outlined in the
    /// same colour so the ranges stay readable when the room is quiet.
    private func style(forSegment index: Int) -> SegmentStyle {
        let midpoint = (Double(index) + 0.5) / Double(segmentCount)
        let db = Settings.Meter.minDB
            + midpoint * (Settings.Meter.maxDB - Settings.Meter.minDB)
        let isLit = Double(position(levelDB)) >= midpoint

        if db >= loudDB {
            return isLit
                ? SegmentStyle(fill: loudColor)
                : SegmentStyle(fill: loudColor.opacity(unlitZoneFillOpacity), outline: loudColor)
        }
        if db >= warnDB {
            return isLit
                ? SegmentStyle(fill: warnColor)
                : SegmentStyle(fill: warnColor.opacity(unlitZoneFillOpacity), outline: warnColor)
        }
        return isLit
            ? SegmentStyle(fill: .green)
            : SegmentStyle(fill: Color.primary.opacity(0.10))
    }

    private func handle(color: Color, x: CGFloat, isActive: Bool) -> some View {
        let width: CGFloat = isActive ? 6 : 4
        return Capsule()
            .fill(color)
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
            .frame(width: width, height: handleHeight)
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
            .offset(x: x - width / 2)
            .animation(.easeOut(duration: 0.12), value: isActive)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let handle = dragging ?? handle(near: value.startLocation.x, width: width)
                else { return }
                dragging = handle
                let db = decibels(atX: value.location.x, width: width)
                switch handle {
                case .warn: setWarnDB(db)
                case .loud: setLoudDB(db)
                }
            }
            .onEnded { _ in dragging = nil }
    }

    /// The closer marker, but only if the point is actually near one.
    private func handle(near x: CGFloat, width: CGFloat) -> Handle? {
        let warnDistance = abs(x - position(warnDB) * width)
        let loudDistance = abs(x - position(loudDB) * width)
        guard min(warnDistance, loudDistance) <= grabRadius else { return nil }
        return warnDistance <= loudDistance ? .warn : .loud
    }

    private func setHovering(_ hovering: Bool) {
        guard hovering != isOverHandle else { return }
        isOverHandle = hovering
        if hovering {
            NSCursor.resizeLeftRight.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func decibels(atX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return Settings.Meter.minDB }
        let fraction = min(max(Double(x / width), 0), 1)
        return Settings.Meter.minDB + fraction * (Settings.Meter.maxDB - Settings.Meter.minDB)
    }

    private func position(_ db: Double) -> CGFloat {
        CGFloat(
            LevelMath.meterPosition(
                forDB: db,
                minDB: Settings.Meter.minDB,
                maxDB: Settings.Meter.maxDB
            )
        )
    }
}
