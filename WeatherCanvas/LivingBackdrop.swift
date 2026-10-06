import CoreGraphics
import SwiftUI

enum DaydreamingPalette {
    // The four landscape panes in Daydreaming.icon, from sunrise to evening.
    static let colors: [Color] = [
        Color(red: 1, green: 0.64706, blue: 0.14902),
        Color(red: 1, green: 0.41961, blue: 0.27059),
        Color(red: 0.82353, green: 0.22353, blue: 0.56078),
        Color(red: 0.30980, green: 0.41961, blue: 1),
    ]
}

/// A bounded impulse opposite to window movement, followed by a damped return.
struct LogoWindowInertia {
    private var previousOrigin: CGPoint?
    private var impulse = CGSize.zero
    private var impulseTime = 0.0

    mutating func moved(to origin: CGPoint, at time: TimeInterval) {
        defer { previousOrigin = origin }
        guard let previousOrigin else { return }
        let current = offset(at: time)
        impulse = CGSize(width: min(12, max(-12, current.width - (origin.x - previousOrigin.x) * 0.12)),
                         height: min(12, max(-12, current.height + (origin.y - previousOrigin.y) * 0.12)))
        impulseTime = time
    }

    func offset(at time: TimeInterval) -> CGSize {
        let elapsed = max(0, time - impulseTime)
        guard elapsed < 3 else { return .zero }
        let decay = exp(-elapsed * 3.5) * cos(elapsed * 7)
        return CGSize(width: impulse.width * decay, height: impulse.height * decay)
    }
}

/// Soft brand color behind the workspace. The foreground picture stays untouched.
struct LogoBackdrop: View {
    let isActive: Bool
    let inertia: LogoWindowInertia
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var animates: Bool {
        LivingBackdropPolicy.animates(requested: isActive, visible: visible, sceneActive: scenePhase == .active,
                                      reduceMotion: reduceMotion, lowPower: lowPower,
                                      reduceTransparency: reduceTransparency, increasedContrast: contrast == .increased)
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if !reduceTransparency && contrast != .increased {
                if animates {
                    TimelineView(.animation(minimumInterval: 1.0 / 15)) { timeline in
                        panes(time: timeline.date.timeIntervalSinceReferenceDate)
                    }
                } else { panes(time: nil) }
            }
        }
        .clipped().allowsHitTesting(false).accessibilityHidden(true)
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func panes(time: TimeInterval?) -> some View {
        Canvas { context, size in
            // The site's peach, rose and lavender wash, kept behind native controls.
            let phase = (time ?? 0) * .pi * 2 / 48
            let offset = time.map { inertia.offset(at: $0) } ?? .zero
            let drift = time == nil ? 0 : sin(phase) * 5
            let strength = colorScheme == .dark ? 0.14 : 0.34
            let colors = [Color(red: 0.97, green: 0.79, blue: 0.44),
                          Color(red: 0.95, green: 0.64, blue: 0.65),
                          Color(red: 0.66, green: 0.64, blue: 0.93)]
            let centers = [CGPoint(x: size.width * 0.05, y: size.height * 0.03),
                           CGPoint(x: size.width * 0.65, y: size.height * 0.45),
                           CGPoint(x: size.width * 0.8, y: size.height * 1.04)]
            for index in colors.indices {
                let center = CGPoint(x: centers[index].x + offset.width * 0.5,
                                     y: centers[index].y + drift + offset.height * 0.5)
                context.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .radialGradient(Gradient(colors: [colors[index].opacity(strength),
                                                                    colors[index].opacity(0)]),
                                                   center: center, startRadius: 0,
                                                   endRadius: max(size.width, size.height) * 0.85))
            }
        }
    }

}

struct CreationStepHeading: View {
    let number: Int
    let title: String
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 8) {
            let color = DaydreamingPalette.colors[min(3, max(0, number - 1))]
            Text("\(number)").font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary).frame(width: 20, height: 20)
                .background(color.opacity(contrast == .increased ? 0 : 0.14), in: .circle)
                .overlay { Circle().strokeBorder(color.opacity(contrast == .increased ? 1 : 0.3), lineWidth: 1) }
                .accessibilityHidden(true)
            Text(title).font(.headline)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(number): \(title)")
        .accessibilityAddTraits(.isHeader)
    }
}

/// A tiny image sample supplies color, never pixels, to the animated background.
struct LivingBackdropPalette: Equatable, Sendable {
    struct RGB: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
    }

    let colors: [RGB]
    static let warm = LivingBackdropPalette(colors: [
        RGB(red: 0.74, green: 0.61, blue: 0.45),
        RGB(red: 0.64, green: 0.59, blue: 0.57),
        RGB(red: 0.76, green: 0.68, blue: 0.54),
    ])

    static func sample(_ image: CGImage) -> LivingBackdropPalette {
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: bytes.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                            | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return .warm }
        var totals = Array(repeating: [Double](repeating: 0, count: 4), count: 3)
        for y in 0..<side {
            for x in 0..<side {
                let index = (y * side + x) * 4
                let alpha = Double(pixels[index + 3]) / 255
                guard alpha > 0.05 else { continue }
                let region = y >= side / 2 ? 2 : (x < side / 2 ? 0 : 1)
                for channel in 0..<3 { totals[region][channel] += Double(pixels[index + channel]) / 255 }
                totals[region][3] += alpha
            }
        }
        let colors = totals.enumerated().map { index, total -> RGB in
            guard total[3] > 0 else { return warm.colors[index] }
            let raw = total.prefix(3).map { min(1, max(0, $0 / total[3])) }
            let luminance = raw[0] * 0.2126 + raw[1] * 0.7152 + raw[2] * 0.0722
            let gentle = raw.map { $0 * 0.58 + luminance * 0.42 }
            return RGB(red: gentle[0], green: gentle[1], blue: gentle[2])
        }
        return LivingBackdropPalette(colors: colors)
    }
}

enum LivingBackdropPolicy {
    static func animates(requested: Bool, visible: Bool, sceneActive: Bool,
                         reduceMotion: Bool, lowPower: Bool, reduceTransparency: Bool,
                         increasedContrast: Bool) -> Bool {
        requested && visible && sceneActive && !reduceMotion && !lowPower
            && !reduceTransparency && !increasedContrast
    }
}

/// Broad, flowing bands echo the icon's landscape curves without moving the picture.
struct LivingBackdrop: View {
    var palette: LivingBackdropPalette = .warm
    var animates = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var shouldAnimate: Bool {
        LivingBackdropPolicy.animates(requested: animates, visible: visible,
                                      sceneActive: scenePhase == .active, reduceMotion: reduceMotion,
                                      lowPower: lowPower, reduceTransparency: reduceTransparency,
                                      increasedContrast: contrast == .increased)
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if !reduceTransparency && contrast != .increased {
                if shouldAnimate {
                    TimelineView(.animation(minimumInterval: 1.0 / 12)) { timeline in
                        ribbons(phase: timeline.date.timeIntervalSinceReferenceDate * .pi * 2 / 28)
                    }
                } else {
                    ribbons(phase: 0)
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func ribbons(phase: Double) -> some View {
        Canvas { context, size in
            let colors = palette.colors.count == 3 ? palette.colors : LivingBackdropPalette.warm.colors
            let strength = colorScheme == .dark ? 0.25 : 0.19
            let drift = sin(phase) * size.height * 0.018
            let wash = Gradient(colors: [colors[0].color.opacity(strength),
                                         colors[1].color.opacity(strength * 0.55),
                                         colors[2].color.opacity(strength)])
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(wash, startPoint: .zero,
                                               endPoint: CGPoint(x: size.width, y: size.height)))
            for index in 0..<3 {
                let base = size.height * (0.2 + Double(index) * 0.23)
                let bend = cos(phase + Double(index) * 1.3) * size.height * 0.014
                let path = ribbon(size: size, baseline: base + drift, bend: bend)
                let gradient = Gradient(colors: [colors[index].color.opacity(strength * 0.65),
                                                 colors[(index + 1) % 3].color.opacity(0.015),
                                                 colors[index].color.opacity(strength * 0.48)])
                context.fill(path, with: .linearGradient(gradient,
                             startPoint: CGPoint(x: 0, y: base),
                             endPoint: CGPoint(x: size.width, y: base + size.height * 0.22)))
            }
        }
    }

    private func ribbon(size: CGSize, baseline: CGFloat, bend: CGFloat) -> Path {
        let width = size.width
        let height = size.height
        let thickness = height * 0.19
        var path = Path()
        path.move(to: CGPoint(x: -width * 0.1, y: baseline + height * 0.12))
        path.addCurve(to: CGPoint(x: width * 1.1, y: baseline + height * 0.015),
                      control1: CGPoint(x: width * 0.28, y: baseline - height * 0.14 + bend),
                      control2: CGPoint(x: width * 0.65, y: baseline + height * 0.13 - bend))
        path.addLine(to: CGPoint(x: width * 1.1, y: baseline + thickness))
        path.addCurve(to: CGPoint(x: -width * 0.1, y: baseline + thickness + height * 0.12),
                      control1: CGPoint(x: width * 0.68, y: baseline + thickness + height * 0.08 - bend),
                      control2: CGPoint(x: width * 0.3, y: baseline + thickness - height * 0.14 + bend))
        path.closeSubpath()
        return path
    }
}
