import AppKit
import ServiceManagement

enum AppInstall {
    static let applicationsURL = URL(fileURLWithPath: "/Applications/Tokenrash.app")
    private static let pendingLoginKey = "install.launchAtLogin.pending"

    static var isInApplications: Bool {
        Bundle.main.bundleURL.resolvingSymlinksInPath().path
            == applicationsURL.resolvingSymlinksInPath().path
    }

    static var launchesAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func applyPendingLaunchAtLogin() {
        guard UserDefaults.standard.bool(forKey: pendingLoginKey) else { return }
        UserDefaults.standard.set(false, forKey: pendingLoginKey)
        try? setLaunchesAtLogin(true)
    }

    static func setLaunchesAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }

    static func installAndRelaunch(enableLogin: Bool) throws {
        if enableLogin {
            UserDefaults.standard.set(true, forKey: pendingLoginKey)
        }
        try copyToApplications()
        NSWorkspace.shared.open(applicationsURL)
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }

    private static func copyToApplications() throws {
        let src = Bundle.main.bundleURL
        let dest = applicationsURL
        if src.resolvingSymlinksInPath() == dest.resolvingSymlinksInPath() { return }
        terminateOtherCopies(at: dest)
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: src, to: dest)
    }

    private static func terminateOtherCopies(at url: URL) {
        let dest = url.resolvingSymlinksInPath()
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.harel.tokenrash") {
            guard app != .current else { continue }
            if let bundle = app.bundleURL?.resolvingSymlinksInPath(), bundle == dest {
                app.terminate()
            }
        }
        Thread.sleep(forTimeInterval: 0.35)
    }
}
