import AppKit
import Foundation
import WebKit

@MainActor
final class IAPSession: NSObject, WKNavigationDelegate, WKUIDelegate {
    let store: BudgetStore
    private var webView: WKWebView!
    private var loginWindow: NSWindow?
    private var loginDelegate: LoginWindowCloser?
    private var pollTimer: Timer?
    private var cookieSession: URLSession
    private var waitingForJSON = false

    init(store: BudgetStore) {
        self.store = store
        let cookies = HTTPCookieStorage.shared
        cookies.cookieAcceptPolicy = .always
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = cookies
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        self.cookieSession = URLSession(configuration: config)
        super.init()
        setupWebView()
    }

    func start() {
        Task { await refresh(interactive: false) }
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: TokenrashConfig.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh(interactive: false)
            }
        }
    }

    func signIn() {
        store.phase = .signingIn
        showLoginWindow()
        waitingForJSON = true
        webView.load(URLRequest(url: TokenrashConfig.meURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }

    func signOut() {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) { }
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        store.markSignedOut()
        closeLogin()
    }

    func inspectPayload() {
        let json = store.rawJSON ?? "No payload yet. Sign in first."
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Last /me payload"
        let view = NSTextView(frame: panel.contentView!.bounds)
        view.string = json
        view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        view.isEditable = false
        view.autoresizingMask = [.width, .height]
        let scroll = NSScrollView(frame: panel.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.documentView = view
        scroll.hasVerticalScroller = true
        panel.contentView = scroll
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await harvestIfPossible() }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if store.budget == nil {
            store.phase = .error(error.localizedDescription)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if store.budget == nil {
            store.phase = .error(error.localizedDescription)
        }
    }

    // MARK: - Private

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 640), configuration: config)
        webView.customUserAgent = TokenrashConfig.safariUserAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    private func refresh(interactive: Bool) async {
        if interactive {
            signIn()
            return
        }
        if await fetchViaURLSession() { return }
        if await fetchViaJavaScript() { return }
        if store.budget == nil, store.phase != .signingIn {
            store.phase = .signedOut
        }
    }

    @discardableResult
    private func fetchViaURLSession() async -> Bool {
        await syncCookies()
        var request = URLRequest(url: TokenrashConfig.meURL)
        request.setValue(TokenrashConfig.safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json,text/plain,*/*", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await cookieSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            if http.statusCode == 401 || http.statusCode == 302 || http.statusCode == 303 {
                return false
            }
            guard http.statusCode == 200 else { return false }
            if looksLikeHTML(data) { return false }
            let (budget, pretty) = try TokenBudgetParser.parse(data: data)
            store.apply(budget: budget, rawJSON: pretty)
            closeLogin()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    private func fetchViaJavaScript() async -> Bool {
        guard webView.url?.host == TokenrashConfig.origin.host else { return false }
        let script = """
        const r = await fetch('/me', { credentials: 'include', headers: { 'Accept': 'application/json' } });
        const t = await r.text();
        return { status: r.status, body: t };
        """
        do {
            let result: Any? = try await withCheckedThrowingContinuation { continuation in
                webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { outcome in
                    switch outcome {
                    case .success(let value):
                        continuation.resume(returning: value)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            guard let obj = result as? [String: Any],
                  let status = (obj["status"] as? Int) ?? (obj["status"] as? Double).map(Int.init),
                  let body = obj["body"] as? String,
                  status == 200 else { return false }
            let (budget, pretty) = try TokenBudgetParser.parse(text: body)
            store.apply(budget: budget, rawJSON: pretty)
            closeLogin()
            return true
        } catch {
            return false
        }
    }

    private func harvestIfPossible() async {
        await syncCookies()
        if await fetchViaURLSession() { return }

        let text = (try? await webView.evaluateJavaScript("document.body ? document.body.innerText : ''")) as? String
        if let text {
            if let parsed = try? TokenBudgetParser.parse(text: text) {
                store.apply(budget: parsed.0, rawJSON: parsed.1)
                closeLogin()
                return
            }
        }
        if let url = webView.url, url.host?.contains("accounts.google.com") == true {
            store.phase = .signingIn
            showLoginWindow()
        }
    }

    private func syncCookies() async {
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    private func looksLikeHTML(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(80), encoding: .utf8)?.lowercased() else { return false }
        return prefix.contains("<html") || prefix.contains("<!doctype") || prefix.contains("google accounts")
    }

    private func showLoginWindow() {
        if loginWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Sign in to Tokenrash"
            window.contentView = webView
            window.isReleasedWhenClosed = false
            let closer = LoginWindowCloser(onClose: { [weak self] in
                if self?.store.budget == nil {
                    self?.store.phase = .signedOut
                }
            })
            loginDelegate = closer
            window.delegate = closer
            loginWindow = window
        }
        webView.removeFromSuperview()
        loginWindow?.contentView = webView
        loginWindow?.center()
        loginWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeLogin() {
        loginWindow?.orderOut(nil)
        waitingForJSON = false
    }
}

private final class LoginWindowCloser: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
