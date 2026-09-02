import AppKit
import SwiftUI

@main
struct TokenrashApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = BudgetStore()
    var iap: IAPSession!
    var statusItem: NSStatusItem!
    var overlay: OverlayPanel!
    private var hosting: NSHostingView<AnyView>!
    private var badgeTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        iap = IAPSession(store: store)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Tokenrash")
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let root = OverlayView(onSignIn: { [weak self] in self?.iap.signIn() })
            .environment(store)
        hosting = NSHostingView(rootView: AnyView(root))
        hosting.frame = NSRect(x: 0, y: 0, width: 296, height: 436)

        overlay = OverlayPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.level = .floating
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlay.isMovableByWindowBackground = true
        overlay.hidesOnDeactivate = false
        overlay.isReleasedWhenClosed = false
        overlay.contentView = hosting
        overlay.ignoresMouseEvents = false

        positionOverlay()
        overlay.orderFrontRegardless()

        iap.start()
        badgeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncBadge() }
        }
        syncBadge()
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
            return
        }
        if overlay.isVisible {
            overlay.orderOut(nil)
        } else {
            overlay.orderFrontRegardless()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: overlay.isVisible ? "Hide sandclock" : "Show sandclock", action: #selector(toggleOverlay), keyEquivalent: "")
        menu.addItem(withTitle: store.budget == nil ? "Sign in…" : "Refresh now", action: #selector(signInOrRefresh), keyEquivalent: "")
        menu.addItem(withTitle: "Inspect /me payload", action: #selector(inspect), keyEquivalent: "")
        menu.addItem(.separator())
        let clickThrough = menu.addItem(withTitle: "Click through", action: #selector(toggleClickThrough), keyEquivalent: "")
        clickThrough.state = overlay.ignoresMouseEvents ? .on : .off
        menu.addItem(.separator())
        if store.budget != nil {
            menu.addItem(withTitle: "Sign out", action: #selector(signOut), keyEquivalent: "")
        }
        menu.addItem(withTitle: "Quit Tokenrash", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleOverlay() {
        overlay.isVisible ? overlay.orderOut(nil) : overlay.orderFrontRegardless()
    }

    @objc private func signInOrRefresh() {
        iap.signIn()
    }

    @objc private func inspect() {
        iap.inspectPayload()
    }

    @objc private func toggleClickThrough() {
        overlay.ignoresMouseEvents.toggle()
        if overlay.ignoresMouseEvents {
            overlay.orderFrontRegardless()
        }
    }

    @objc private func signOut() {
        iap.signOut()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func positionOverlay() {
        if let saved = UserDefaults.standard.string(forKey: "overlay.frame") {
            let rect = NSRectFromString(saved)
            if rect.width > 40, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) {
                overlay.setFrame(rect, display: true)
                return
            }
        }
        guard let screen = NSScreen.main else { return }
        let frame = overlay.frame
        let x = screen.visibleFrame.maxX - frame.width - 24
        let y = screen.visibleFrame.minY + 48
        overlay.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func syncBadge() {
        if let budget = store.budget {
            statusItem.button?.title = TokenFormat.percent(budget.remainingFraction)
            statusItem.button?.toolTip = "\(TokenFormat.tokens(budget.remaining)) of \(TokenFormat.tokens(budget.limit)) left today"
            statusItem.button?.contentTintColor = budget.isCritical ? NSColor.systemRed : nil
        } else {
            statusItem.button?.title = ""
            statusItem.button?.toolTip = "Tokenrash — sign in to load daily budget"
            statusItem.button?.contentTintColor = nil
        }
        UserDefaults.standard.set(NSStringFromRect(overlay.frame), forKey: "overlay.frame")
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
