import SwiftUI

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
            statusText = "ModDB (cache): \(cached.mods.count) mods."
            return
        }
        do {
            statusText = "Downloading ModDB list…"
            var all: [ModDBMod] = []
            var seen = Set<String>()
            let firstHTML = try await client.html(from: Self.listingURL)
            challengeVisible = client.challengeVisible
            guard !ModDBHTML.isCloudflare(firstHTML) else {
                statusText = "ModDB blocked automatic downloading (Cloudflare). Complete the Cloudflare check in the window and refresh."
                return
            }
            let pages = ModDBHTML.listingPages(firstHTML)
            for mod in ModDBHTML.listing(firstHTML) where seen.insert(mod.slug).inserted {
                all.append(mod)
            }
            if pages > 1 {
                for page in 2 ... pages {
                    statusText = "Downloading ModDB list (\(page)/\(pages))…"
                    guard let url = URL(string: "https://www.moddb.com/games/quake/mods/page/\(page)") else { continue }
                    let html = try await client.html(from: url)
                    for mod in ModDBHTML.listing(html) where seen.insert(mod.slug).inserted {
                        all.append(mod)
                    }
                }
            }
            mods = all
            saveCache(all)
            statusText = "ModDB: \(all.count) Quake 1 mods."
        } catch is CancellationError {
            statusText = "ModDB check cancelled."
        } catch {
            if mods.isEmpty, let cached = loadCache() {
                mods = cached.mods
                statusText = "Network down — using cache with \(cached.mods.count) items. (\(error.localizedDescription))"
            } else {
                statusText = "Couldn't download ModDB list: \(error.localizedDescription)"
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
            statusText = "Couldn't download page \(slug): \(error.localizedDescription)"
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
            statusText = "Set the Quake folder in the launcher window first."
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
            statusText = "This mod has no files on ModDB yet."
            return
        }
        do {
            statusText = "Loading file details for \(file.title)…"
            let fileURL = URL(string: "https://www.moddb.com/mods/\(mod.slug)/downloads/\(file.slug)")!
            let fileHTML = try await client.html(from: fileURL)
            challengeVisible = client.challengeVisible
            ModDBHTML.applyFilePage(to: &file, html: fileHTML)
            if file.isInstaller {
                statusText = "File \(file.filename.isEmpty ? file.title : file.filename) is a Windows/macOS installer — the launcher can't unpack it. Open the ModDB page."
                return
            }
            guard let fileID = file.fileID else {
                statusText = "Couldn't find a download link for \(file.title)."
                return
            }
            statusText = "Looking for a ModDB mirror for \(file.filename.isEmpty ? file.title : file.filename)…"
            let start = URL(string: "https://www.moddb.com/downloads/start/\(fileID)")!
            var startHTML = try await client.html(from: start)
            var mirror = ModDBHTML.mirrorURL(in: startHTML, filename: file.filename.isEmpty ? nil : file.filename)
            if mirror == nil, let all = URL(string: "https://www.moddb.com/downloads/start/\(fileID)/all") {
                startHTML = try await client.html(from: all)
                mirror = ModDBHTML.mirrorURL(in: startHTML, filename: file.filename.isEmpty ? nil : file.filename)
            }
            guard let mirror else {
                statusText = "ModDB returned no download mirror. Try again or download manually from the page."
                return
            }
            let label = file.filename.isEmpty ? file.title : file.filename
            let sizeHint = file.sizeText.isEmpty ? "" : " (\(file.sizeText))"
            statusText = "Downloading \(label)\(sizeHint)…"
            let tempName = file.filename.isEmpty ? "download.bin" : file.filename
            let tempFile = fm.temporaryDirectory.appendingPathComponent("qmoddb-\(UUID().uuidString)-\(tempName)")
            let staging = fm.temporaryDirectory.appendingPathComponent("qmoddb-unpack-\(UUID().uuidString)")
            // sprzątanie zarejestrowane PRZED pobraniem — przerwane pobranie też zostawia plik
            defer {
                try? fm.removeItem(at: tempFile)
                try? fm.removeItem(at: staging)
            }
            try await client.download(mirror, to: tempFile)

            statusText = "Unpacking \(label)…"
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
                statusText = "Unpacked to \(actual)/, but it can't be run as a mod (no pak/progs.dat/maps)."
            } else if let warn = mod.engineWarning {
                statusText = "Installed \(mod.title) → \(actual)/. \(warn)"
            } else {
                statusText = "Installed \(mod.title) → \(actual)/ — ready to run (Play or Launch)."
            }
        } catch {
            statusText = "Install failed for \(mod.slug): \(error.localizedDescription)"
        }
    }

    func play(_ mod: ModDBMod, launcher: LauncherModel, registry: InstallRegistry, map: String? = nil) {
        let dir = registry.entry(.moddb, mod.slug)?.gameDir ?? mod.slug
        guard launcher.canRun(gameDir: dir) else {
            statusText = "Directory \(launcher.actualGameDir(dir))/ doesn't look like a Quake mod — not launching."
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
