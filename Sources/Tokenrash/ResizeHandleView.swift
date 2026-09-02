import AppKit

/// Bottom-right resize control. Uses a mouse-tracking loop in screen space so
/// SwiftUI gestures and `isMovableByWindowBackground` cannot steal the drag.
final class ResizeHandleView: NSView {
    static let minWidth: CGFloat = 150
    static let maxWidth: CGFloat = 420
    static let aspect: CGFloat = 1.5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        toolTip = "Drag to resize"
    }

    required init?(coder: NSCoder) { nil }

    override var mouseDownCanMoveWindow: Bool { false }
    override var isFlipped: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: Self.resizeCursor)
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 7, dy: 7)
        let color = NSColor(red: 0.90, green: 0.78, blue: 0.55, alpha: 0.95)
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        // Two nested corner ticks.
        path.move(to: NSPoint(x: inset.maxX, y: inset.minY + 4))
        path.line(to: NSPoint(x: inset.maxX, y: inset.minY))
        path.line(to: NSPoint(x: inset.maxX - 4, y: inset.minY))
        path.move(to: NSPoint(x: inset.maxX, y: inset.minY + 9))
        path.line(to: NSPoint(x: inset.maxX, y: inset.minY))
        path.move(to: NSPoint(x: inset.maxX, y: inset.minY))
        path.line(to: NSPoint(x: inset.maxX - 9, y: inset.minY))
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let startFrame = window.frame
        let startPoint = NSEvent.mouseLocation
        Self.resizeCursor.set()

        while true {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            if next.type == .leftMouseUp { break }

            let now = NSEvent.mouseLocation
            let dx = now.x - startPoint.x
            let dy = now.y - startPoint.y
            // Right grows, down grows (Cocoa Y is up, so down is negative dy).
            let grow = dx - dy
            var width = startFrame.width + grow
            width = min(Self.maxWidth, max(Self.minWidth, width))
            let height = width * Self.aspect

            var frame = startFrame
            frame.size = NSSize(width: width, height: height)
            frame.origin.y = startFrame.maxY - height
            window.setFrame(frame, display: true, animate: false)
        }
        NSCursor.arrow.set()
    }

    private static var resizeCursor: NSCursor {
        return NSCursor.crosshair
    }
}
