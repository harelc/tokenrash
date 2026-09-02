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
    private var probing = false
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
            Task { @MainActor in
                await self?.refresh(interactive: false)
            }
        }
    }

    func signIn() {
        store.phase = .signingIn
        probing = false
        showLoginWindow()
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await pageFinished() }
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
        keeperWindow = NSWindow(
            contentRect: NSRect(x: -9000, y: -9000, width: 1024, height: 768),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        keeperWindow.isReleasedWhenClosed = false
        keeperWindow.alphaValue = 1
        keeperWindow.ignoresMouseEvents = true
        keeperWindow.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        keeperWindow.contentView = webView
        keeperWindow.orderFrontRegardless()
    }

    private func refresh(interactive: Bool) async {
        if interactive {
            signIn()
            return
        }
        probing = false
        webView.load(URLRequest(url: TokenrashConfig.meURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }

    private func pageFinished() async {
        let host = webView.url?.host ?? ""
        if host.contains("accounts.google.com") {
            store.phase = .signingIn
            showLoginWindow()
            return
        }
        guard host == TokenrashConfig.origin.host else { return }

        try? await Task.sleep(nanoseconds: 1_200_000_000)
        await harvestFromPageText()
        if store.budget != nil { return }
        await probeAPIPaths()
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
        ingest(text, source: "dom")
    }

    private func probeAPIPaths() async {
        guard !probing else { return }
        probing = true
        let script = """
        const paths = [
          '/api/me', '/api/users/me', '/api/user', '/api/usage', '/api/usage?period=today',
          '/api/quota', '/api/budget', '/api/stats', '/api/v1/me', '/v1/me', '/me.json',
          '/openapi.json', '/api/daily', '/api/tokens', '/api/account', '/api/profile'
        ];
        const out = [];
        for (const p of paths) {
          try {
            const r = await fetch(p, { credentials: 'include', headers: { 'Accept': 'application/json' } });
            const t = await r.text();
            out.push({ path: p, status: r.status, body: t.slice(0, 120000) });
          } catch (e) {
            out.push({ path: p, status: 0, body: String(e) });
          }
        }
        return out;
        """
        let result: Any? = await withCheckedContinuation { continuation in
            webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { outcome in
                switch outcome {
                case .success(let value): continuation.resume(returning: value)
                case .failure: continuation.resume(returning: nil)
                }
            }
        }
        guard let rows = result as? [Any] else { return }
        for row in rows {
            guard let dict = row as? [String: Any] else { continue }
            let path = dict["path"] as? String ?? ""
            let status = (dict["status"] as? Int) ?? (dict["status"] as? Double).map(Int.init) ?? 0
            let body = dict["body"] as? String ?? ""
            appendCapture(source: "probe \(path) \(status)", body: body)
            if status == 200, !looksLikeHTML(body) {
                ingest(body, source: path)
                if store.budget != nil { return }
            }
        }
    }

    private func ingest(_ raw: String, source: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appendCapture(source: source, body: trimmed)
        if looksLikeHTML(trimmed) { return }
        // Daily history has spend/limit per day but is not "today".
        if trimmed.contains("\"series\"") && !trimmed.contains("\"today\"") { return }
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

    private func parkWebView() {
        webView.removeFromSuperview()
        keeperWindow.contentView = webView
        keeperWindow.orderFrontRegardless()
    }

    private func closeLogin() {
        loginWindow?.orderOut(nil)
        parkWebView()
        probing = false
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
          window.webkit.messageHandlers.tokenrash.postMessage(t);
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
