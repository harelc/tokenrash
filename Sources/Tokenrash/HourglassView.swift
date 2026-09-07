import SwiftUI

enum HourglassChrome {
    /// Overlay: glass tucked into brass yokes that hold the flap boards.
    case instrument
    /// Dock tile: glass with small collars, no yokes.
    case icon

    static let design = CGSize(width: 200, height: 300)
    static let yoke: CGFloat = 48

    static func glassRect(in size: CGSize, chrome: HourglassChrome) -> CGRect {
        switch chrome {
        case .instrument:
            let yoke = size.height * (Self.yoke / design.height)
            let overlap = size.height * (11 / design.height)
            return CGRect(
                x: size.width * 0.155,
                y: yoke - overlap,
                width: size.width * 0.69,
                height: size.height - 2 * yoke + 2 * overlap
            )
        case .icon:
            return CGRect(
                x: size.width * 0.16,
                y: size.height * 0.08,
                width: size.width * 0.68,
                height: size.height * 0.84
            )
        }
    }
}

enum Palette {
    static let brass = Color(red: 0.76, green: 0.60, blue: 0.38)
    static let brassLite = Color(red: 0.90, green: 0.78, blue: 0.55)
    static let brassDark = Color(red: 0.38, green: 0.26, blue: 0.12)
    static let sand = Color(red: 0.93, green: 0.80, blue: 0.46)
    static let sandDeep = Color(red: 0.74, green: 0.48, blue: 0.18)
    static let ember = Color(red: 0.86, green: 0.28, blue: 0.16)
    static let sage = Color(red: 0.52, green: 0.74, blue: 0.36)
    static let soot = Color(red: 0.06, green: 0.05, blue: 0.04)
    static let parchment = Color(red: 0.93, green: 0.88, blue: 0.76)

    /// Champagne when plenty remains, ember when the glass is almost empty.
    static func sand(remaining: Double) -> Color {
        let t = min(1, max(0, remaining))
        if t >= 0.5 {
            return mix((0.93, 0.80, 0.46), (0.52, 0.74, 0.36), (t - 0.5) / 0.5)
        }
        if t >= 0.22 {
            return mix((0.74, 0.48, 0.18), (0.93, 0.80, 0.46), (t - 0.22) / 0.28)
        }
        return mix((0.86, 0.28, 0.16), (0.74, 0.48, 0.18), t / 0.22)
    }

    private static func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> Color {
        let u = min(1, max(0, t))
        return Color(
            red: a.0 + (b.0 - a.0) * u,
            green: a.1 + (b.1 - a.1) * u,
            blue: a.2 + (b.2 - a.2) * u
        )
    }
}

struct HourglassGeom {
    let rect: CGRect
    var silhouette: GlassSilhouette = .classic
    var neckRatio: CGFloat = 0.028
    var bulbRatio: CGFloat = 0.48

    var cx: CGFloat { rect.midX }
    var topY: CGFloat { rect.minY }
    var bottomY: CGFloat { rect.maxY }
    var neckY: CGFloat { rect.midY }
    var height: CGFloat { rect.height }

    func halfWidth(atY y: CGFloat) -> CGFloat {
        let t = (y - topY) / max(height, 1)
        let d = abs(t - 0.5) * 2
        let neck = rect.width * neckRatio
        let bulb = rect.width * bulbRatio
        let blend: CGFloat
        switch silhouette {
        case .classic:
            blend = d * d * (3 - 2 * d)
        case .column:
            blend = pow(d, 2.35)
        case .toy:
            blend = d * d * (3 - 2 * d)
        case .diamond:
            blend = d
        case .blob:
            blend = d * d
        }
        return neck + (bulb - neck) * blend
    }

    func outline() -> Path {
        var path = Path()
        let steps = 28
        for i in 0...steps {
            let y = topY + height * CGFloat(i) / CGFloat(steps)
            let x = cx - halfWidth(atY: y)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        for i in stride(from: steps, through: 0, by: -1) {
            let y = topY + height * CGFloat(i) / CGFloat(steps)
            path.addLine(to: CGPoint(x: cx + halfWidth(atY: y), y: y))
        }
        path.closeSubpath()
        return path
    }

    func sandBand(from y0: CGFloat, to y1: CGFloat, time: TimeInterval, wobble: CGFloat) -> Path {
        let lo = min(y0, y1)
        let hi = max(y0, y1)
        guard hi - lo > 0.5 else { return Path() }
        var path = Path()
        let steps = max(6, Int((hi - lo) / 5))
        for i in 0...steps {
            let y = lo + (hi - lo) * CGFloat(i) / CGFloat(steps)
            let wave = CGFloat(sin(Double(y) * 0.18 + time * 1.7)) * wobble
            let x = cx - halfWidth(atY: y) + 1.2 + wave
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        for i in stride(from: steps, through: 0, by: -1) {
            let y = lo + (hi - lo) * CGFloat(i) / CGFloat(steps)
            let wave = CGFloat(sin(Double(y) * 0.18 + time * 1.7 + 0.6)) * wobble
            path.addLine(to: CGPoint(x: cx + halfWidth(atY: y) - 1.2 + wave, y: y))
        }
        path.closeSubpath()
        return path
    }
}

struct HourglassView: View {
    var remainingFraction: Double
    var usedFraction: Double? = nil
    var reduceMotion: Bool
    var siren: Bool = false
    var chrome: HourglassChrome = .instrument
    var look: WidgetLook = .horologist
    /// Frozen frame for Dock snapshots — Canvas, no Metal.
    var animate: Bool = true
    /// Used when `animate` is false so the siren can still pulse on Dock redraws.
    var clock: TimeInterval = 0

    private var used: Double { usedFraction ?? max(0, 1 - remainingFraction) }

    var body: some View {
        Group {
            if chrome == .instrument, MetalHourglass.isAvailable {
                MetalHourglassView(
                    remaining: remainingFraction,
                    used: used,
                    siren: siren,
                    look: look,
                    running: animate,
                    reduceMotion: reduceMotion
                )
            } else {
                hourglassCanvas(time: siren ? clock : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func hourglassCanvas(time: TimeInterval) -> some View {
        Canvas { context, size in
                let glassRect = HourglassChrome.glassRect(in: size, chrome: chrome)
                let geom = HourglassGeom(
                    rect: glassRect,
                    silhouette: look.silhouette,
                    neckRatio: look.neck,
                    bulbRatio: look.bulb
                )
                let pulse = sirenPulse(time: time)
                let sandColor = look.sand(remaining: remainingFraction, siren: siren, pulse: pulse)

                if siren || (remainingFraction < 0.22 && used > 0.01) {
                    drawGlow(context: &context, size: size, remaining: remainingFraction, sirenPulse: pulse)
                }
                if chrome == .icon {
                    drawCaps(context: &context, glass: glassRect, top: true)
                }

                let outline = geom.outline()
                context.fill(outline, with: .color(look.cavityFill(siren: false, pulse: 0)))

                var inner = context
                inner.clip(to: outline)

                let topFull = geom.neckY - geom.topY - 10
                let topSand = max(4, topFull * remainingFraction)
                let topStart = geom.neckY - topSand
                if remainingFraction > 0.01 {
                    let topPath = geom.sandBand(from: topStart, to: geom.neckY - 2, time: 0, wobble: 1.1 * look.wobble)
                    inner.fill(topPath, with: .linearGradient(
                        Gradient(colors: [sandColor.opacity(0.95), sandColor.opacity(0.7)]),
                        startPoint: CGPoint(x: geom.cx, y: topStart),
                        endPoint: CGPoint(x: geom.cx, y: geom.neckY)
                    ))
                    if look.showTicks {
                        drawTicks(context: &inner, geom: geom, from: topStart + 4, to: geom.neckY - 8, time: time, color: sandColor)
                    }
                }

                let bottomFull = geom.bottomY - geom.neckY - 10
                let bottomSand = max(used > 0.01 ? 8 : 0, bottomFull * used)
                let bottomTop = geom.bottomY - bottomSand
                if used > 0.01 {
                    let bottomPath = geom.sandBand(from: bottomTop, to: geom.bottomY - 3, time: 0, wobble: 0.7 * look.wobble)
                    inner.fill(bottomPath, with: .linearGradient(
                        Gradient(colors: [sandColor.opacity(0.75), sandColor]),
                        startPoint: CGPoint(x: geom.cx, y: bottomTop),
                        endPoint: CGPoint(x: geom.cx, y: geom.bottomY)
                    ))
                    if look.showTicks {
                        drawTicks(context: &inner, geom: geom, from: bottomTop + 6, to: geom.bottomY - 8, time: time + 4, color: sandColor)
                    }
                }

                if remainingFraction > 0.01, remainingFraction < 0.995 {
                    var stream = Path()
                    stream.move(to: CGPoint(x: geom.cx, y: geom.neckY - 6))
                    stream.addLine(to: CGPoint(x: geom.cx, y: min(bottomTop + 2, geom.neckY + 40)))
                    inner.stroke(stream, with: .color(sandColor.opacity(0.55)), lineWidth: look.streamWidth)
                }

                if siren {
                    inner.fill(outline, with: .color(look.cavityFill(siren: true, pulse: pulse)))
                }

                context.stroke(outline, with: .linearGradient(
                    Gradient(colors: look.rimColors(siren: siren, pulse: pulse)),
                    startPoint: CGPoint(x: glassRect.minX, y: glassRect.minY),
                    endPoint: CGPoint(x: glassRect.maxX, y: glassRect.maxY)
                ), lineWidth: siren ? look.rimWidth + 0.8 : look.rimWidth)

                var highlight = Path()
                highlight.move(to: CGPoint(x: geom.cx - geom.halfWidth(atY: glassRect.minY + 18) + 6, y: glassRect.minY + 16))
                highlight.addQuadCurve(
                    to: CGPoint(x: geom.cx - 8, y: geom.neckY - 10),
                    control: CGPoint(x: geom.cx - geom.halfWidth(atY: geom.neckY - 50) - 4, y: geom.neckY - 70)
                )
                context.stroke(highlight, with: .color(look.highlight), lineWidth: look == .jelly ? 2.2 : 1.1)

                drawCollars(context: &context, geom: geom)
                if chrome == .icon {
                    drawCaps(context: &context, glass: glassRect, top: false)
                }
            }
    }

    private func sirenPulse(time: TimeInterval) -> Double {
        guard siren else { return 0 }
        let speed = reduceMotion ? 2.2 : 8.0
        return 0.5 + 0.5 * sin(time * speed)
    }

    private func drawGlow(context: inout GraphicsContext, size: CGSize, remaining: Double, sirenPulse: Double) {
        let color = siren
            ? Color.red.opacity(0.2 + 0.55 * sirenPulse)
            : look.sand(remaining: remaining, siren: false, pulse: 0).opacity(remaining < 0.22 ? 0.32 : 0.14)
        let rect = CGRect(x: size.width * 0.15, y: size.height * 0.12, width: size.width * 0.7, height: size.height * 0.6)
        context.fill(
            Path(ellipseIn: rect.insetBy(dx: 10, dy: 20)),
            with: .radialGradient(
                Gradient(colors: [color, .clear]),
                center: CGPoint(x: rect.midX, y: rect.midY),
                startRadius: 10,
                endRadius: rect.width * 0.55
            )
        )
    }

    private func drawTicks(context: inout GraphicsContext, geom: HourglassGeom, from: CGFloat, to: CGFloat, time _: TimeInterval, color: Color) {
        guard to > from else { return }
        var rng = Seeded(seed: UInt64(from + to * 10))
        var y = from
        while y < to {
            let hw = geom.halfWidth(atY: y) - 4
            guard hw > 4 else { y += 5; continue }
            let count = Int(hw / 5)
            for i in 0..<count {
                let x = geom.cx - hw + CGFloat(i) * (hw * 2 / CGFloat(max(count, 1))) + CGFloat(rng.next() * 2.2)
                var tick = Path(roundedRect: CGRect(x: x, y: y, width: 1.1, height: 3.4), cornerRadius: 0.4)
                tick = tick.applying(CGAffineTransform(translationX: -x, y: -y)
                    .concatenating(CGAffineTransform(rotationAngle: (rng.next() - 0.5) * 0.7))
                    .concatenating(CGAffineTransform(translationX: x, y: y)))
                context.fill(tick, with: .color(color.opacity(0.55 + rng.next() * 0.4)))
            }
            y += 5.2
        }
    }

    private func drawCollars(context: inout GraphicsContext, geom: HourglassGeom) {
        let topW = geom.halfWidth(atY: geom.topY) + 7
        fillBrass(
            context: &context,
            rect: CGRect(x: geom.cx - topW, y: geom.topY - 3, width: topW * 2, height: 9),
            radius: 3
        )
        let botW = geom.halfWidth(atY: geom.bottomY) + 7
        fillBrass(
            context: &context,
            rect: CGRect(x: geom.cx - botW, y: geom.bottomY - 6, width: botW * 2, height: 9),
            radius: 3
        )
    }

    private func drawCaps(context: inout GraphicsContext, glass: CGRect, top: Bool) {
        let capWidth = glass.width * 0.92
        let capHeight: CGFloat = 16
        let x = glass.midX - capWidth / 2
        if top {
            let band = CGRect(x: x, y: glass.minY - 14, width: capWidth, height: capHeight)
            fillBrass(context: &context, rect: band)
            let ring = CGRect(x: glass.midX - 18, y: band.minY - 10, width: 36, height: 12)
            fillBrass(context: &context, rect: ring, radius: 6)
        } else {
            let band = CGRect(x: x, y: glass.maxY - 2, width: capWidth, height: capHeight)
            fillBrass(context: &context, rect: band)
            let foot = CGRect(x: x - 8, y: band.maxY - 4, width: capWidth + 16, height: 14)
            fillBrass(context: &context, rect: foot, radius: 3)
        }
    }

    private func fillBrass(context: inout GraphicsContext, rect: CGRect, radius: CGFloat = 4) {
        let path = Path(roundedRect: rect, cornerRadius: radius)
        context.fill(path, with: .linearGradient(
            Gradient(colors: [look.metalLite, look.metal, look.metalDark]),
            startPoint: CGPoint(x: rect.minX, y: rect.minY),
            endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
        ))
        context.stroke(path, with: .color(look.metalDark.opacity(0.7)), lineWidth: 0.6)
    }
}

private struct Seeded {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z % 10_000) / 10_000
    }
}
