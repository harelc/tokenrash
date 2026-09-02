import SwiftUI

enum Palette {
    static let brass = Color(red: 0.76, green: 0.60, blue: 0.38)
    static let brassLite = Color(red: 0.90, green: 0.78, blue: 0.55)
    static let brassDark = Color(red: 0.38, green: 0.26, blue: 0.12)
    static let sand = Color(red: 0.93, green: 0.80, blue: 0.46)
    static let sandDeep = Color(red: 0.74, green: 0.48, blue: 0.18)
    static let ember = Color(red: 0.86, green: 0.28, blue: 0.16)
    static let soot = Color(red: 0.06, green: 0.05, blue: 0.04)
    static let parchment = Color(red: 0.93, green: 0.88, blue: 0.76)
}

struct HourglassGeom {
    let rect: CGRect

    var cx: CGFloat { rect.midX }
    var topY: CGFloat { rect.minY }
    var bottomY: CGFloat { rect.maxY }
    var neckY: CGFloat { rect.midY }
    var height: CGFloat { rect.height }

    func halfWidth(atY y: CGFloat) -> CGFloat {
        let t = (y - topY) / max(height, 1)
        let d = abs(t - 0.5) * 2
        let eased = d * d * (3 - 2 * d)
        let neck = rect.width * 0.028
        let bulb = rect.width * 0.42
        return neck + (bulb - neck) * eased
    }

    func outline() -> Path {
        var path = Path()
        let steps = 56
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
        let steps = max(8, Int((hi - lo) / 2))
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

struct Grain: Identifiable {
    let id: Int
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var length: CGFloat
    var rotation: Double
    var spin: Double
}

struct HourglassView: View {
    var remainingFraction: Double
    var usedTokens: Double
    var limitTokens: Double
    var caption: String
    var plate: String
    var isDemo: Bool
    var reduceMotion: Bool

    @State private var grains: [Grain] = []
    @State private var nextID = 0

    var usedFraction: Double { 1 - remainingFraction }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 : 1.0 / 40.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let glassRect = CGRect(x: size.width * 0.18, y: size.height * 0.11, width: size.width * 0.64, height: size.height * 0.62)
                let geom = HourglassGeom(rect: glassRect)
                let sandColor = sandTone(usedFraction)

                drawGlow(context: &context, size: size, used: usedFraction)
                drawCaps(context: &context, size: size, glass: glassRect, brassTop: true)

                let outline = geom.outline()
                context.fill(outline, with: .color(Palette.soot.opacity(0.55)))

                var inner = context
                inner.clipToLayer { $0.fill(outline, with: .color(.white)) }

                let topFull = geom.neckY - geom.topY - 10
                let topSand = max(4, topFull * remainingFraction)
                let topStart = geom.neckY - topSand
                if remainingFraction > 0.01 {
                    let topPath = geom.sandBand(from: topStart, to: geom.neckY - 2, time: time, wobble: 1.1)
                    inner.fill(topPath, with: .linearGradient(
                        Gradient(colors: [sandColor.opacity(0.95), sandColor.opacity(0.7)]),
                        startPoint: CGPoint(x: geom.cx, y: topStart),
                        endPoint: CGPoint(x: geom.cx, y: geom.neckY)
                    ))
                    drawTicks(context: &inner, geom: geom, from: topStart + 4, to: geom.neckY - 8, time: time, color: sandColor)
                }

                let bottomFull = geom.bottomY - geom.neckY - 10
                let bottomSand = max(usedFraction > 0.01 ? 8 : 0, bottomFull * usedFraction)
                let bottomTop = geom.bottomY - bottomSand
                if usedFraction > 0.01 {
                    let bottomPath = geom.sandBand(from: bottomTop, to: geom.bottomY - 3, time: time, wobble: 0.7)
                    inner.fill(bottomPath, with: .linearGradient(
                        Gradient(colors: [sandColor.opacity(0.75), sandColor]),
                        startPoint: CGPoint(x: geom.cx, y: bottomTop),
                        endPoint: CGPoint(x: geom.cx, y: geom.bottomY)
                    ))
                    drawTicks(context: &inner, geom: geom, from: bottomTop + 6, to: geom.bottomY - 8, time: time + 4, color: sandColor)
                }

                if remainingFraction > 0.01, remainingFraction < 0.995 {
                    var stream = Path()
                    stream.move(to: CGPoint(x: geom.cx, y: geom.neckY - 6))
                    stream.addLine(to: CGPoint(x: geom.cx, y: min(bottomTop + 2, geom.neckY + 40)))
                    inner.stroke(stream, with: .color(sandColor.opacity(0.55)), lineWidth: 2.2)
                }

                for grain in grains {
                    var tick = Path(roundedRect: CGRect(x: -grain.length * 0.2, y: -grain.length, width: grain.length * 0.4, height: grain.length), cornerRadius: 0.6)
                    tick = tick.applying(CGAffineTransform(rotationAngle: grain.rotation))
                    tick = tick.applying(CGAffineTransform(translationX: grain.x, y: grain.y))
                    inner.fill(tick, with: .color(sandColor))
                }

                context.stroke(outline, with: .linearGradient(
                    Gradient(colors: [
                        Color.white.opacity(0.55),
                        Palette.brassLite.opacity(0.35),
                        Color.white.opacity(0.12)
                    ]),
                    startPoint: CGPoint(x: glassRect.minX, y: glassRect.minY),
                    endPoint: CGPoint(x: glassRect.maxX, y: glassRect.maxY)
                ), lineWidth: 1.6)

                var highlight = Path()
                highlight.move(to: CGPoint(x: geom.cx - geom.halfWidth(atY: glassRect.minY + 18) + 6, y: glassRect.minY + 16))
                highlight.addQuadCurve(
                    to: CGPoint(x: geom.cx - 8, y: geom.neckY - 10),
                    control: CGPoint(x: geom.cx - geom.halfWidth(atY: geom.neckY - 50) - 4, y: geom.neckY - 70)
                )
                context.stroke(highlight, with: .color(.white.opacity(0.28)), lineWidth: 1.1)

                drawCaps(context: &context, size: size, glass: glassRect, brassTop: false)
                drawPlate(context: &context, size: size, plate: plate, caption: caption, demo: isDemo)
            }
            .onChange(of: timeline.date) { _, date in
                guard !reduceMotion else { return }
                stepGrains(date: date, size: CGSize(width: 280, height: 420))
            }
        }
        .frame(width: 280, height: 420)
    }

    private func sandTone(_ used: Double) -> Color {
        if used < 0.55 {
            return Palette.sand
        }
        if used < 0.85 {
            return Palette.sandDeep
        }
        return Palette.ember
    }

    private func drawGlow(context: inout GraphicsContext, size: CGSize, used: Double) {
        let color = used > 0.9 ? Palette.ember : (used > 0.7 ? Palette.sandDeep : Palette.brass)
        let rect = CGRect(x: size.width * 0.15, y: size.height * 0.12, width: size.width * 0.7, height: size.height * 0.6)
        context.fill(
            Path(ellipseIn: rect.insetBy(dx: 10, dy: 20)),
            with: .radialGradient(
                Gradient(colors: [color.opacity(used > 0.85 ? 0.28 : 0.12), .clear]),
                center: CGPoint(x: rect.midX, y: rect.midY),
                startRadius: 10,
                endRadius: rect.width * 0.55
            )
        )
    }

    private func drawTicks(context: inout GraphicsContext, geom: HourglassGeom, from: CGFloat, to: CGFloat, time: TimeInterval, color: Color) {
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
        _ = time
    }

    private func drawCaps(context: inout GraphicsContext, size: CGSize, glass: CGRect, brassTop: Bool) {
        let capWidth = glass.width * 0.92
        let capHeight: CGFloat = 16
        let x = glass.midX - capWidth / 2
        if brassTop {
            let top = CGRect(x: x, y: glass.minY - 14, width: capWidth, height: capHeight)
            fillBrass(context: &context, rect: top)
            let ring = CGRect(x: glass.midX - 18, y: top.minY - 10, width: 36, height: 12)
            fillBrass(context: &context, rect: ring, radius: 6)
        } else {
            let bottom = CGRect(x: x, y: glass.maxY - 2, width: capWidth, height: capHeight)
            fillBrass(context: &context, rect: bottom)
            let foot = CGRect(x: x - 8, y: bottom.maxY - 4, width: capWidth + 16, height: 14)
            fillBrass(context: &context, rect: foot, radius: 3)
        }
    }

    private func fillBrass(context: inout GraphicsContext, rect: CGRect, radius: CGFloat = 4) {
        let path = Path(roundedRect: rect, cornerRadius: radius)
        context.fill(path, with: .linearGradient(
            Gradient(colors: [Palette.brassLite, Palette.brass, Palette.brassDark]),
            startPoint: CGPoint(x: rect.minX, y: rect.minY),
            endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
        ))
        context.stroke(path, with: .color(Palette.brassDark.opacity(0.7)), lineWidth: 0.6)
    }

    private func drawPlate(context: inout GraphicsContext, size: CGSize, plate: String, caption: String, demo: Bool) {
        let plateRect = CGRect(x: size.width * 0.14, y: size.height * 0.78, width: size.width * 0.72, height: 68)
        fillBrass(context: &context, rect: plateRect, radius: 8)
        let inner = plateRect.insetBy(dx: 6, dy: 6)
        context.fill(Path(roundedRect: inner, cornerRadius: 5), with: .color(Palette.brassDark.opacity(0.35)))

        let plateText = Text(plate)
            .font(.custom("Bodoni 72", size: 34))
            .foregroundColor(Palette.parchment)
        let capText = Text(demo ? "demo sand · sign in" : caption)
            .font(.system(size: 11, weight: .medium, design: .serif))
            .foregroundColor(Palette.parchment.opacity(0.78))
        context.draw(plateText, at: CGPoint(x: plateRect.midX, y: plateRect.midY - 8))
        context.draw(capText, at: CGPoint(x: plateRect.midX, y: plateRect.maxY - 16))
    }

    private func stepGrains(date: Date, size: CGSize) {
        let glassRect = CGRect(x: size.width * 0.18, y: size.height * 0.11, width: size.width * 0.64, height: size.height * 0.62)
        let geom = HourglassGeom(rect: glassRect)
        let dt: CGFloat = 1.0 / 40.0
        let bottomFull = geom.bottomY - geom.neckY - 10
        let bottomSand = max(usedFraction > 0.01 ? 8 : 0, bottomFull * usedFraction)
        let bottomTop = geom.bottomY - bottomSand

        if remainingFraction > 0.015, remainingFraction < 0.995, grains.count < 90 {
            let spawn = remainingFraction < 0.2 ? 2 : 1
            for _ in 0..<spawn {
                grains.append(Grain(
                    id: nextID,
                    x: geom.cx + CGFloat.random(in: -2...2),
                    y: geom.neckY - 2,
                    vx: CGFloat.random(in: -8...8),
                    vy: CGFloat.random(in: 55...95),
                    length: CGFloat.random(in: 3.2...5.4),
                    rotation: Double.random(in: -0.4...0.4),
                    spin: Double.random(in: -1.6...1.6)
                ))
                nextID += 1
            }
        }

        for i in grains.indices {
            grains[i].vy += 90 * dt
            grains[i].x += grains[i].vx * dt
            grains[i].y += grains[i].vy * dt
            grains[i].rotation += grains[i].spin * Double(dt)
            let hw = geom.halfWidth(atY: grains[i].y) - 2
            let minX = geom.cx - hw
            let maxX = geom.cx + hw
            if grains[i].x < minX { grains[i].x = minX; grains[i].vx = abs(grains[i].vx) * 0.3 }
            if grains[i].x > maxX { grains[i].x = maxX; grains[i].vx = -abs(grains[i].vx) * 0.3 }
        }
        grains.removeAll { $0.y > bottomTop - 1 || $0.y > geom.bottomY - 4 }
        _ = date
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
