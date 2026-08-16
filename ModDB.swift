import SwiftUI
import WebKit

// MARK: - ModDB: dane
//
// ModDB nie ma publicznego API. Lista i pliki są w HTML, a właściwy bajtowy
// download idzie przez /downloads/start/<id> → /downloads/mirror/….
// Cloudflare często blokuje goły URLSession, więc przy challenge'u dokładamy
// WKWebView (ten sam silnik co Safari) i przepisujemy ciastka do sesji.

struct ModDBMod: Identifiable, Hashable, Codable {
    var slug: String
    var title = ""
    var summary = ""
    var thumbnailURL: URL?
    var screenshotURL: URL?
    var updated: Date?
    var released: Date?
    var status = ""
    var genre = ""
    var author = ""
    var rating = 0.0
    var ratingCount = 0
    var descriptionText = ""
    var files: [ModDBFile] = []
    var detailLoaded = false
    /// Kiedy pobraliśmy tego moda — wstrzykiwane z rejestru przy filtrowaniu,
    /// żeby tabela mogła po tym sortować (Table sortuje po właściwościach modelu).
    var installedAt: Date?
    var pageURL: URL { URL(string: "https://www.moddb.com/mods/\(slug)")! }
    var id: String { slug }

    var updatedText: String {
        guard let updated else { return "—" }
        return Self.day.string(from: updated)
    }

    var updatedSort: Date { updated ?? .distantPast }

    var installedSort: Date { installedAt ?? .distantPast }

    var installedText: String {
        guard let installedAt else { return "—" }
        return Self.day.string(from: installedAt)
    }

    var statusText: String {
        if !status.isEmpty { return status }
        if released != nil { return "Wydany" }
        return "—"
    }

    var isReleased: Bool {
        let s = status.lowercased()
        return s.contains("released") || s.hasPrefix("wydany")
    }

    /// Silniki / formaty, z którymi typowy QuakeSpasm sobie nie poradzi.
    var engineWarning: String? {
        let blob = "\(title) \(summary) \(descriptionText)".lowercased()
        var need: [String] = []
        if blob.contains("darkplaces") { need.append("DarkPlaces") }
        if blob.contains("fteqw") || blob.contains("fte quake") || blob.contains("ftequake")
            || blob.contains(" for fte") { need.append("FTE") }
        if blob.contains("zircon") { need.append("Zircon") }
        var notes: [String] = []
        if title.lowercased().contains("engine") || slug.contains("engine") {
            notes.append("To wygląda na silnik, nie na katalog -game — launcher rozpakuje archiwum, ale nie uruchomi tego jako moda.")
        }
        if !need.isEmpty {
            notes.append("Ten mod jest pod \(need.joined(separator: "/")) — QuakeSpasm/vkQuake mogą go nie załadować.")
        }
        return notes.isEmpty ? nil : notes.joined(separator: " ")
    }

    private static let day: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
}

struct ModDBFile: Identifiable, Hashable, Codable {
    var slug: String
    var title = ""
    var category = ""
    var date = ""
    var summary = ""
    var filename = ""
    var sizeBytes = 0
    var md5 = ""
    var fileID: Int?
    var imageURL: URL?

    var id: String { slug }

    var sizeText: String {
        guard sizeBytes > 0 else { return "" }
        if sizeBytes >= 1_048_576 { return String(format: "%.1f MB", Double(sizeBytes) / 1_048_576) }
        if sizeBytes >= 1024 { return String(format: "%.0f KB", Double(sizeBytes) / 1024) }
        return "\(sizeBytes) B"
    }

    var ext: String {
        URL(fileURLWithPath: filename.isEmpty ? slug : filename).pathExtension.lowercased()
    }

    var isArchive: Bool {
        ["zip", "7z", "rar", "tar", "gz", "tgz", "pk3", "pak"].contains(ext)
    }

    var isInstaller: Bool {
        ["exe", "msi", "dmg", "pkg", "app"].contains(ext)
    }

}

// MARK: - Parser HTML

enum ModDBHTML {
    /// Czy to strona blokująca, a nie zwykła treść.
    ///
    /// Uwaga na fałszywe trafienia: Cloudflare wstrzykuje `/cdn-cgi/challenge-platform/…`
    /// w KAŻDĄ chronioną stronę, także po pomyślnej weryfikacji. Sprawdzanie tego ciągu
    /// sprawiało, że każde pobranie uchodziło za challenge — launcher czekał 90 s na
    /// kliknięcie, którego nie było o co prosić, i kończył timeoutem, a lista modów
    /// zostawała na wiecznie nieodświeżanym cache. Zostają markery samego interstycjału.
    static func isCloudflare(_ html: String) -> Bool {
        let lower = html.lowercased()
        return lower.contains("just a moment")
            || lower.contains("window._cf_chl")
            || lower.contains("cf_chl_opt")
            || lower.contains("checking your browser")
    }

    static func listing(_ html: String) -> [ModDBMod] {
        let scope = slice(html, after: "id=\"modsbrowse\">", before: "class=\"pagination") ?? html
        guard let rowRe = try? NSRegularExpression(
            pattern: "<div class=\"row rowcontent[^\"]*\">(.*?)</div>\\s*</div>",
            options: .dotMatchesLineSeparators)
        else { return [] }

        var result: [ModDBMod] = []
        var seen = Set<String>()
        for match in rowRe.matches(in: scope, range: ns(scope)) {
            let row = slice(scope, match, 1)
            guard let slug = first(row, "href=\"/mods/([^\"/?#]+)\"") else { continue }
            guard seen.insert(slug).inserted else { continue }
            var mod = ModDBMod(slug: slug)
            mod.title = QuaddictedIndex.stripTags(first(row, "<h4><a[^>]*>(.*?)</a></h4>") ?? slug)
            mod.summary = QuaddictedIndex.stripTags(first(row, "<p>(.*?)</p>") ?? "")
            if let src = first(row, "<img src=\"([^\"]+)\"") { mod.thumbnailURL = URL(string: src) }
            let times = all(row, "<time datetime=\"([^\"]+)\"")
            if let first = times.first { mod.updated = parseTime(first) }
            if times.count > 1 { mod.released = parseTime(times[1]) }
            // Subheading to jeden ciąg w rodzaju „Released 2003 First Person Shooter".
            // Podział po dwóch spacjach nie działał, bo stripTags zostawia pojedyncze —
            // status wchłaniał cały tekst, a gatunek zostawał pusty. Tniemy po wzorcu statusu.
            let sub = QuaddictedIndex.stripTags(first(row, "class=\"subheading\">(.*?)</span>") ?? "")
            // „Coming Soon" przed „Coming" — inaczej alternatywa urwałaby się na pierwszym słowie.
            // Po słowie statusu bierzemy też datę („Released Aug 14, 2026" albo „Released 1997"),
            // inaczej wpadała do gatunku i kolumna pokazywała „Aug 14, 2026 First Person Shooter".
            if let head = first(sub, #"^((?:Released|Releasing|Coming Soon|Coming|Early Access|TBD)(?:\s+\w{3}\s+\d{1,2},\s*\d{4}|\s+\d{4})?)"#) {
                mod.status = head.trimmingCharacters(in: .whitespaces)
                mod.genre = String(sub.dropFirst(head.count)).trimmingCharacters(in: .whitespaces)
            } else {
                mod.genre = sub
            }
            result.append(mod)
        }
        return result
    }

    static func listingTotal(_ html: String) -> Int? {
        first(html, #"of (\d+)"#).flatMap(Int.init)
    }

    static func listingPages(_ html: String) -> Int {
        let nums = all(html, "/mods/page/(\\d+)").compactMap(Int.init)
        if let max = nums.max(), max > 0 { return max }
        if let total = listingTotal(html) { return max(1, (total + 29) / 30) }
        return 1
    }

    static func files(in html: String, slug: String) -> [ModDBFile] {
        let escaped = NSRegularExpression.escapedPattern(for: slug)
        let scope = slice(html, after: "class=\"heading\">Files", before: "id=\"comments\"") ?? html
        guard let rowRe = try? NSRegularExpression(
            pattern: "<div class=\"row rowcontent[^\"]*\">(.*?)</div>\\s*</div>",
            options: .dotMatchesLineSeparators)
        else { return [] }

        var result: [ModDBFile] = []
        var seen = Set<String>()
        let hrefRe = "href=\"/mods/\(escaped)/downloads/([^\"/?#]+)\""
        for match in rowRe.matches(in: scope, range: ns(scope)) {
            let row = slice(scope, match, 1)
            guard let fileSlug = first(row, hrefRe), fileSlug != "add" else { continue }
            guard seen.insert(fileSlug).inserted else { continue }
            var file = ModDBFile(slug: fileSlug)
            file.title = QuaddictedIndex.stripTags(first(row, "<h4><a[^>]*>(.*?)</a></h4>") ?? fileSlug)
            file.date = QuaddictedIndex.stripTags(first(row, "<time[^>]*>(.*?)</time>") ?? "")
            file.category = QuaddictedIndex.stripTags(first(row, "class=\"subheading\">(.*?)</span>") ?? "")
            file.summary = QuaddictedIndex.stripTags(first(row, "<p>(.*?)</p>") ?? "")
            if let src = first(row, "<img src=\"([^\"]+)\"") {
                file.imageURL = URL(string: src)
                file.fileID = idFromMediaPath(src)
            }
            result.append(file)
        }
        return result
    }

    static func applyDetail(to mod: inout ModDBMod, html: String) {
        if let title = first(html, "property=\"og:title\" content=\"([^\"]+)\"") {
            let cleaned = title.replacingOccurrences(of: " mod for Quake", with: "")
            if !cleaned.isEmpty { mod.title = QuaddictedIndex.stripTags(cleaned) }
        }
        if let desc = first(html, "property=\"og:description\" content=\"([^\"]+)\"")
            ?? first(html, "name=\"description\" content=\"([^\"]+)\"") {
            mod.descriptionText = QuaddictedIndex.stripTags(desc)
        }
        if let img = first(html, "property=\"og:image\" content=\"([^\"]+)\"") {
            mod.screenshotURL = URL(string: img)
        }
        if let author = first(html, "<h5>Creator</h5>.*?itemprop=\"name\">(.*?)</span>")
            ?? first(html, "<h5>Creator</h5>.*?<a[^>]*>(.*?)</a>") {
            mod.author = QuaddictedIndex.stripTags(author)
        }
        if let value = first(html, "itemprop=\"ratingValue\" content=\"([0-9.]+)\"") {
            mod.rating = Double(value) ?? 0
        }
        if let count = first(html, "itemprop=\"ratingCount\" content=\"(\\d+)\"") {
            mod.ratingCount = Int(count) ?? 0
        }
        let files = files(in: html, slug: mod.slug)
        if !files.isEmpty { mod.files = files }
        mod.detailLoaded = true
    }

    static func applyFilePage(to file: inout ModDBFile, html: String) {
        if let name = labeled(html, "Filename") { file.filename = name }
        if let hash = labeled(html, "MD5 Hash") { file.md5 = hash.lowercased() }
        if let size = labeled(html, "Size"),
           let bytes = first(size, "\\(([0-9,]+)\\s*bytes\\)") ?? first(size, "\\(([0-9,]+)") {
            file.sizeBytes = Int(bytes.replacingOccurrences(of: ",", with: "")) ?? 0
        }
        if let cat = first(html, "<h5>Category</h5>.*?<a[^>]*>(.*?)</a>") {
            file.category = QuaddictedIndex.stripTags(cat)
        }
        if let id = first(html, "/downloads/start/(\\d+)") ?? first(html, "siteareaid=(\\d+)") {
            file.fileID = Int(id)
        }
        if file.fileID == nil, let src = first(html, "images/downloads/\\d+/\\d+/(\\d+)/") {
            file.fileID = Int(src)
        }
    }

    static func mirrorURL(in html: String, filename: String?) -> URL? {
        if let path = first(html, "href=\"(/downloads/mirror/[^\"]+)\""),
           let url = URL(string: "https://www.moddb.com" + path) {
            return url
        }
        if let filename, !filename.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: filename)
            if let path = first(html, "href=\"([^\"]+)\"[^>]*>\\s*download\\s+\(escaped)"),
               let url = absolute(path) {
                return url
            }
        }
        if let path = first(html, "href=\"([^\"]+)\"[^>]*>\\s*download\\s+", options: [.caseInsensitive]),
           let url = absolute(path) {
            return url
        }
        return nil
    }

    static func preferredFile(_ files: [ModDBFile]) -> ModDBFile? {
        let skip = files.filter {
            let c = $0.category.lowercased()
            return !c.contains("tutorial") && !c.contains("source")
        }
        let pool = skip.isEmpty ? files : skip
        if let full = pool.first(where: { $0.category.lowercased().contains("full") }) { return full }
        if let zip = pool.first(where: { $0.ext == "zip" || $0.filename.lowercased().hasSuffix(".zip") }) { return zip }
        return pool.first
    }

    static func idFromMediaPath(_ src: String) -> Int? {
        first(src, "images/downloads/\\d+/\\d+/(\\d+)/").flatMap(Int.init)
    }

    // MARK: drobne

    private static func labeled(_ html: String, _ label: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: label)
        return first(html, "<h5>\\s*\(escaped)\\s*</h5>\\s*<span[^>]*>(.*?)</span>")
            .map { QuaddictedIndex.stripTags($0) }
    }

    private static func parseTime(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        if raw.count >= 10 {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd"
            return df.date(from: String(raw.prefix(10)))
        }
        return nil
    }

    private static func absolute(_ path: String) -> URL? {
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: path.hasPrefix("/") ? "https://www.moddb.com\(path)" : "https://www.moddb.com/\(path)")
    }

    private static func slice(_ html: String, after: String, before: String) -> String? {
        guard let a = html.range(of: after) else { return nil }
        let rest = html[a.upperBound...]
        guard let b = rest.range(of: before) else { return String(rest) }
        return String(rest[..<b.lowerBound])
    }

    private static func ns(_ s: String) -> NSRange { NSRange(s.startIndex..., in: s) }

    private static func slice(_ s: String, _ match: NSTextCheckingResult, _ group: Int) -> String {
        let range = match.range(at: group)
        guard let swift = Range(range, in: s) else { return "" }
        return String(s[swift])
    }

    static func first(_ s: String, _ pattern: String, options: NSRegularExpression.Options = [.dotMatchesLineSeparators]) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options),
              let match = re.firstMatch(in: s, range: ns(s)), match.numberOfRanges > 1
        else { return nil }
        return slice(s, match, 1)
    }

    static func all(_ s: String, _ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        return re.matches(in: s, range: ns(s)).compactMap { match in
            match.numberOfRanges > 1 ? slice(s, match, 1) : nil
        }
    }
}

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

// MARK: - Model przeglądarki

@MainActor
final class ModDBModel: ObservableObject {
    @Published var mods: [ModDBMod] = []
    @Published var searchText = ""
    @Published var onlyInstalled = false
    @Published var onlyReleased = false
    @Published var loading = false
    @Published var statusText = ""
    @Published var installing: Set<String> = []
    @Published var challengeVisible = false

    let client = ModDBClient()
    private let fm = FileManager.default

    private static let cacheName = "moddb_quake_mods.json"
    private static let listingURL = URL(string: "https://www.moddb.com/games/quake/mods")!

    init() {
        client.onChallengeChange = { [weak self] visible in
            self?.challengeVisible = visible
        }
    }

    func filtered(launcher: LauncherModel, registry: InstallRegistry) -> [ModDBMod] {
        var result = mods
        if onlyReleased { result = result.filter(\.isReleased) }
        for i in result.indices {
            result[i].installedAt = registry.entry(.moddb, result[i].slug)?.installedAt
        }
        if onlyInstalled { result = result.filter { isInstalled($0, registry: registry, launcher: launcher) } }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(query)
                    || $0.slug.lowercased().contains(query)
                    || $0.author.lowercased().contains(query)
                    || $0.summary.lowercased().contains(query)
            }
        }
        return result
    }

    func isInstalled(_ mod: ModDBMod, registry: InstallRegistry, launcher: LauncherModel? = nil) -> Bool {
        if registry.isInstalled(.moddb, mod.slug) { return true }
        // mod bywa też rozpakowany ręcznie — wtedy poznajemy go po katalogu z danymi gry
        guard let base = launcher?.baseDir else { return false }
        let name = registry.entry(.moddb, mod.slug)?.gameDir ?? mod.slug
        return PackageFS.looksLikeGameDir(base.appendingPathComponent(name))
    }

    func loadIfNeeded() async {
        guard mods.isEmpty, !loading else { return }
        await load(force: false)
    }

    func load(force: Bool) async {
        loading = true
        defer { loading = false }
        if !force, let cached = loadCache(), Date().timeIntervalSince(cached.date) < 24 * 3600 {
            mods = cached.mods
            statusText = "ModDB (cache): \(cached.mods.count) modów."
            return
        }
        do {
            statusText = "Pobieram listę ModDB…"
            var all: [ModDBMod] = []
            var seen = Set<String>()
            let firstHTML = try await client.html(from: Self.listingURL)
            challengeVisible = client.challengeVisible
            guard !ModDBHTML.isCloudflare(firstHTML) else {
                statusText = "ModDB zablokował automatyczne pobieranie (Cloudflare). Dokończ weryfikację w oknie i odśwież."
                return
            }
            let pages = ModDBHTML.listingPages(firstHTML)
            for mod in ModDBHTML.listing(firstHTML) where seen.insert(mod.slug).inserted {
                all.append(mod)
            }
            if pages > 1 {
                for page in 2 ... pages {
                    statusText = "Pobieram listę ModDB (\(page)/\(pages))…"
                    guard let url = URL(string: "https://www.moddb.com/games/quake/mods/page/\(page)") else { continue }
                    let html = try await client.html(from: url)
                    for mod in ModDBHTML.listing(html) where seen.insert(mod.slug).inserted {
                        all.append(mod)
                    }
                }
            }
            mods = all
            saveCache(all)
            statusText = "ModDB: \(all.count) modów do Quake 1."
        } catch is CancellationError {
            statusText = "Anulowano weryfikację ModDB."
        } catch {
            if mods.isEmpty, let cached = loadCache() {
                mods = cached.mods
                statusText = "Sieć padła — cache z \(cached.mods.count) pozycjami. (\(error.localizedDescription))"
            } else {
                statusText = "Nie udało się pobrać listy ModDB: \(error.localizedDescription)"
            }
        }
        challengeVisible = client.challengeVisible
    }

    func ensureDetail(_ slug: String) async {
        guard let idx = mods.firstIndex(where: { $0.slug == slug }), !mods[idx].detailLoaded else { return }
        do {
            let html = try await client.html(from: mods[idx].pageURL)
            var mod = mods[idx]
            ModDBHTML.applyDetail(to: &mod, html: html)
            if mod.files.isEmpty, let downloads = URL(string: "https://www.moddb.com/mods/\(mod.slug)/downloads") {
                let extra = try await client.html(from: downloads)
                let files = ModDBHTML.files(in: extra, slug: mod.slug)
                if !files.isEmpty { mod.files = files }
            }
            mods[idx] = mod
        } catch {
            statusText = "Nie udało się pobrać strony \(slug): \(error.localizedDescription)"
        }
    }

    private var cacheFile: URL {
        let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.marcinkleczek.quakelauncher")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Self.cacheName)
    }

    private func loadCache() -> (date: Date, mods: [ModDBMod])? {
        guard let data = try? Data(contentsOf: cacheFile),
              let box = try? JSONDecoder().decode(ModDBCache.self, from: data)
        else { return nil }
        return (box.fetchedAt, box.mods)
    }

    private func saveCache(_ mods: [ModDBMod]) {
        let box = ModDBCache(fetchedAt: Date(), mods: mods)
        if let data = try? JSONEncoder().encode(box) { try? data.write(to: cacheFile, options: .atomic) }
    }

    // MARK: Instalacja

    func install(_ modIn: ModDBMod, file picked: ModDBFile?, launcher: LauncherModel, registry: InstallRegistry) async {
        guard let base = launcher.baseDir else {
            statusText = "Najpierw ustaw katalog Quake'a w oknie launchera."
            return
        }
        var mod = modIn
        installing.insert(mod.slug)
        defer { installing.remove(mod.slug) }
        if !mod.detailLoaded {
            await ensureDetail(mod.slug)
            guard let fresh = mods.first(where: { $0.slug == mod.slug }) else { return }
            mod = fresh
        }
        guard var file = picked ?? ModDBHTML.preferredFile(mod.files) else {
            statusText = "Ten mod nie ma jeszcze plików na ModDB."
            return
        }
        do {
            statusText = "Pobieram szczegóły pliku \(file.title)…"
            let fileURL = URL(string: "https://www.moddb.com/mods/\(mod.slug)/downloads/\(file.slug)")!
            let fileHTML = try await client.html(from: fileURL)
            challengeVisible = client.challengeVisible
            ModDBHTML.applyFilePage(to: &file, html: fileHTML)
            if file.isInstaller {
                statusText = "Plik \(file.filename.isEmpty ? file.title : file.filename) to instalator Windows/macOS — launcher go nie rozpakuje. Otwórz stronę ModDB."
                return
            }
            guard let fileID = file.fileID else {
                statusText = "Nie znalazłem linku do pobrania dla \(file.title)."
                return
            }
            statusText = "Szukam lustra ModDB dla \(file.filename.isEmpty ? file.title : file.filename)…"
            let start = URL(string: "https://www.moddb.com/downloads/start/\(fileID)")!
            var startHTML = try await client.html(from: start)
            var mirror = ModDBHTML.mirrorURL(in: startHTML, filename: file.filename.isEmpty ? nil : file.filename)
            if mirror == nil, let all = URL(string: "https://www.moddb.com/downloads/start/\(fileID)/all") {
                startHTML = try await client.html(from: all)
                mirror = ModDBHTML.mirrorURL(in: startHTML, filename: file.filename.isEmpty ? nil : file.filename)
            }
            guard let mirror else {
                statusText = "ModDB nie oddał lustra pliku. Spróbuj ponownie albo pobierz ręcznie ze strony."
                return
            }
            let label = file.filename.isEmpty ? file.title : file.filename
            let sizeHint = file.sizeText.isEmpty ? "" : " (\(file.sizeText))"
            statusText = "Pobieram \(label)\(sizeHint)…"
            let tempName = file.filename.isEmpty ? "download.bin" : file.filename
            let tempFile = fm.temporaryDirectory.appendingPathComponent("qmoddb-\(UUID().uuidString)-\(tempName)")
            let staging = fm.temporaryDirectory.appendingPathComponent("qmoddb-unpack-\(UUID().uuidString)")
            // sprzątanie zarejestrowane PRZED pobraniem — przerwane pobranie też zostawia plik
            defer {
                try? fm.removeItem(at: tempFile)
                try? fm.removeItem(at: staging)
            }
            try await client.download(mirror, to: tempFile)

            statusText = "Rozpakowuję \(label)…"
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try PackageFS.extract(tempFile, to: staging)
            PackageFS.lowercaseNames(in: staging)
            try PackageFS.peelNestedArchives(in: staging)

            let placed = try PackageFS.placeGameDir(from: staging, fallbackName: mod.slug, base: base)
            let target = base.appendingPathComponent(placed)
            let launchable = PackageFS.looksLikeGameDir(target)

            let bspNames = PackageFS.bspNames(in: target)

            let actual = launcher.actualGameDir(placed)
            registry.record(source: .moddb, slug: mod.slug, title: mod.title,
                            gameDir: actual, maps: bspNames, base: base)
            launcher.rescan()
            if launcher.mods.contains(actual) { launcher.selectedMod = actual }

            if !launchable {
                statusText = "Rozpakowano do \(actual)/, ale nie da się tego uruchomić jako moda (brak pak/progs.dat/maps)."
            } else if let warn = mod.engineWarning {
                statusText = "Zainstalowano \(mod.title) → \(actual)/. \(warn)"
            } else {
                statusText = "Zainstalowano \(mod.title) → \(actual)/ — można uruchomić (Graj albo Launch)."
            }
        } catch {
            statusText = "Błąd instalacji \(mod.slug): \(error.localizedDescription)"
        }
    }

    func play(_ mod: ModDBMod, launcher: LauncherModel, registry: InstallRegistry, map: String? = nil) {
        let dir = registry.entry(.moddb, mod.slug)?.gameDir ?? mod.slug
        guard launcher.canRun(gameDir: dir) else {
            statusText = "Katalog \(launcher.actualGameDir(dir))/ nie wygląda na moda Quake'a — nie uruchamiam."
            return
        }
        launcher.runGame(gameDir: dir, map: map ?? startMap(for: mod, registry: registry))
        statusText = launcher.status
    }

    func canLaunch(_ mod: ModDBMod, launcher: LauncherModel, registry: InstallRegistry) -> Bool {
        guard let base = launcher.baseDir else { return false }
        let game = launcher.actualGameDir(registry.entry(.moddb, mod.slug)?.gameDir ?? mod.slug)
        return PackageFS.looksLikeGameDir(base.appendingPathComponent(game))
    }

    func availableMaps(_ mod: ModDBMod, registry: InstallRegistry) -> [String] {
        registry.entry(.moddb, mod.slug)?.maps ?? []
    }

    /// +map tylko gdy wiemy, od czego zacząć. Pierwsza z brzegu .bsp to często DM — wtedy menu.
    private func startMap(for mod: ModDBMod, registry: InstallRegistry) -> String? {
        let maps = availableMaps(mod, registry: registry)
        let preferred = ["start", "start1", "startmap"]
        if let named = preferred.first(where: { maps.contains($0) }) { return named }
        return maps.count == 1 ? maps[0] : nil
    }

}

private struct ModDBCache: Codable {
    var fetchedAt: Date
    var mods: [ModDBMod]
}

// MARK: - Okno przeglądarki
//
// Układ jak w przeglądarce Quaddicted: tabela po lewej, szczegóły po prawej.
// ModDB dokłada dwie rzeczy, których tamta nie potrzebuje — ramkę Cloudflare
// (challenge trzeba czasem kliknąć ręcznie) i wybór pliku, bo mod ma zwykle
// kilka pozycji do pobrania: pełną wersję, patch, wersję źródłową.

struct ModDBBrowserView: View {
    @ObservedObject var launcher: LauncherModel
    @ObservedObject var browser: ModDBModel
    @ObservedObject var registry: InstallRegistry

    @State private var selection: String?
    @State private var sortOrder = [KeyPathComparator(\ModDBMod.updatedSort, order: .reverse)]

    private var rows: [ModDBMod] {
        browser.filtered(launcher: launcher, registry: registry).sorted(using: sortOrder)
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 8) {
                HStack {
                    TextField("Szukaj na ModDB…", text: $browser.searchText)
                        .textFieldStyle(.roundedBorder)
                    Toggle("Wydane", isOn: $browser.onlyReleased)
                    Toggle("Pobrane", isOn: $browser.onlyInstalled)
                    Button {
                        Task { await browser.load(force: true) }
                    } label: { Image(systemName: "arrow.clockwise") }
                        .help("Odśwież listę z ModDB")
                        .disabled(browser.loading)
                }
                .padding([.top, .horizontal], 10)

                if browser.challengeVisible {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("ModDB prosi o potwierdzenie — kliknij w ramce poniżej.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                        ModDBWebView(client: browser.client)
                            .frame(height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                    }
                    .padding(.horizontal, 10)
                }

                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Tytuł", value: \.title) { mod in
                        HStack(spacing: 4) {
                            if browser.isInstalled(mod, registry: registry, launcher: launcher) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                            Text(mod.title.isEmpty ? mod.slug : mod.title).lineLimit(1)
                        }
                    }
                    // tytuł potrzebuje gwarantowanego minimum — bez tego sztywne kolumny
                    // zjadały całą szerokość i zostawało „Lib…”
                    .width(min: 200, ideal: 300)
                    TableColumn("Status", value: \.status) { Text($0.statusText).lineLimit(1) }.width(150)
                    TableColumn("Gatunek", value: \.genre) { Text($0.genre).lineLimit(1) }.width(120)
                    TableColumn("Aktualizacja", value: \.updatedSort) { Text($0.updatedText) }.width(90)
                    TableColumn("Pobrano", value: \.installedSort) { mod in
                        Text(mod.installedText)
                            .foregroundStyle(mod.installedAt == nil ? .secondary : .primary)
                    }
                    .width(90)
                }

                HStack {
                    if browser.loading { ProgressView().controlSize(.small) }
                    Text(browser.statusText).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    Text("\(rows.count) z \(browser.mods.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding([.bottom, .horizontal], 10)
            }
            .frame(minWidth: 660)

            Group {
                if let mod = rows.first(where: { $0.slug == selection })
                    ?? browser.mods.first(where: { $0.slug == selection }) {
                    ModDBDetail(launcher: launcher, browser: browser, registry: registry, mod: mod)
                } else {
                    Text("Wybierz moda z listy")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 340)
        }
        .frame(minWidth: 1060, minHeight: 560)
        .task { await browser.loadIfNeeded() }
    }
}

struct ModDBDetail: View {
    @ObservedObject var launcher: LauncherModel
    @ObservedObject var browser: ModDBModel
    @ObservedObject var registry: InstallRegistry
    let mod: ModDBMod

    private var subtitle: String {
        [mod.author, mod.statusText, mod.genre, mod.updatedText]
            .filter { !$0.isEmpty && $0 != "—" }
            .joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(mod.title.isEmpty ? mod.slug : mod.title).font(.title3).bold()
                Text(subtitle).font(.caption).foregroundStyle(.secondary)

                AsyncImage(url: mod.screenshotURL ?? mod.thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 6))
                    case .failure:
                        Label("Brak zrzutu ekranu", systemImage: "photo")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100)
                    default:
                        ProgressView().frame(maxWidth: .infinity, minHeight: 100)
                    }
                }
                .frame(maxHeight: 260)

                actions

                if let warn = mod.engineWarning {
                    Label(warn, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }

                if !mod.files.isEmpty {
                    Divider()
                    Text("PLIKI DO POBRANIA").font(.caption2.bold()).foregroundStyle(.secondary)
                    ForEach(mod.files) { file in
                        fileRow(file)
                    }
                }

                if !mod.descriptionText.isEmpty {
                    Divider()
                    Text(mod.descriptionText).textSelection(.enabled)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: mod.slug) { await browser.ensureDetail(mod.slug) }
    }

    @ViewBuilder private var actions: some View {
        HStack {
            if browser.installing.contains(mod.slug) {
                ProgressView().controlSize(.small)
                Text("Instaluję…").font(.caption)
            } else if let entry = registry.entry(.moddb, mod.slug) {
                if launcher.canRun(gameDir: entry.gameDir) {
                    Button("Graj ▶") { browser.play(mod, launcher: launcher, registry: registry) }
                        .buttonStyle(.borderedProminent)
                    if entry.maps.count > 1 {
                        Menu("mapa ▾") {
                            ForEach(entry.maps, id: \.self) { map in
                                Button(map) { browser.play(mod, launcher: launcher, registry: registry, map: map) }
                            }
                        }
                        .frame(width: 90)
                    }
                } else {
                    Text("nie do odpalenia").font(.caption).foregroundStyle(.orange)
                        .help("W katalogu \(entry.gameDir ?? "—") nie ma pak/progs.dat/maps.")
                }
                Label("pobrane \(entry.dateText)", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else if !mod.detailLoaded {
                ProgressView().controlSize(.small)
                Text("Pobieram szczegóły…").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Pobierz i zainstaluj") {
                    Task { await browser.install(mod, file: nil, launcher: launcher, registry: registry) }
                }
                .buttonStyle(.borderedProminent)
                .help("Wybierze plik automatycznie — poniżej możesz wskazać konkretny.")
            }
            Spacer()
            Link("ModDB ↗", destination: mod.pageURL)
        }
    }

    /// Pozycja listy plików. ModDB trzyma pod jednym modem pełne wersje, patche i paczki
    /// źródłowe — automat wybiera „full", ale czasem trzeba wskazać coś ręcznie.
    @ViewBuilder private func fileRow(_ file: ModDBFile) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(file.title).font(.callout).lineLimit(1)
                Text([file.category, file.date, file.sizeText]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if file.isInstaller {
                Text("instalator").font(.caption2).foregroundStyle(.orange)
                    .help("Plik .exe/.dmg — launcher go nie rozpakuje.")
            } else if !browser.installing.contains(mod.slug) {
                Button("Pobierz") {
                    Task { await browser.install(mod, file: file, launcher: launcher, registry: registry) }
                }
                .controlSize(.small)
            }
        }
    }
}

struct ModDBWebView: NSViewRepresentable {
    let client: ModDBClient

    func makeNSView(context: Context) -> WKWebView {
        client.attachedWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
