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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
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
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        let root = OverlayView(onSignIn: { [weak self] in self?.iap.signIn() })
            .environment(store)
        hosting = NSHostingView(rootView: AnyView(root))
        hosting.frame = NSRect(x: 0, y: 0, width: 200, height: 300)
        hosting.autoresizingMask = [.width, .height]

        let container = OverlayContainer(frame: hosting.frame)
        container.addSubview(hosting)

        let handleSize: CGFloat = 30
        let handlePad: CGFloat = 6
        let handle = ResizeHandleView(frame: NSRect(
            x: container.bounds.maxX - handleSize - handlePad,
            y: handlePad,
            width: handleSize,
            height: handleSize
        ))
        handle.autoresizingMask = [.minXMargin, .maxYMargin]
        container.addSubview(handle)

        overlay = OverlayPanel(
            contentRect: container.frame,
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
        overlay.minSize = NSSize(width: ResizeHandleView.minWidth, height: ResizeHandleView.minWidth * ResizeHandleView.aspect)
        overlay.maxSize = NSSize(width: ResizeHandleView.maxWidth, height: ResizeHandleView.maxWidth * ResizeHandleView.aspect)
        overlay.contentView = container
        overlay.ignoresMouseEvents = false

        positionOverlay()
        overlay.orderFrontRegardless()

        iap.start()
        store.alarms.onTrip = { [weak self] in
            self?.overlay.orderFrontRegardless()
        }
        AppInstall.applyPendingLaunchAtLogin()
        badgeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncBadge() }
        }
        syncBadge()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: overlay.isVisible ? "Hide widget" : "Show widget", action: #selector(toggleOverlay), keyEquivalent: "")
        menu.addItem(withTitle: store.budget == nil ? "Sign in…" : "Refresh now", action: #selector(signInOrRefresh), keyEquivalent: "")
        menu.addItem(withTitle: "Inspect /me payload", action: #selector(inspect), keyEquivalent: "")
        menu.addItem(.separator())
        let clickThrough = menu.addItem(withTitle: "Click through", action: #selector(toggleClickThrough), keyEquivalent: "")
        clickThrough.state = overlay.ignoresMouseEvents ? .on : .off
        menu.addItem(withTitle: "Reset size", action: #selector(resetSize), keyEquivalent: "")
        let preview = NSMenu()
        preview.addItem(withTitle: "10% left — bell", action: #selector(previewTen), keyEquivalent: "")
        preview.addItem(withTitle: "5% left — bells", action: #selector(previewFive), keyEquivalent: "")
        preview.addItem(withTitle: "1% left — siren", action: #selector(previewSiren), keyEquivalent: "")
        preview.addItem(.separator())
        preview.addItem(withTitle: "Play all", action: #selector(previewAllWarnings), keyEquivalent: "")
        for item in preview.items { item.target = self }
        let previewItem = NSMenuItem(title: "Preview warnings", action: nil, keyEquivalent: "")
        previewItem.submenu = preview
        menu.addItem(previewItem)
        menu.addItem(.separator())
        if !AppInstall.isInApplications {
            menu.addItem(withTitle: "Install to Applications…", action: #selector(installToApplications), keyEquivalent: "")
        }
        let login = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.state = AppInstall.launchesAtLogin ? .on : .off
        menu.addItem(.separator())
        if store.budget != nil {
            menu.addItem(withTitle: "Sign out", action: #selector(signOut), keyEquivalent: "")
        }
        menu.addItem(withTitle: "Quit Tokenrash", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
    }

    @objc private func toggleOverlay() {
        overlay.isVisible ? overlay.orderOut(nil) : overlay.orderFrontRegardless()
    }

    @objc private func signInOrRefresh() {
        if store.budget == nil {
            iap.signIn()
        } else {
            iap.refreshNow()
        }
    }

    @objc private func inspect() {
        iap.inspectPayload()
    }

    @objc private func previewTen() {
        overlay.orderFrontRegardless()
        store.previewWarning(TokenrashConfig.alarmSteps[0])
    }

    @objc private func previewFive() {
        overlay.orderFrontRegardless()
        store.previewWarning(TokenrashConfig.alarmSteps[1])
    }

    @objc private func previewSiren() {
        overlay.orderFrontRegardless()
        store.previewWarning(TokenrashConfig.alarmSteps[2])
    }

    @objc private func previewAllWarnings() {
        overlay.orderFrontRegardless()
        store.previewAllWarnings()
    }

    @objc private func toggleClickThrough() {
        overlay.ignoresMouseEvents.toggle()
        if overlay.ignoresMouseEvents {
            overlay.orderFrontRegardless()
        }
    }

    @objc private func installToApplications() {
        do {
            try AppInstall.installAndRelaunch(enableLogin: false)
        } catch {
            presentInstallError(error)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if AppInstall.isInApplications {
                try AppInstall.setLaunchesAtLogin(!AppInstall.launchesAtLogin)
                return
            }
            if AppInstall.launchesAtLogin {
                try AppInstall.setLaunchesAtLogin(false)
                return
            }
            try AppInstall.installAndRelaunch(enableLogin: true)
        } catch {
            presentInstallError(error)
        }
    }

    private func presentInstallError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(error: error)
        alert.messageText = "Could not install Tokenrash"
        alert.runModal()
    }

    @objc private func signOut() {
        iap.signOut()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func resetSize() {
        var frame = overlay.frame
        let oldHeight = frame.height
        frame.size = NSSize(width: 200, height: 300)
        frame.origin.y += oldHeight - 300
        overlay.setFrame(frame, display: true)
        UserDefaults.standard.set(NSStringFromRect(overlay.frame), forKey: "overlay.frame.v2")
    }

    private func positionOverlay() {
        if let saved = UserDefaults.standard.string(forKey: "overlay.frame.v2") {
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
            statusItem.button?.title = TokenFormat.usd(budget.remaining)
            statusItem.button?.toolTip = "\(TokenFormat.usd(budget.remaining)) left out of \(TokenFormat.usd(budget.limit)) today"
            if store.isSiren {
                let on = Int(Date().timeIntervalSince1970 * 2) % 2 == 0
                statusItem.button?.contentTintColor = on ? NSColor.systemRed : nil
            } else {
                statusItem.button?.contentTintColor = budget.isCritical ? NSColor.systemRed : nil
            }
        } else {
            statusItem.button?.title = ""
            statusItem.button?.toolTip = "Tokenrash — sign in to load daily budget"
            statusItem.button?.contentTintColor = nil
        }
        UserDefaults.standard.set(NSStringFromRect(overlay.frame), forKey: "overlay.frame.v2")
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Clear container so the hourglass stays draggable except on the resize handle.
final class OverlayContainer: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { nil }
}
