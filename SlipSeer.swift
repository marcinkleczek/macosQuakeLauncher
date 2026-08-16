import SwiftUI

// MARK: - SlipSeer
//
// slipseer.com to XenForo z Resource Managerem: zwykły HTML, HTTP 200, bez Cloudflare —
// więc w przeciwieństwie do ModDB wystarcza URLSession. Struktura listy jest przewidywalna
// (`structItem--resource`, `js-resourceListItem-<id>`), a plik siedzi pod /download.
// Uwaga: część zasobów to nie pliki na serwerze, tylko odsyłacze na zewnętrzne hosty —
// wtedy /download odpowiada przekierowaniem na stronę WWW, a nie archiwum.

struct SlipSeerResource: Identifiable, Hashable, Codable {
    /// XenForo adresuje zasób jako "nazwa.id", np. "quake-brutalist-jam-iii.549".
    var slug: String
    var title = ""
    var author = ""
    var summary = ""
    var category = ""
    var updated: Date?
    var iconURL: URL?
    var rating = 0.0
    var descriptionText = ""
    var detailLoaded = false
    /// Data pobrania z rejestru — wstrzykiwana przy filtrowaniu, żeby tabela mogła sortować.
    var installedAt: Date?

    var id: String { slug }

    var pageURL: URL { URL(string: "https://www.slipseer.com/index.php?resources/\(slug)/")! }
    var downloadURL: URL { URL(string: "https://www.slipseer.com/index.php?resources/\(slug)/download")! }

    /// Sama nazwa bez numeru — na katalog gry i tak trafia wersja małymi literami.
    var name: String {
        guard let dot = slug.lastIndex(of: "."), slug[slug.index(after: dot)...].allSatisfy(\.isNumber)
        else { return slug }
        return String(slug[..<dot])
    }

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

    /// Kategorie SlipSeera, które nie są mapami do zainstalowania w katalogu gry.
    var isTooling: Bool {
        let c = category.lowercased()
        return c.contains("tool") || c.contains("asset") || c.contains("3d model")
            || c.contains("texture") || c.contains("sound") || c.contains("source")
    }

    /// Mody bazowe, na których stoją inne mapy — warto je mieć zanim pobierze się resztę.
    var isBaseMod: Bool {
        ["alkaline", "arcane dimensions", "copper", "quoth", "progs_dump"].contains {
            category.lowercased().contains($0)
        }
    }

    private static let day: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
}

enum SlipSeerHTML {
    static func listing(_ html: String) -> [SlipSeerResource] {
        // każdy wiersz zaczyna się markerem js-resourceListItem-<id>; tniemy po nim,
        // bo zagnieżdżone <div>y uniemożliwiają dopasowanie całego bloku regexpem
        let chunks = html.components(separatedBy: "js-resourceListItem-").dropFirst()
        var result: [SlipSeerResource] = []
        var seen = Set<String>()
        for chunk in chunks {
            guard let slug = ModDBHTML.first(chunk, #"href="/index\.php\?resources/([^"/?#&]+\.\d+)/?""#),
                  seen.insert(slug).inserted else { continue }
            var res = SlipSeerResource(slug: slug)
            res.author = ModDBHTML.first(chunk, #"data-author="([^"]*)""#) ?? ""
            if let title = ModDBHTML.first(chunk, #"class="structItem-title">\s*<a[^>]*>(.*?)</a>"#) {
                res.title = QuaddictedIndex.stripTags(title)
            }
            if let tag = ModDBHTML.first(chunk, #"class="structItem-resourceTagLine">(.*?)</div>"#) {
                res.summary = QuaddictedIndex.stripTags(tag)
            }
            if let cat = ModDBHTML.first(chunk, #"\?resources/categories/[^"]*">(.*?)</a>"#) {
                res.category = QuaddictedIndex.stripTags(cat)
            }
            if let stamp = ModDBHTML.first(chunk, #"data-timestamp="(\d+)""#), let secs = Double(stamp) {
                res.updated = Date(timeIntervalSince1970: secs)
            }
            if let icon = ModDBHTML.first(chunk, #"<img src="([^"]+resource_icons[^"]+)""#) {
                res.iconURL = URL(string: icon.replacingOccurrences(of: "&amp;", with: "&"))
            }
            if let rating = ModDBHTML.first(chunk, #"title="([0-9.]+) star"#) {
                res.rating = Double(rating) ?? 0
            }
            result.append(res)
        }
        return result
    }

    /// Ostatnia strona listy. Uwaga: w HTML link wygląda jak `?resources/&amp;page=29`,
    /// więc bezpośrednio przed „page=" stoi średnik z encji, a nie „&" — wzorzec
    /// wymagający `[?&]page=` nie trafiał niczego i lista kończyła się na pierwszej stronie.
    static func pages(_ html: String) -> Int {
        let nums = ModDBHTML.all(html, #"page=(\d+)"#).compactMap(Int.init)
            + ModDBHTML.all(html, #"page-(\d+)"#).compactMap(Int.init)
        return max(1, nums.max() ?? 1)
    }

    static func applyDetail(to res: inout SlipSeerResource, html: String) {
        if let desc = ModDBHTML.first(html, #"property="og:description" content="([^"]+)""#) {
            res.descriptionText = QuaddictedIndex.stripTags(desc)
                .replacingOccurrences(of: "&amp;", with: "&")
        }
        if res.title.isEmpty, let title = ModDBHTML.first(html, #"property="og:title" content="([^"]+)""#) {
            res.title = QuaddictedIndex.stripTags(title)
        }
        res.detailLoaded = true
    }
}

// MARK: - Model

@MainActor
final class SlipSeerModel: ObservableObject {
    @Published var resources: [SlipSeerResource] = []
    @Published var searchText = ""
    @Published var hideTooling = true
    @Published var loading = false
    @Published var statusText = ""
    @Published var installing: Set<String> = []

    private let fm = FileManager.default
    private static let cacheName = "slipseer_resources.json"
    private static let listURL = "https://www.slipseer.com/index.php?resources/"
    /// Tyle stron pobieramy maksymalnie — lista ma ich obecnie ~29, a każda to jedno żądanie.
    private static let pageLimit = 40

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": ModDBClient.userAgent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
        ]
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 1800
        return URLSession(configuration: config)
    }()

    func filtered(registry: InstallRegistry) -> [SlipSeerResource] {
        var result = resources
        if hideTooling { result = result.filter { !$0.isTooling } }
        for i in result.indices {
            result[i].installedAt = registry.entry(.slipseer, result[i].slug)?.installedAt
        }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(query) || $0.author.lowercased().contains(query)
                    || $0.summary.lowercased().contains(query) || $0.category.lowercased().contains(query)
            }
        }
        return result
    }

    func loadIfNeeded() async {
        guard resources.isEmpty, !loading else { return }
        await load(force: false)
    }

    func load(force: Bool) async {
        loading = true
        defer { loading = false }
        if !force, let cached = loadCache(), Date().timeIntervalSince(cached.date) < 24 * 3600 {
            resources = cached.items
            statusText = "SlipSeer (cache): \(cached.items.count) pozycji."
            return
        }
        do {
            statusText = "Pobieram listę SlipSeer…"
            var all: [SlipSeerResource] = []
            var seen = Set<String>()
            let firstHTML = try await html(Self.listURL)
            let pages = min(SlipSeerHTML.pages(firstHTML), Self.pageLimit)
            for r in SlipSeerHTML.listing(firstHTML) where seen.insert(r.slug).inserted { all.append(r) }
            if pages > 1 {
                for page in 2 ... pages {
                    statusText = "Pobieram listę SlipSeer (\(page)/\(pages))…"
                    let url = "https://www.slipseer.com/index.php?resources/&page=\(page)"
                    let page = try await html(url)
                    for r in SlipSeerHTML.listing(page) where seen.insert(r.slug).inserted { all.append(r) }
                }
            }
            resources = all
            saveCache(all)
            statusText = "SlipSeer: \(all.count) pozycji."
        } catch {
            if resources.isEmpty, let cached = loadCache() {
                resources = cached.items
                statusText = "Sieć padła — cache z \(cached.items.count) pozycjami."
            } else {
                statusText = "Nie udało się pobrać SlipSeer: \(error.localizedDescription)"
            }
        }
    }

    func ensureDetail(_ slug: String) async {
        guard let idx = resources.firstIndex(where: { $0.slug == slug }), !resources[idx].detailLoaded else { return }
        guard let page = try? await html(resources[idx].pageURL.absoluteString) else { return }
        var res = resources[idx]
        SlipSeerHTML.applyDetail(to: &res, html: page)
        resources[idx] = res
    }

    private func html(_ url: String) async throws -> String {
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: u)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Instalacja

    func install(_ res: SlipSeerResource, launcher: LauncherModel, registry: InstallRegistry) async {
        guard let base = launcher.baseDir else {
            statusText = "Najpierw ustaw katalog Quake'a w oknie launchera."
            return
        }
        installing.insert(res.slug)
        defer { installing.remove(res.slug) }
        let staging = fm.temporaryDirectory.appendingPathComponent("qslip-unpack-\(UUID().uuidString)")
        let tempFile = fm.temporaryDirectory.appendingPathComponent("qslip-\(UUID().uuidString)")
        defer {
            try? fm.removeItem(at: staging)
            try? fm.removeItem(at: tempFile)
        }
        do {
            statusText = "Pobieram \(res.title.isEmpty ? res.name : res.title)…"
            var request = URLRequest(url: res.downloadURL)
            request.setValue(ModDBClient.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("https://www.slipseer.com/", forHTTPHeaderField: "Referer")
            let (downloaded, response) = try await session.download(for: request)
            try? fm.removeItem(at: tempFile)
            try fm.moveItem(at: downloaded, to: tempFile)

            let http = response as? HTTPURLResponse
            guard (200 ... 299).contains(http?.statusCode ?? 0) else { throw URLError(.badServerResponse) }
            // zasoby będące odsyłaczem oddają stronę WWW zamiast archiwum
            let type = (http?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            if type.contains("text/html") {
                statusText = "\(res.name) jest na SlipSeer tylko odsyłaczem do innej strony — pobierz ręcznie ze strony zasobu."
                return
            }

            statusText = "Rozpakowuję…"
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try PackageFS.extract(tempFile, to: staging)
            PackageFS.lowercaseNames(in: staging)
            try PackageFS.peelNestedArchives(in: staging)

            let placed = try PackageFS.placeGameDir(from: staging, fallbackName: res.name, base: base)
            let target = base.appendingPathComponent(placed)
            let maps = PackageFS.bspNames(in: target)
            let actual = launcher.actualGameDir(placed)

            registry.record(source: .slipseer, slug: res.slug,
                            title: res.title.isEmpty ? res.name : res.title,
                            gameDir: actual, maps: maps, base: base)
            launcher.rescan()
            if launcher.mods.contains(actual) { launcher.selectedMod = actual }

            if PackageFS.looksLikeGameDir(target) {
                statusText = "Zainstalowano \(res.title) → \(actual)/ (\(maps.count) map)."
            } else {
                statusText = "Rozpakowano do \(actual)/, ale to nie wygląda na katalog gry (brak pak/progs.dat/maps)."
            }
        } catch {
            statusText = "Błąd instalacji \(res.name): \(error.localizedDescription)"
        }
    }

    // MARK: Cache

    private var cacheFile: URL {
        let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.marcinkleczek.quakelauncher")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Self.cacheName)
    }

    private struct Cache: Codable {
        var fetchedAt: Date
        var items: [SlipSeerResource]
    }

    private func loadCache() -> (date: Date, items: [SlipSeerResource])? {
        guard let data = try? Data(contentsOf: cacheFile),
              let box = try? JSONDecoder().decode(Cache.self, from: data) else { return nil }
        return (box.fetchedAt, box.items)
    }

    private func saveCache(_ items: [SlipSeerResource]) {
        let box = Cache(fetchedAt: Date(), items: items)
        if let data = try? JSONEncoder().encode(box) { try? data.write(to: cacheFile, options: .atomic) }
    }
}
