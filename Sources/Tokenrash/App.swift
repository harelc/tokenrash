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
    private var lastDockKey: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(DockSettings.enabled ? .regular : .accessory)
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
        store.alarms.onTrip = { [weak self] step in
            guard let self else { return }
            let hidden = !self.overlay.isVisible || !self.overlay.occlusionState.contains(.visible)
            if hidden, step.id == 10 {
                self.revealOverlay()
            }
        }
        AppInstall.applyPendingLaunchAtLogin()
        NotificationCenter.default.addObserver(
            self, selector: #selector(persistOverlayFrame),
            name: NSWindow.didMoveNotification, object: overlay
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(persistOverlayFrame),
            name: NSWindow.didEndLiveResizeNotification, object: overlay
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(overlayOcclusionChanged),
            name: NSWindow.didChangeOcclusionStateNotification, object: overlay
        )
        badgeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [self] in self?.syncBadge() }
        }
        badgeTimer?.tolerance = 0.4
        syncOverlayActivity()
        syncBadge()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        revealOverlay()
        return false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        addItem(menu, overlay.isVisible ? "Hide Widget" : "Show Widget", #selector(toggleOverlay))
        addItem(menu, store.budget == nil ? "Sign In…" : "Refresh", #selector(signInOrRefresh))

        menu.addItem(.separator())
        menu.addItem(looksMenuItem())
        addToggle(menu, "Remaining", store.showTopCounter, #selector(toggleTopCounter))
        addToggle(menu, "Spent", store.showBottomCounter, #selector(toggleBottomCounter))
        addToggle(menu, "Click Through", overlay.ignoresMouseEvents, #selector(toggleClickThrough))
        addItem(menu, "Reset Size", #selector(resetSize))

        menu.addItem(.separator())
        addToggle(menu, "Sound Effects", SoundSettings.enabled, #selector(toggleSounds))
        addToggle(menu, "Show in Dock", DockSettings.enabled, #selector(toggleDock))
        addToggle(menu, "Launch at Login", AppInstall.launchesAtLogin, #selector(toggleLaunchAtLogin))

        menu.addItem(.separator())
        menu.addItem(previewMenuItem())
        addItem(menu, "Inspect Payload…", #selector(inspect))
        if !AppInstall.isInApplications {
            addItem(menu, "Install to Applications…", #selector(installToApplications))
        }

        menu.addItem(.separator())
        if store.budget != nil {
            addItem(menu, "Sign Out", #selector(signOut))
        }
        addItem(menu, "Quit Tokenrash", #selector(quit), key: "q")

        for item in menu.items { item.target = self }
    }

    private func addItem(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        menu.addItem(withTitle: title, action: action, keyEquivalent: key)
    }

    private func addToggle(_ menu: NSMenu, _ title: String, _ on: Bool, _ action: Selector) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.state = on ? .on : .off
    }

    private func looksMenuItem() -> NSMenuItem {
        let looks = NSMenu()
        for look in WidgetLook.allCases {
            let item = looks.addItem(withTitle: look.menuTitle, action: #selector(chooseLook(_:)), keyEquivalent: "")
            item.representedObject = look.rawValue
            item.state = store.look == look ? .on : .off
            item.target = self
        }
        let item = NSMenuItem(title: "Look", action: nil, keyEquivalent: "")
        item.submenu = looks
        return item
    }

    private func previewMenuItem() -> NSMenuItem {
        let preview = NSMenu()
        preview.addItem(withTitle: "10% Remaining", action: #selector(previewTen), keyEquivalent: "")
        preview.addItem(withTitle: "5% Remaining", action: #selector(previewFive), keyEquivalent: "")
        preview.addItem(withTitle: "1% Remaining", action: #selector(previewSiren), keyEquivalent: "")
        preview.addItem(withTitle: "Flap", action: #selector(previewFlap), keyEquivalent: "")
        preview.addItem(.separator())
        preview.addItem(withTitle: "Play All", action: #selector(previewAllWarnings), keyEquivalent: "")
        for item in preview.items { item.target = self }
        let item = NSMenuItem(title: "Preview Alarms", action: nil, keyEquivalent: "")
        item.submenu = preview
        return item
    }

    @objc private func toggleOverlay() {
        if overlay.isVisible {
            overlay.orderOut(nil)
            syncOverlayActivity()
        } else {
            revealOverlay()
        }
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
        revealOverlay()
        store.previewWarning(TokenrashConfig.alarmSteps[0])
    }

    @objc private func previewFive() {
        revealOverlay()
        store.previewWarning(TokenrashConfig.alarmSteps[1])
    }

    @objc private func previewSiren() {
        revealOverlay()
        store.previewWarning(TokenrashConfig.alarmSteps[2])
    }

    @objc private func previewFlap() {
        revealOverlay()
        store.previewFlap()
    }

    @objc private func previewAllWarnings() {
        revealOverlay()
        store.previewAllWarnings()
    }

    @objc private func toggleClickThrough() {
        overlay.ignoresMouseEvents.toggle()
        if overlay.ignoresMouseEvents {
            overlay.orderFrontRegardless()
        }
    }

    @objc private func toggleSounds() {
        SoundSettings.enabled.toggle()
    }

    @objc private func toggleDock() {
        DockSettings.enabled.toggle()
        applyDockVisibility()
    }

    @objc private func toggleTopCounter() {
        store.showTopCounter.toggle()
        CounterSettings.showTop = store.showTopCounter
    }

    @objc private func toggleBottomCounter() {
        store.showBottomCounter.toggle()
        CounterSettings.showBottom = store.showBottomCounter
    }

    @objc private func chooseLook(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let look = WidgetLook(rawValue: raw) else { return }
        store.look = look
        WidgetLook.stored = look
        lastDockKey = nil
        syncDockIcon()
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
        persistOverlayFrame()
    }

    @objc private func persistOverlayFrame() {
        UserDefaults.standard.set(NSStringFromRect(overlay.frame), forKey: "overlay.frame.v2")
    }

    @objc private func overlayOcclusionChanged() {
        syncOverlayActivity()
    }

    private func revealOverlay() {
        overlay.orderFrontRegardless()
        syncOverlayActivity()
    }

    private func syncOverlayActivity() {
        store.overlayActive = overlay.isVisible && overlay.occlusionState.contains(.visible)
    }

    private func positionOverlay() {
        if let saved = UserDefaults.standard.string(forKey: "overlay.frame.v2") {
            var rect = NSRectFromString(saved)
            if rect.width > 40, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) {
                let top = rect.maxY
                rect.size.height = rect.width * ResizeHandleView.aspect
                rect.origin.y = top - rect.size.height
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
        syncDockIcon()
    }

    private func applyDockVisibility() {
        lastDockKey = nil
        if DockSettings.enabled {
            NSApp.setActivationPolicy(.regular)
            syncDockIcon()
        } else {
            DockIcon.restore()
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func syncDockIcon() {
        guard DockSettings.enabled else { return }
        let remaining = store.remainingFraction
        let used = store.usedFraction
        let siren = store.isSiren
        let flash = siren && Int(Date().timeIntervalSince1970 * 2) % 2 == 0
        let badge = store.budget.map { TokenFormat.dockBadge($0.remaining) }
        let key = "\(store.look.rawValue)-\(Int((remaining * 1000).rounded()))-\(Int((used * 1000).rounded()))-\(flash)-\(badge ?? "")"
        guard key != lastDockKey else { return }
        lastDockKey = key
        DockIcon.apply(remaining: remaining, used: used, siren: flash, badge: badge, look: store.look)
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
