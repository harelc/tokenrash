import AppKit
import Foundation
import WebKit

@MainActor
final class IAPSession: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let store: BudgetStore
    private var webView: WKWebView?
    private var loginWindow: NSWindow?
    private var loginDelegate: LoginWindowCloser?
    private var pollTask: Task<Void, Never>?
    private let dumpURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Logs/Tokenrash-last-me.json")
    private let captureURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Logs/Tokenrash-captures.jsonl")
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 30
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()

    init(store: BudgetStore) {
        self.store = store
        super.init()
    }

    func start() {
        Task { await silentRefresh() }
    }

    func signIn() {
        store.phase = .signingIn
        let view = ensureWebView()
        view.load(URLRequest(url: TokenrashConfig.meURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }

    /// URLSession `/api/me` with stored IAP cookies. Opens Google only if the session is dead.
    func refreshNow() {
        Task {
            switch await fetchAPIMe() {
            case .ingested:
                schedulePoll()
            case .unauthorized:
                signIn()
            case .failed:
                NSLog("[Tokenrash] refresh failed; keeping last budget")
            }
        }
    }

    func signOut() {
        pollTask?.cancel()
        pollTask = nil
        teardownBrowser()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) { }
        store.markSignedOut()
    }

    func inspectPayload() {
        let json = store.rawJSON ?? (try? String(contentsOf: dumpURL, encoding: .utf8)) ?? "No payload yet. Sign in first."
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

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        syncBrowserChrome()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncBrowserChrome()
        Task { await pageFinished() }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let host = navigationAction.request.url?.host, isAuthHost(host) {
            showLoginWindow()
        }
        decisionHandler(.allow)
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
        if store.budget == nil, store.phase == .signingIn {
            store.phase = .error(error.localizedDescription)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if store.budget == nil, store.phase == .signingIn {
            store.phase = .error(error.localizedDescription)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "tokenrash" else { return }
        if let dict = message.body as? [String: Any] {
            let url = dict["url"] as? String ?? ""
            let body = dict["body"] as? String ?? ""
            guard isMeJSONURL(url) else { return }
            ingest(body, source: "sniff \(url)")
            return
        }
        if let body = message.body as? String {
            ingest(body, source: "message")
        }
    }

    private func silentRefresh() async {
        switch await fetchAPIMe() {
        case .ingested:
            schedulePoll()
        case .unauthorized, .failed:
            break
        }
    }

    private func schedulePoll() {
        pollTask?.cancel()
        guard store.budget != nil else { return }
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let interval = TokenrashConfig.pollInterval(remaining: self.store.budget?.remainingFraction)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                switch await self.fetchAPIMe() {
                case .ingested:
                    continue
                case .unauthorized, .failed:
                    continue
                }
            }
        }
    }

    private enum FetchOutcome {
        case ingested
        case unauthorized
        case failed
    }

    /// GET `/api/me` with cookies from the WebKit data store. No live WebView.
    private func fetchAPIMe() async -> FetchOutcome {
        let cookies = await allCookies()
        var request = URLRequest(url: TokenrashConfig.apiMeURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(TokenrashConfig.safariUserAgent, forHTTPHeaderField: "User-Agent")
        let sent = cookies.filter { Self.cookie($0, appliesTo: TokenrashConfig.apiMeURL) }
        let header = HTTPCookie.requestHeaderFields(with: sent)
        if let value = header["Cookie"] {
            request.setValue(value, forHTTPHeaderField: "Cookie")
        }
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed }
            await storeResponseCookies(http, for: TokenrashConfig.apiMeURL)
            if http.statusCode == 401 || http.statusCode == 403 { return .unauthorized }
            if (300..<400).contains(http.statusCode) { return .unauthorized }
            guard http.statusCode == 200 else { return .failed }
            let body = String(data: data, encoding: .utf8) ?? ""
            appendCapture(source: "URLSession GET /api/me \(http.statusCode)", body: body)
            if looksLikeHTML(body) { return .unauthorized }
            if ingest(body, source: "URLSession GET /api/me") { return .ingested }
            return .failed
        } catch {
            NSLog("[Tokenrash] URLSession /api/me: \(error.localizedDescription)")
            return .failed
        }
    }

    private func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func storeResponseCookies(_ response: HTTPURLResponse, for url: URL) async {
        var fields: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let value = value as? String else { continue }
            fields[String(describing: key)] = value
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        let store = WKWebsiteDataStore.default().httpCookieStore
        for cookie in cookies {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.setCookie(cookie) { continuation.resume() }
            }
        }
    }

    private static func cookie(_ cookie: HTTPCookie, appliesTo url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let domain = cookie.domain.lowercased()
        if domain.hasPrefix(".") {
            let bare = String(domain.dropFirst())
            if host != bare && !host.hasSuffix("." + bare) { return false }
        } else if host != domain {
            return false
        }
        let path = url.path.isEmpty ? "/" : url.path
        let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
        let pathOK = path == cookiePath
            || (cookiePath.hasSuffix("/") && path.hasPrefix(cookiePath))
            || path.hasPrefix(cookiePath + "/")
        if !pathOK { return false }
        if cookie.isSecure, url.scheme?.lowercased() != "https" { return false }
        if let expiry = cookie.expiresDate, expiry < Date() { return false }
        return true
    }

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.add(self, name: "tokenrash")
        config.userContentController.addUserScript(
            WKUserScript(source: Self.snifferScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 680), configuration: config)
        view.customUserAgent = TokenrashConfig.safariUserAgent
        view.navigationDelegate = self
        view.uiDelegate = self
        webView = view
        return view
    }

    private func pageFinished() async {
        guard let webView else { return }
        let host = webView.url?.host ?? ""
        if isAuthHost(host) {
            store.phase = .signingIn
            showLoginWindow()
            return
        }
        guard host == TokenrashConfig.origin.host else { return }
        await fetchMeJSONFromPage()
        if store.budget != nil { return }
        await harvestFromPageText()
    }

    /// Personal JSON is `GET /api/me`. Navigating to `/me` loads the SPA HTML.
    private func fetchMeJSONFromPage() async {
        guard let webView else { return }
        let script = """
        const pull = async (path) => {
          const r = await fetch(path, {
            credentials: 'include',
            cache: 'no-store',
            headers: { 'Accept': 'application/json' }
          });
          return { path, status: r.status, body: await r.text() };
        };
        const looksJSON = (t) => {
          const s = (t || '').trim();
          return s.startsWith('{') || s.startsWith('[');
        };
        let r = await pull('/api/me');
        if (!(r.status === 200 && looksJSON(r.body))) {
          r = await pull('/me');
        }
        return r;
        """
        let result: Any? = await withCheckedContinuation { continuation in
            webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { outcome in
                switch outcome {
                case .success(let value): continuation.resume(returning: value)
                case .failure: continuation.resume(returning: nil)
                }
            }
        }
        guard let dict = result as? [String: Any] else { return }
        let status = (dict["status"] as? Int) ?? (dict["status"] as? Double).map(Int.init) ?? 0
        let body = dict["body"] as? String ?? ""
        let path = dict["path"] as? String ?? "/api/me"
        appendCapture(source: "GET \(path) \(status)", body: body)
        guard status == 200 else { return }
        ingest(body, source: "GET \(path)")
    }

    private func harvestFromPageText() async {
        guard let webView else { return }
        let script = """
        (function() {
          const pre = document.querySelector('pre');
          if (pre && pre.innerText.trim().startsWith('{')) return pre.innerText;
          return document.body ? document.body.innerText : '';
        })()
        """
        let text: String = await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script) { result, _ in
                continuation.resume(returning: (result as? String) ?? "")
            }
        }
        if let path = webView.url?.path, !isMeJSONURL(path) { return }
        ingest(text, source: "dom")
    }

    @discardableResult
    private func ingest(_ raw: String, source: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        appendCapture(source: source, body: trimmed)
        if looksLikeHTML(trimmed) { return false }
        if looksLikeOrgGraph(trimmed) { return false }
        if trimmed.contains("\"series\"") && !trimmed.contains("\"spend_usd\"") { return false }
        do {
            let (budget, pretty) = try TokenBudgetParser.parse(text: trimmed)
            store.apply(budget: budget, rawJSON: pretty)
            try? pretty.write(to: dumpURL, atomically: true, encoding: .utf8)
            Task { @MainActor [weak self] in
                self?.teardownBrowser()
                self?.schedulePoll()
            }
            NSLog("[Tokenrash] budget from \(source): used=\(budget.used) limit=\(budget.limit)")
            return true
        } catch {
            try? trimmed.write(to: dumpURL, atomically: true, encoding: .utf8)
            NSLog("[Tokenrash] parse miss from \(source): \(trimmed.prefix(160))")
            return false
        }
    }

    private func appendCapture(source: String, body: String) {
        let line = "{\"source\":\(Self.jsonString(source)),\"n\":\(body.count),\"prefix\":\(Self.jsonString(String(body.prefix(300))))}\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: captureURL.path) {
                if let handle = try? FileHandle(forWritingTo: captureURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: captureURL)
            }
        }
    }

    private func looksLikeHTML(_ text: String) -> Bool {
        let prefix = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return prefix.hasPrefix("<!doctype") || prefix.hasPrefix("<html") || prefix.contains("<div id=\"root\"")
    }

    /// Personal JSON is `GET /api/me` (and legacy `/me`). Admin SPA also fetches `/tree`; never apply that.
    private func isMeJSONURL(_ url: String) -> Bool {
        let path = url.split(separator: "?").first.map(String.init) ?? url
        let lower = path.lowercased()
        if lower.contains("/tree") { return false }
        return lower.hasSuffix("/api/me") || lower.hasSuffix("/me") || lower.hasSuffix("/me.json")
            || lower == "/me" || lower == "me" || lower == "/api/me"
    }

    /// `/tree` org dump: `{ nodes, personas }` — even if people have nested spend fields.
    private func looksLikeOrgGraph(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return text.contains("\"nodes\"")
        }
        if root["nodes"] != nil { return true }
        return root["personas"] != nil && root["today"] == nil
    }

    private func showLoginWindow() {
        let view = ensureWebView()
        if loginWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Sign in to Tokenrash"
            window.isReleasedWhenClosed = false
            window.isExcludedFromWindowsMenu = true
            let closer = LoginWindowCloser(onClose: { [weak self] in
                self?.teardownBrowser()
                if self?.store.budget == nil, self?.store.phase == .signingIn {
                    self?.store.phase = .signedOut
                }
            })
            loginDelegate = closer
            window.delegate = closer
            loginWindow = window
        }
        view.removeFromSuperview()
        loginWindow?.contentView = view
        loginWindow?.center()
        loginWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func syncBrowserChrome() {
        let host = webView?.url?.host ?? ""
        if isAuthHost(host) {
            store.phase = .signingIn
            showLoginWindow()
        }
    }

    private func isAuthHost(_ host: String) -> Bool {
        let h = host.lowercased()
        if h.contains("accounts.google.") { return true }
        if h.contains("iap.googleapis.com") { return true }
        return false
    }

    private func teardownBrowser() {
        loginWindow?.delegate = nil
        loginWindow?.orderOut(nil)
        loginWindow?.contentView = nil
        loginWindow = nil
        loginDelegate = nil
        guard let webView else { return }
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "tokenrash")
        webView.removeFromSuperview()
        self.webView = nil
    }

    private static func jsonString(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
        return String(data: data ?? Data("\"\"".utf8), encoding: .utf8) ?? "\"\""
    }

    private static let snifferScript = """
    (function() {
      if (window.__tokenrashSniff) return;
      window.__tokenrashSniff = true;
      const post = (url, text) => {
        try {
          const t = (text || '').trim();
          if (!t) return;
          if (!(t.startsWith('{') || t.startsWith('['))) return;
          const href = String(url || '');
          const path = href.split('?')[0].toLowerCase();
          if (path.includes('/tree')) return;
          if (!(path.endsWith('/api/me') || path.endsWith('/me') || path.endsWith('/me.json') || path === '/me' || path === 'me')) return;
          window.webkit.messageHandlers.tokenrash.postMessage({ url: href, body: t });
        } catch (e) {}
      };
      const origFetch = window.fetch;
      window.fetch = async function(input, init) {
        const res = await origFetch.apply(this, arguments);
        try {
          const clone = res.clone();
          const text = await clone.text();
          post(String(input && input.url ? input.url : input), text);
        } catch (e) {}
        return res;
      };
      const origOpen = XMLHttpRequest.prototype.open;
      const origSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(method, url) {
        this.__tokenrashURL = url;
        return origOpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function() {
        this.addEventListener('load', function() {
          post(String(this.__tokenrashURL || ''), this.responseText || '');
        });
        return origSend.apply(this, arguments);
      };
    })();
    """
}

private final class LoginWindowCloser: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
