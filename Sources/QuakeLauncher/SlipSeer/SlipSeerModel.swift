import SwiftUI

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
            statusText = "SlipSeer (cache): \(cached.items.count) items."
            return
        }
        do {
            statusText = "Downloading SlipSeer list…"
            var all: [SlipSeerResource] = []
            var seen = Set<String>()
            let firstHTML = try await html(Self.listURL)
            let pages = min(SlipSeerHTML.pages(firstHTML), Self.pageLimit)
            for r in SlipSeerHTML.listing(firstHTML) where seen.insert(r.slug).inserted { all.append(r) }
            if pages > 1 {
                for page in 2 ... pages {
                    statusText = "Downloading SlipSeer list (\(page)/\(pages))…"
                    let url = "https://www.slipseer.com/index.php?resources/&page=\(page)"
                    let page = try await html(url)
                    for r in SlipSeerHTML.listing(page) where seen.insert(r.slug).inserted { all.append(r) }
                }
            }
            resources = all
            saveCache(all)
            statusText = "SlipSeer: \(all.count) items."
        } catch {
            if resources.isEmpty, let cached = loadCache() {
                resources = cached.items
                statusText = "Network down — using cache with \(cached.items.count) items."
            } else {
                statusText = "Couldn't download SlipSeer: \(error.localizedDescription)"
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
            statusText = "Set the Quake folder in the launcher window first."
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
            statusText = "Downloading \(res.title.isEmpty ? res.name : res.title)…"
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
                statusText = "\(res.name) is only a link to another site on SlipSeer — download it manually from the resource page."
                return
            }

            statusText = "Unpacking…"
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
                statusText = "Installed \(res.title) → \(actual)/ (\(maps.count) \(maps.count == 1 ? "map" : "maps"))."
            } else {
                statusText = "Unpacked to \(actual)/, but it doesn't look like a game directory (no pak/progs.dat/maps)."
            }
        } catch {
            statusText = "Install failed for \(res.name): \(error.localizedDescription)"
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
