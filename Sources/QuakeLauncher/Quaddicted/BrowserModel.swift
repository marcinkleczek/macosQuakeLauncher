import SwiftUI

// MARK: - Quaddicted: model przeglądarki

@MainActor
final class BrowserModel: ObservableObject {
    @Published var packages: [MapPackage] = []
    @Published var searchText = ""
    @Published var onlyInstalled = false
    @Published var kindFilter: PackageKind = .all
    @Published var loading = false
    @Published var statusText = ""
    @Published var installing: Set<String> = []
    @Published var installedIDs: Set<String>
    @Published var packageMaps: [String: [String]]
    /// id paczki → moment instalacji (sekundy od 1970). Zapisywane od wersji z sierpnia 2026;
    /// wcześniejsze instalacje nie zostawiły po sobie żadnego znacznika czasu.
    @Published var installedDates: [String: Double]

    private let fm = FileManager.default
    private static let databaseURL = URL(string: "https://www.quaddicted.com/db/v2/")!

    init() {
        installedIDs = Set(UserDefaults.standard.stringArray(forKey: "installedPackages") ?? [])
        packageMaps = UserDefaults.standard.dictionary(forKey: "packageMaps") as? [String: [String]] ?? [:]
        installedDates = UserDefaults.standard.dictionary(forKey: "installedDates") as? [String: Double] ?? [:]
    }

    /// Dla paczek zainstalowanych przed wprowadzeniem znacznika czasu próbujemy odzyskać datę
    /// z katalogu, który launcher sam założył. Paczki rozpakowane do id1/maps albo do katalogu
    /// moda przepadają — ich pliki noszą daty z archiwum (bywa, że z 1996 roku).
    ///
    /// Katalog paczki nie mógł powstać przed katalogiem bazowym, który go zawiera. Wcześniejsza
    /// data znaczy, że katalog trafił tu kopiowaniem z zachowaniem metadanych (Finder, cp -p) —
    /// to nie jest instalacja i lepiej nie zgadywać, niż pokazać rok 2008.
    func backfillInstallDates(launcher: LauncherModel) {
        guard let base = launcher.baseDir,
              let baseCreated = try? base.resourceValues(forKeys: [.creationDateKey]).creationDate
        else { return }

        var recovered = 0
        for id in installedIDs where installedDates[id] == nil {
            let dir = base.appendingPathComponent(id)
            guard let created = try? dir.resourceValues(forKeys: [.creationDateKey]).creationDate,
                  created >= baseCreated
            else { continue }
            installedDates[id] = created.timeIntervalSince1970
            recovered += 1
        }
        guard recovered > 0 else { return }
        UserDefaults.standard.set(installedDates, forKey: "installedDates")
    }

    // MARK: Historia instalacji w katalogu gry

    private static let historyFilename = ".quakelauncher-installs.json"

    private func historyURL(_ launcher: LauncherModel) -> URL? {
        launcher.baseDir?.appendingPathComponent(Self.historyFilename)
    }

    /// Scala historię z dysku z tym, co wiemy z UserDefaults. Świadomie robimy sumę zbiorów,
    /// a nie nadpisanie: plik może pochodzić z innego komputera i znać instalacje, o których
    /// te preferencje nie wiedzą — i odwrotnie. Przy konflikcie dat wygrywa wcześniejsza,
    /// bo to ona jest bliższa faktycznemu momentowi pobrania.
    func loadInstallHistory(launcher: LauncherModel) {
        guard let url = historyURL(launcher),
              let data = try? Data(contentsOf: url),
              let history = try? JSONDecoder().decode(InstallHistory.self, from: data)
        else { return }

        var changed = false
        for (id, record) in history.installs {
            if installedIDs.insert(id).inserted { changed = true }
            if let stamp = record.date {
                if let known = installedDates[id] {
                    if stamp < known { installedDates[id] = stamp; changed = true }
                } else {
                    installedDates[id] = stamp
                    changed = true
                }
            }
            if let maps = record.maps, packageMaps[id] == nil {
                packageMaps[id] = maps
                changed = true
            }
        }
        guard changed else { return }
        UserDefaults.standard.set(Array(installedIDs), forKey: "installedPackages")
        UserDefaults.standard.set(installedDates, forKey: "installedDates")
        UserDefaults.standard.set(packageMaps, forKey: "packageMaps")
    }

    /// Zrzuca aktualny stan do pliku w katalogu gry. Wywoływane po instalacji i po scaleniu
    /// przy starcie, żeby daty odzyskane z katalogów też trafiły na dysk.
    func saveInstallHistory(launcher: LauncherModel) {
        guard let url = historyURL(launcher) else { return }
        var history = InstallHistory()
        for id in installedIDs {
            history.installs[id] = InstallRecord(date: installedDates[id], maps: packageMaps[id])
        }
        guard let data = try? JSONEncoder().encode(history) else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            statusText = "Nie udało się zapisać historii instalacji: \(error.localizedDescription)"
        }
    }

    /// Mapy paczki: najpierw <startmap> z bazy, potem .bsp znalezione przy instalacji.
    /// Małymi literami — pliki instalujemy znormalizowane, a na case-sensitive APFS
    /// "THISISTE" ≠ "thisiste.bsp".
    func availableMaps(_ pkg: MapPackage) -> [String] {
        var result = pkg.startmaps.map { $0.lowercased() }
        for name in packageMaps[pkg.id] ?? [] where !result.contains(name.lowercased()) {
            result.append(name.lowercased())
        }
        return result
    }

    private var cacheFile: URL {
        let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.marcinkleczek.quakelauncher")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("quaddicted_dbv2.html")
    }

    func filtered(launcher: LauncherModel) -> [MapPackage] {
        var result = packages
        if kindFilter != .all { result = result.filter { $0.kinds.contains(kindFilter) } }
        if !installedDates.isEmpty {
            for i in result.indices {
                if let stamp = installedDates[result[i].id] {
                    result[i].installedAt = Date(timeIntervalSince1970: stamp)
                }
            }
        }
        if onlyInstalled { result = result.filter { isInstalled($0, launcher: launcher) } }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(query) || $0.author.lowercased().contains(query)
                    || $0.id.lowercased().contains(query)
                    || $0.tags.contains { $0.lowercased().contains(query) }
            }
        }
        return result
    }

    func loadIfNeeded() async {
        guard packages.isEmpty, !loading else { return }
        await load(force: false)
    }

    func load(force: Bool) async {
        loading = true
        defer { loading = false }
        var data: Data?
        let cacheAge = (try? fm.attributesOfItem(atPath: cacheFile.path)[.modificationDate] as? Date)
            .map { Date().timeIntervalSince($0) } ?? .infinity
        if !force, cacheAge < 7 * 24 * 3600 {
            data = try? Data(contentsOf: cacheFile)
        }
        if data == nil {
            statusText = "Pobieram bazę Quaddicted…"
            do {
                let (fresh, response) = try await URLSession.shared.data(from: Self.databaseURL)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                try? fresh.write(to: cacheFile)
                data = fresh
            } catch {
                data = try? Data(contentsOf: cacheFile) // sieć padła — użyj starego cache, jeśli jest
                if data == nil {
                    statusText = "Nie udało się pobrać bazy: \(error.localizedDescription)"
                    return
                }
            }
        }
        guard let raw = data else { return }
        statusText = "Przetwarzam bazę…"
        let html = String(decoding: raw, as: UTF8.self)
        let parsed = await Task.detached(priority: .userInitiated) { QuaddictedIndex.parse(html) }.value
        packages = parsed
        statusText = "Baza Quaddicted: \(parsed.count) pozycji."
    }

    /// Uzupełnia rejestr o rzeczy, których dawniej nie zapisywaliśmy: wymagany mod bazowy
    /// (tag `mod=`) i katalog gry. Bez tego mapa dla Quotha startowała na czystym Quake'u,
    /// a okno „Pobrane" nie wiedziało, co uruchomić. Wywoływane po wczytaniu bazy — dopiero
    /// wtedy znamy tagi paczek.
    func backfillFromIndex(registry: InstallRegistry, launcher: LauncherModel) {
        guard !packages.isEmpty, let base = launcher.baseDir else { return }
        var touched = 0
        for pkg in packages {
            guard let entry = registry.entry(.quaddicted, pkg.id) else { continue }
            let needsMod = entry.requiresMod == nil && pkg.requiredMod != nil
            // Katalog gry ustalamy po tym, gdzie NAPRAWDĘ leżą pliki .bsp. Zgadywanie
            // z zipbasedir mijało się z rzeczywistością: mapa dla Arcane Dimensions
            // rozpakowuje się do ad/, a nie do katalogu o nazwie paczki.
            let known = entry.gameDir.map { launcher.actualGameDir($0) }
            let dirHasMaps = known.map {
                PackageFS.looksLikeGameDir(base.appendingPathComponent($0))
            } ?? false
            var resolved: String?
            if !dirHasMaps {
                let names = entry.maps.isEmpty ? availableMaps(pkg) : entry.maps
                let found = launcher.locateMaps(named: names,
                                                preferredGame: playGameDir(pkg, launcher: launcher))
                // katalog gry to ten dwa poziomy nad plikiem: <gra>/maps/<mapa>.bsp
                resolved = found.first
                    .map { $0.source.file.deletingLastPathComponent().deletingLastPathComponent() }
                    .map { $0.lastPathComponent }
            }
            // Dawny instalator nie zaglądał do paków, więc paczki z mapami tylko w pak0.pak
            // nie mają spisu map. Skanujemy wyłącznie katalog nazwany jak paczka — wspólny
            // katalog moda (quoth/, gadgets/) zawiera też mapy innych paczek.
            var maps: [String] = []
            if availableMaps(pkg).isEmpty, entry.maps.isEmpty,
               let dir = resolved ?? known, dir.lowercased() == pkg.id.lowercased() {
                maps = PackageFS.bspNames(in: base.appendingPathComponent(dir))
                if !maps.isEmpty { packageMaps[pkg.id] = maps }
            }
            guard needsMod || resolved != nil || !maps.isEmpty else { continue }
            registry.record(source: .quaddicted, slug: pkg.id,
                            title: entry.title.isEmpty ? pkg.title : entry.title,
                            gameDir: resolved, maps: maps, base: nil,
                            requiresMod: needsMod ? pkg.requiredMod : nil)
            touched += 1
        }
        if touched > 0 {
            registry.save(base: base)
            UserDefaults.standard.set(packageMaps, forKey: "packageMaps")
        }
    }

    // MARK: Instalacja

    /// Ścieżka instalacji względem katalogu bazowego wg <zipbasedir> z bazy Quaddicted
    /// (np. "id1/maps", "quoth", "" = sam katalog bazowy). nil = brak wpisu → własny katalog o nazwie id.
    func installRelPath(_ pkg: MapPackage) -> String? {
        let raw = pkg.zipbasedir.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        // małymi literami, spójnie z lowercaseNames() — inaczej powstałby katalog
        // typu „Quoth", którego rozpakowane pliki (już małymi) nie znajdą
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }

    /// Katalog gry (-game) potrzebny do uruchomienia paczki, o ile commandline go nie podaje.
    /// Zwracana nazwa jest już dopasowana do rzeczywistej pisowni katalogu na dysku.
    func playGameDir(_ pkg: MapPackage, launcher: LauncherModel) -> String? {
        let tokens = pkg.commandline.split(separator: " ").map(String.init)
        if let i = tokens.firstIndex(of: "-game"), i + 1 < tokens.count {
            return launcher.actualGameDir(tokens[i + 1])
        }
        if let rel = installRelPath(pkg) {
            if let top = rel.split(separator: "/").first.map(String.init), top != "id1" {
                return launcher.actualGameDir(top)
            }
            return nil // id1 albo korzeń — gra bez -game
        }
        return launcher.actualGameDir(pkg.id)
    }

    func isInstalled(_ pkg: MapPackage, launcher: LauncherModel) -> Bool {
        installedIDs.contains(pkg.id)
    }

    func install(_ pkgIn: MapPackage, launcher: LauncherModel, registry: InstallRegistry) async {
        guard let base = launcher.baseDir else {
            statusText = "Najpierw ustaw katalog Quake'a w oknie launchera."
            return
        }
        var pkg = pkgIn
        installing.insert(pkg.id)
        defer { installing.remove(pkg.id) }
        if !pkg.detailLoaded {
            await ensureDetail(pkg.id)
            guard let fresh = packages.first(where: { $0.id == pkg.id }), fresh.detailLoaded else {
                statusText = "Nie udało się pobrać szczegółów \(pkg.id) — spróbuj ponownie."
                return
            }
            pkg = fresh
        }
        statusText = "Pobieram \(pkg.filename.isEmpty ? pkg.id + ".zip" : pkg.filename)…"
        do {
            let zipURL = pkg.downloadURL ?? URL(string: "https://www.quaddicted.com/filebase/\(pkg.id).zip")!
            let (tempZip, response) = try await URLSession.shared.download(from: zipURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

            let staging = fm.temporaryDirectory.appendingPathComponent("qinstall-\(UUID().uuidString)")
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: staging) }

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-oq", tempZip.path, "-d", staging.path]
            try unzip.run()
            unzip.waitUntilExit()
            guard unzip.terminationStatus <= 1 else { throw URLError(.cannotDecodeContentData) } // 1 = tylko ostrzeżenia

            // stare paczki bywają WIELKIMI LITERAMI, a silnik szuka małych —
            // na case-sensitive woluminie (np. APFS Case-sensitive) to by nie działało
            lowercaseNames(in: staging)

            let rel = installRelPath(pkg)
            var root = staging
            if rel == nil {
                // Fallback bez zipbasedir. Tylko tutaj wolno zejść przez katalog-otoczkę —
                // przy zipbasedir "/" zip celowo zawiera własny katalog gry i trzeba go zachować.
                while true {
                    let entries = (try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]))
                        .filter { $0.lastPathComponent.lowercased() != "__macosx" }
                    if entries.count == 1,
                       (try? entries[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        root = entries[0]
                    } else { break }
                }
                // luźne .bsp/.lit w korzeniu paczki → maps/
                let rootEntries = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                if rootEntries.contains(where: { $0.pathExtension.lowercased() == "bsp" }) {
                    let mapsDir = root.appendingPathComponent("maps")
                    try fm.createDirectory(at: mapsDir, withIntermediateDirectories: true)
                    for f in rootEntries where ["bsp", "lit"].contains(f.pathExtension.lowercased()) {
                        try fm.moveItem(at: f, to: mapsDir.appendingPathComponent(f.lastPathComponent))
                    }
                }
            }

            // spisz mapy paczki, żeby "Graj" działał także bez <startmap> w bazie
            let bspNames = PackageFS.bspNames(in: root)

            let target: URL
            if let rel, !rel.isEmpty {
                target = base.appendingPathComponent(rel)
            } else if rel != nil {
                target = base // zipbasedir "/" — zip zawiera pełne ścieżki katalogów gry
            } else {
                target = base.appendingPathComponent(pkg.id)
            }
            try mergeMove(from: root, to: target)

            installedIDs.insert(pkg.id)
            UserDefaults.standard.set(Array(installedIDs), forKey: "installedPackages")
            installedDates[pkg.id] = Date().timeIntervalSince1970
            UserDefaults.standard.set(installedDates, forKey: "installedDates")
            if !bspNames.isEmpty {
                packageMaps[pkg.id] = bspNames.sorted()
                UserDefaults.standard.set(packageMaps, forKey: "packageMaps")
            }
            saveInstallHistory(launcher: launcher)
            registry.record(source: .quaddicted, slug: pkg.id, title: pkg.title,
                            gameDir: playGameDir(pkg, launcher: launcher),
                            maps: bspNames.map { $0.lowercased() }, base: base,
                            requiresMod: pkg.requiredMod)
            launcher.rescan()
            let where_ = installRelPath(pkg).map { $0.isEmpty ? "katalog bazowy" : "\($0)/" } ?? "\(pkg.id)/"
            statusText = "Zainstalowano \(pkg.title.isEmpty ? pkg.id : pkg.title) → \(where_)"
        } catch {
            statusText = "Błąd instalacji \(pkg.id): \(error.localizedDescription)"
        }
    }

    /// Rekurencyjnie zmienia nazwy plików i katalogów na małe litery.
    private func lowercaseNames(in dir: URL) {
        for item in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
            var current = item
            let lower = item.lastPathComponent.lowercased()
            if lower != item.lastPathComponent {
                let dest = dir.appendingPathComponent(lower)
                if (try? fm.moveItem(at: item, to: dest)) != nil { current = dest }
            }
            if (try? current.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                lowercaseNames(in: current)
            }
        }
    }

    private func mergeMove(from src: URL, to dst: URL) throws {
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        for item in try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: [.isDirectoryKey]) {
            let dest = dst.appendingPathComponent(item.lastPathComponent)
            let itemIsDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            var destIsDir: ObjCBool = false
            if itemIsDir, fm.fileExists(atPath: dest.path, isDirectory: &destIsDir), destIsDir.boolValue {
                try mergeMove(from: item, to: dest)
            } else {
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.moveItem(at: item, to: dest)
            }
        }
    }

    // MARK: Szczegóły paczki (API v1) i zrzuty ekranu

    private var detailFailures: Set<String> = []

    /// Dociąga opis, instrukcję instalacji, commandline, startmapy i zależności z /api/v1.
    func ensureDetail(_ id: String) async {
        guard let idx = packages.firstIndex(where: { $0.id == id }), !packages[idx].detailLoaded else { return }
        let sha = packages[idx].sha256
        guard let url = URL(string: "https://www.quaddicted.com/api/v1/?q=%2Bsha256:\(sha)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let api = (try? JSONDecoder().decode([APIPackage].self, from: data))?.first
        else {
            if detailFailures.insert(id).inserted {
                statusText = "Nie udało się pobrać szczegółów \(id)."
            }
            return
        }
        var pkg = packages[idx]
        pkg.descriptionText = QuaddictedIndex.stripTags(api.description ?? "")
        if let bytes = api.bytes { pkg.sizeKB = bytes / 1024 }
        if let extract = api.install?["extract"] {
            let rel = extract.replacingOccurrences(of: "{base}", with: "")
            pkg.zipbasedir = rel.isEmpty ? "/" : rel
        }
        for tag in api.tags ?? [] {
            // część tagów mamy już z indeksu — nie dublujemy
            guard let eq = tag.firstIndex(of: "=") else {
                if !pkg.tags.contains(tag) { pkg.tags.append(tag) }
                continue
            }
            let key = String(tag[..<eq])
            let value = String(tag[tag.index(after: eq)...])
            switch key {
            case "commandline": pkg.commandline = value
            case "startmap": pkg.startmaps.append(value)
            case "dependency": pkg.requirements.append(value)
            case "zipbasedir": if pkg.zipbasedir.isEmpty { pkg.zipbasedir = value }
            case "title", "filename", "author", "release_date": break
            default: if !pkg.tags.contains(tag) { pkg.tags.append(tag) }
            }
        }
        pkg.downloadURL = (api.urls ?? []).compactMap { URL(string: $0) }.first
        pkg.detailLoaded = true
        packages[idx] = pkg
    }

    /// Obrazy żyją w repo GitHub adresowanym sha256 paczki; stary zrzut nazywa się <id>.jpg.
    func screenshotURL(for pkg: MapPackage) -> URL? {
        guard pkg.sha256.count == 64 else { return nil }
        return URL(string: "https://raw.githubusercontent.com/Quaddicted/quaddicted-images/main/by-sha256/\(pkg.sha256.prefix(2))/\(pkg.sha256)/\(pkg.id).jpg")
    }

    // MARK: Uruchamianie

    func play(_ pkg: MapPackage, launcher: LauncherModel, map: String? = nil) {
        guard let exec = launcher.selectedEngine?.execURL, let base = launcher.baseDir else {
            statusText = "Ustaw silnik i katalog w oknie launchera."
            return
        }
        var args = ["-basedir", base.path]
        var tokens = pkg.commandline.split(separator: " ").map(String.init)
        let gameDirForPkg = playGameDir(pkg, launcher: launcher)
        // commandline z bazy niesie pisownię autora paczki — podmieniamy na tę z dysku
        if let i = tokens.firstIndex(of: "-game"), i + 1 < tokens.count {
            tokens[i + 1] = launcher.actualGameDir(tokens[i + 1])
        }
        args += tokens
        if !tokens.contains("-game"), let game = gameDirForPkg {
            args += ["-game", game]
        }
        // ustawienia z okna launchera (commandline paczki ma pierwszeństwo)
        if !tokens.contains("-fullscreen"), !tokens.contains("-window") {
            args += [launcher.fullscreen ? "-fullscreen" : "-window"]
        }
        if launcher.skill >= 0, !tokens.contains("+skill") {
            args += ["+skill", String(launcher.skill)]
        }
        if let map = map ?? availableMaps(pkg).first { args += ["+map", map] }
        let process = Process()
        process.executableURL = exec
        process.arguments = args
        process.currentDirectoryURL = base
        if let env = launcher.gameEnvironment() { process.environment = env }
        do {
            try process.run()
            statusText = "Uruchomiono: \(args.joined(separator: " "))"
        } catch {
            statusText = "Błąd uruchamiania: \(error.localizedDescription)"
        }
    }
}
