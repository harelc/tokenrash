import AppKit
import Foundation
import WebKit

@MainActor
final class IAPSession: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let store: BudgetStore
    private var webView: WKWebView!
    private var loginWindow: NSWindow?
    private var keeperWindow: NSWindow!
    private var loginDelegate: LoginWindowCloser?
    private var pollTimer: Timer?
    private let dumpURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Logs/Tokenrash-last-me.json")
    private let captureURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Logs/Tokenrash-captures.jsonl")

    init(store: BudgetStore) {
        self.store = store
        super.init()
        setupWebView()
    }

    func start() {
        Task { await refresh(interactive: false) }
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: TokenrashConfig.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [self] in
                await self?.refresh(interactive: false)
            }
        }
    }

    func signIn() {
        store.phase = .signingIn
        webView.load(URLRequest(url: TokenrashConfig.meURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }

    /// Reload `/me` in the hidden keeper WebView. Only surfaces a window if IAP
    /// bounces to Google and the user actually needs to sign in again.
    func refreshNow() {
        Task { await refresh(interactive: false) }
    }

    func signOut() {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) { }
        store.markSignedOut()
        closeLogin()
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

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.add(self, name: "tokenrash")
        config.userContentController.addUserScript(WKUserScript(source: Self.snifferScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
        webView.customUserAgent = TokenrashConfig.safariUserAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        let keeper = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        keeper.isReleasedWhenClosed = false
        keeper.hasShadow = false
        keeper.hidesOnDeactivate = false
        keeper.isExcludedFromWindowsMenu = true
        keeper.collectionBehavior = [.ignoresCycle, .transient, .stationary, .fullScreenAuxiliary]
        keeper.contentView = webView
        keeperWindow = keeper
        concealKeeper()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(concealKeeper),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(concealKeeper),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(concealKeeper),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(concealKeeper),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    private func refresh(interactive: Bool) async {
        if interactive {
            signIn()
            return
        }
        if webView.url?.host == TokenrashConfig.origin.host {
            await fetchMeJSON()
            if store.budget != nil { return }
        }
        webView.load(URLRequest(url: TokenrashConfig.meURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }

    private func pageFinished() async {
        let host = webView.url?.host ?? ""
        if isAuthHost(host) {
            store.phase = .signingIn
            showLoginWindow()
            return
        }
        guard host == TokenrashConfig.origin.host else { return }
        await fetchMeJSON()
        if store.budget != nil { return }
        await harvestFromPageText()
    }

    /// Personal JSON is `GET /api/me`. Navigating to `/me` loads the SPA HTML.
    private func fetchMeJSON() async {
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

    private func ingest(_ raw: String, source: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appendCapture(source: source, body: trimmed)
        if looksLikeHTML(trimmed) { return }
        if looksLikeOrgGraph(trimmed) { return }
        if trimmed.contains("\"series\"") && !trimmed.contains("\"spend_usd\"") { return }
        do {
            let (budget, pretty) = try TokenBudgetParser.parse(text: trimmed)
            store.apply(budget: budget, rawJSON: pretty)
            try? pretty.write(to: dumpURL, atomically: true, encoding: .utf8)
            closeLogin()
            NSLog("[Tokenrash] budget from \(source): used=\(budget.used) limit=\(budget.limit)")
        } catch {
            try? trimmed.write(to: dumpURL, atomically: true, encoding: .utf8)
            NSLog("[Tokenrash] parse miss from \(source): \(trimmed.prefix(160))")
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
            window.isExcludedFromWindowsMenu = true
            let closer = LoginWindowCloser(onClose: { [weak self] in
                self?.parkWebView()
                if self?.store.budget == nil, self?.store.phase == .signingIn {
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

    private func syncBrowserChrome() {
        let host = webView.url?.host ?? ""
        if isAuthHost(host) {
            store.phase = .signingIn
            showLoginWindow()
        }
        // Do not park the WebView just because we left Google — that reparent
        // mid-redirect drops the IAP cookie. ingest() closes the window.
    }

    private func isAuthHost(_ host: String) -> Bool {
        let h = host.lowercased()
        if h.contains("accounts.google.") { return true }
        if h.contains("iap.googleapis.com") { return true }
        return false
    }

    @objc private func concealKeeper() {
        guard webView.window === keeperWindow else { return }
        parkWebView()
    }

    private func parkWebView() {
        webView.removeFromSuperview()
        keeperWindow.alphaValue = 0
        keeperWindow.ignoresMouseEvents = true
        keeperWindow.hasShadow = false
        keeperWindow.contentView = webView
        keeperWindow.orderFrontRegardless()
    }

    private func closeLogin() {
        loginWindow?.orderOut(nil)
        parkWebView()
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
