import SwiftUI
import WebKit

// MARK: - Klient HTTP / WKWebView

@MainActor
final class ModDBClient: NSObject, WKNavigationDelegate {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpAdditionalHeaders = [
            "User-Agent": Self.userAgent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
        ]
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 1800
        return URLSession(configuration: config)
    }()

    private var webView: WKWebView?
    private var pending: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?

    var challengeVisible = false
    var onChallengeChange: ((Bool) -> Void)?

    func html(from url: URL) async throws -> String {
        if let viaSession = try? await sessionHTML(url), !ModDBHTML.isCloudflare(viaSession) {
            return viaSession
        }
        return try await webViewHTML(url)
    }

    func download(_ url: URL, to dest: URL) async throws {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.moddb.com/", forHTTPHeaderField: "Referer")
        let (temp, response) = try await session.download(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 403 || ModDBHTML.isCloudflare(String(data: (try? Data(contentsOf: temp)) ?? Data(), encoding: .utf8) ?? "") {
            throw URLError(.userAuthenticationRequired)
        }
        guard (200...399).contains(code) else { throw URLError(.badServerResponse) }
        if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
        try FileManager.default.moveItem(at: temp, to: dest)
    }

    private func sessionHTML(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.moddb.com/", forHTTPHeaderField: "Referer")
        let (data, _) = try await session.data(for: request)
        return String(decoding: data, as: UTF8.self)
    }

    private func webViewHTML(_ url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            if pending != nil { pending?.resume(throwing: CancellationError()) }
            pending = cont
            ensureWebView()
            // ramkę pokazujemy dopiero, gdy strona faktycznie okaże się challenge'em
            // (didFinish) — inaczej prosiłaby o kliknięcie przy każdym zwykłym pobraniu
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 90_000_000_000)
                await MainActor.run { self?.finish(.failure(URLError(.timedOut))) }
            }
            webView?.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard let html = try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String
            else { return }
            if ModDBHTML.isCloudflare(html) {
                showChallenge()
                return
            }
            await syncCookies()
            hideChallenge()
            finish(.success(html))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func attachedWebView() -> WKWebView {
        ensureWebView()
        return webView!
    }

    private func finish(_ result: Result<String, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let pending else { return }
        self.pending = nil
        pending.resume(with: result)
    }

    private func ensureWebView() {
        if webView != nil { return }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = "Version/18.5 Safari/605.1.15"
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = Self.userAgent
        wv.navigationDelegate = self
        webView = wv
    }

    private func showChallenge() {
        challengeVisible = true
        onChallengeChange?(true)
    }

    private func hideChallenge() {
        challengeVisible = false
        onChallengeChange?(false)
    }

    private func syncCookies() async {
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else { return }
        let cookies = await store.allCookies()
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }
}
