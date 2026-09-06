import AppKit
import SwiftUI

@MainActor
enum DockIcon {
    private static let logical = CGSize(width: 128, height: 128)
    private static let scale: CGFloat = 2

    static func apply(remaining: Double, siren: Bool, badge: String?) {
        let icon = DockHourglassIcon(
            remaining: remaining,
            siren: siren,
            clock: Date().timeIntervalSinceReferenceDate
        )
        if let image = rasterize(icon) {
            image.isTemplate = false
            NSApp.applicationIconImage = image
        }
        let tile = NSApp.dockTile
        tile.badgeLabel = badge
        tile.display()
    }

    static func restore() {
        NSApp.applicationIconImage = NSImage(named: "AppIcon")
        NSApp.dockTile.badgeLabel = nil
        NSApp.dockTile.display()
    }

    private static func rasterize<V: View>(_ view: V) -> NSImage? {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: logical)
        host.wantsLayer = true
        host.layer?.isOpaque = false
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.layoutSubtreeIfNeeded()

        let pixels = Int(logical.width * scale)
        guard let src = makeRep(pixels: pixels) else { return nil }
        host.cacheDisplay(in: host.bounds, to: src)

        guard let dst = makeRep(pixels: pixels) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext(bitmapImageRep: dst) else { return nil }
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high

        let rect = NSRect(origin: .zero, size: logical)
        NSColor.clear.setFill()
        rect.fill()
        squircle(in: rect.insetBy(dx: 1, dy: 1)).addClip()
        src.draw(in: rect)

        let image = NSImage(size: logical)
        image.addRepresentation(dst)
        return image
    }

    private static func makeRep(pixels: Int) -> NSBitmapImageRep? {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        )
        rep?.size = logical
        return rep
    }

    /// macOS app-icon squircle (superellipse), so runtime `applicationIconImage`
    /// is not shown as a sharp square — the Dock does not remask those.
    private static func squircle(in rect: NSRect, n: CGFloat = 5) -> NSBezierPath {
        let path = NSBezierPath()
        let a = rect.width / 2
        let b = rect.height / 2
        let cx = rect.midX
        let cy = rect.midY
        let steps = 180
        let exp = 2 / n
        for i in 0...steps {
            let theta = (CGFloat(i) / CGFloat(steps)) * 2 * .pi
            let c = cos(theta)
            let s = sin(theta)
            let x = cx + a * copysign(pow(abs(c), exp), c)
            let y = cy + b * copysign(pow(abs(s), exp), s)
            let point = NSPoint(x: x, y: y)
            if i == 0 { path.move(to: point) }
            else { path.line(to: point) }
        }
        path.close()
        return path
    }
}

private struct DockHourglassIcon: View {
    var remaining: Double
    var siren: Bool
    var clock: TimeInterval

    var body: some View {
        ZStack {
            Palette.soot
            HourglassView(
                remainingFraction: remaining,
                reduceMotion: true,
                siren: siren,
                animate: false,
                clock: clock
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
        }
        .frame(width: 128, height: 128)
    }
}
