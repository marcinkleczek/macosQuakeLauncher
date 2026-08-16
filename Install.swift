import Foundation

// MARK: - Wspólna biblioteka pobranych rzeczy
//
// Do niedawna każde źródło (Quaddicted, ModDB) prowadziło własny rejestr w UserDefaults
// i własny plik na dysku, a kod rozpakowywania był kopiowany między nimi. Przy trzecim
// źródle (SlipSeer) rozjazd byłby nieunikniony — zwłaszcza że w tej właśnie logice siedział
// błąd z wielkością liter w nazwie katalogu gry. Stąd jeden rejestr i jeden zestaw narzędzi.

enum InstallSource: String, Codable, CaseIterable, Identifiable {
    case quaddicted, moddb, slipseer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quaddicted: return "Quaddicted"
        case .moddb: return "ModDB"
        case .slipseer: return "SlipSeer"
        }
    }
}

struct InstallEntry: Codable, Identifiable, Hashable {
    var source: InstallSource
    var slug: String
    var title = ""
    /// Sekundy od 1970. nil dla instalacji sprzed wprowadzenia znacznika — takich dat
    /// nie da się już odtworzyć i lepiej pokazać puste pole niż zmyśloną datę.
    var date: Double?
    var gameDir: String?
    var maps: [String] = []

    var id: String { "\(source.rawValue):\(slug)" }

    var installedAt: Date? { date.map { Date(timeIntervalSince1970: $0) } }
    var sortDate: Date { installedAt ?? .distantPast }

    var dateText: String {
        guard let installedAt else { return "—" }
        return Self.day.string(from: installedAt)
    }

    var displayTitle: String { title.isEmpty ? slug : title }

    private static let day: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
}

private struct LibraryFile: Codable {
    var version = 2
    var entries: [String: InstallEntry] = [:]
}

@MainActor
final class InstallRegistry: ObservableObject {
    @Published private(set) var entries: [String: InstallEntry] = [:]

    private let fm = FileManager.default
    private static let filename = ".quakelauncher-library.json"
    /// Pliki poprzednich wersji — czytamy je przy migracji, ale już nie zapisujemy.
    private static let legacyQuaddicted = ".quakelauncher-installs.json"
    private static let legacyModDB = ".quakelauncher-moddb.json"

    func entry(_ source: InstallSource, _ slug: String) -> InstallEntry? {
        entries["\(source.rawValue):\(slug)"]
    }

    func isInstalled(_ source: InstallSource, _ slug: String) -> Bool {
        entry(source, slug) != nil
    }

    func all(source: InstallSource? = nil) -> [InstallEntry] {
        let list = Array(entries.values)
        guard let source else { return list }
        return list.filter { $0.source == source }
    }

    /// Zapisuje fakt instalacji. Datę ustawiamy tylko przy pierwszym wpisie, żeby ponowne
    /// pobranie tej samej rzeczy nie skasowało informacji, kiedy pojawiła się u nas pierwotnie.
    func record(source: InstallSource, slug: String, title: String,
                gameDir: String?, maps: [String], base: URL?, at date: Date = Date()) {
        let key = "\(source.rawValue):\(slug)"
        var entry = entries[key] ?? InstallEntry(source: source, slug: slug, date: date.timeIntervalSince1970)
        if entry.date == nil { entry.date = date.timeIntervalSince1970 }
        if !title.isEmpty { entry.title = title }
        if let gameDir { entry.gameDir = gameDir }
        if !maps.isEmpty { entry.maps = maps }
        entries[key] = entry
        save(base: base)
    }

    func forget(_ source: InstallSource, _ slug: String, base: URL?) {
        entries.removeValue(forKey: "\(source.rawValue):\(slug)")
        save(base: base)
    }

    // MARK: Trwałość

    private func fileURL(_ base: URL?) -> URL? {
        base?.appendingPathComponent(Self.filename)
    }

    /// Scala zawartość dysku z tym, co już mamy. Suma zbiorów, nie nadpisanie: plik może
    /// pochodzić z innego komputera i znać instalacje, o których ta kopia nie wie.
    /// Przy konflikcie dat wygrywa wcześniejsza — bliższa faktycznemu pobraniu.
    func load(base: URL?) {
        guard let url = fileURL(base),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(LibraryFile.self, from: data)
        else { return }
        for (key, incoming) in file.entries {
            guard var current = entries[key] else { entries[key] = incoming; continue }
            if let d = incoming.date, current.date == nil || d < current.date! { current.date = d }
            if current.title.isEmpty { current.title = incoming.title }
            if current.gameDir == nil { current.gameDir = incoming.gameDir }
            if current.maps.isEmpty { current.maps = incoming.maps }
            entries[key] = current
        }
    }

    func save(base: URL?) {
        guard let url = fileURL(base) else { return }
        let file = LibraryFile(entries: entries)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Migracja ze starych rejestrów

    private var migrationDone: Bool {
        get { UserDefaults.standard.bool(forKey: "libraryMigrated.v2") }
        set { UserDefaults.standard.set(newValue, forKey: "libraryMigrated.v2") }
    }

    /// Przenosi dane z trzech dawnych miejsc: kluczy UserDefaults obu przeglądarek oraz
    /// plików .quakelauncher-installs.json i .quakelauncher-moddb.json. Stare źródła zostają
    /// nietknięte — gdyby migracja okazała się błędna, nic nie przepada.
    func migrateIfNeeded(base: URL?) {
        load(base: base)
        guard !migrationDone else { return }

        let defaults = UserDefaults.standard
        let quaddictedIDs = defaults.stringArray(forKey: "installedPackages") ?? []
        let quaddictedDates = defaults.dictionary(forKey: "installedDates") as? [String: Double] ?? [:]
        let quaddictedMaps = defaults.dictionary(forKey: "packageMaps") as? [String: [String]] ?? [:]
        for id in quaddictedIDs {
            merge(InstallEntry(source: .quaddicted, slug: id, date: quaddictedDates[id],
                               maps: quaddictedMaps[id] ?? []))
        }

        let moddbIDs = defaults.stringArray(forKey: "moddbInstalled") ?? []
        let moddbDates = defaults.dictionary(forKey: "moddbInstalledDates") as? [String: Double] ?? [:]
        let moddbDirs = defaults.dictionary(forKey: "moddbGameDirs") as? [String: String] ?? [:]
        let moddbMaps = defaults.dictionary(forKey: "moddbMaps") as? [String: [String]] ?? [:]
        for id in moddbIDs {
            merge(InstallEntry(source: .moddb, slug: id, date: moddbDates[id],
                               gameDir: moddbDirs[id], maps: moddbMaps[id] ?? []))
        }

        migrateLegacyFile(base, Self.legacyQuaddicted, source: .quaddicted)
        migrateLegacyFile(base, Self.legacyModDB, source: .moddb)

        migrationDone = true
        save(base: base)
    }

    private func migrateLegacyFile(_ base: URL?, _ name: String, source: InstallSource) {
        guard let url = base?.appendingPathComponent(name),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let installs = json["installs"] as? [String: [String: Any]]
        else { return }
        for (slug, record) in installs {
            merge(InstallEntry(source: source,
                               slug: slug,
                               date: record["date"] as? Double,
                               gameDir: record["gameDir"] as? String,
                               maps: record["maps"] as? [String] ?? []))
        }
    }

    private func merge(_ incoming: InstallEntry) {
        guard var current = entries[incoming.id] else { entries[incoming.id] = incoming; return }
        if let d = incoming.date, current.date == nil || d < current.date! { current.date = d }
        if current.title.isEmpty { current.title = incoming.title }
        if current.gameDir == nil { current.gameDir = incoming.gameDir }
        if current.maps.isEmpty { current.maps = incoming.maps }
        entries[incoming.id] = current
    }
}

// MARK: - Operacje na plikach paczek
//
// Jeden komplet zamiast kopii w każdej przeglądarce.

enum PackageFS {
    static let fm = FileManager.default

    /// Czy katalog wygląda na katalog gry (dane moda), a nie na pustą skorupę po samym configu.
    static func looksLikeGameDir(_ url: URL) -> Bool {
        let contents = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
        return contents.contains { entry in
            let name = entry.lowercased()
            return name.hasSuffix(".pak") || name.hasSuffix(".pk3") || name == "progs.dat" || name == "maps"
        }
    }

    /// Rekurencyjnie zmienia nazwy plików i katalogów na małe litery. Na case-sensitive APFS
    /// silnik nie znajdzie THISISTE.BSP, gdy szuka thisiste.bsp.
    static func lowercaseNames(in dir: URL) {
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

    static func mergeMove(from src: URL, to dst: URL) throws {
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

    static func usefulEntries(_ dir: URL) -> [URL] {
        ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { url in
                let n = url.lastPathComponent.lowercased()
                return n != "__macosx" && n != ".ds_store" && !n.hasPrefix(".nested-")
            }
    }

    /// Luźne .bsp w korzeniu paczki trafiają do maps/, bo tam ich szuka silnik.
    static func hoistLooseMaps(in root: URL) {
        let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        guard entries.contains(where: { $0.pathExtension.lowercased() == "bsp" }) else { return }
        let mapsDir = root.appendingPathComponent("maps")
        try? fm.createDirectory(at: mapsDir, withIntermediateDirectories: true)
        for f in entries where ["bsp", "lit"].contains(f.pathExtension.lowercased()) {
            try? fm.moveItem(at: f, to: mapsDir.appendingPathComponent(f.lastPathComponent))
        }
    }

    /// Zdejmuje otoczki (katalog z jedną rzeczą w środku), ale zatrzymuje się na katalogu,
    /// w którym już są dane gry — jego nazwa bywa istotna dla silnika.
    static func unwrapWrappers(_ staging: URL) -> URL {
        var root = staging
        while true {
            let entries = usefulEntries(root)
            if entries.count == 1,
               (try? entries[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
               !looksLikeGameDir(entries[0]) {
                root = entries[0]
            } else { break }
        }
        return root
    }

    static func bspNames(in dir: URL) -> [String] {
        var names: [String] = []
        guard let walker = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        for case let f as URL in walker.allObjects where f.pathExtension.lowercased() == "bsp" {
            let name = f.deletingPathExtension().lastPathComponent.lowercased()
            if !name.hasPrefix("b_") { names.append(name) }
        }
        return names.sorted()
    }

    // MARK: Archiwa

    enum ArchiveKind { case zip, tar, gzip, rar, sevenZ, pak, unknown }

    static func sniff(_ url: URL) -> ArchiveKind {
        if let fh = try? FileHandle(forReadingFrom: url) {
            defer { try? fh.close() }
            if let head = try? fh.read(upToCount: 8), head.count >= 4 {
                let b = [UInt8](head)
                if b[0] == 0x50, b[1] == 0x4B { return .zip } // PK
                if b[0] == 0x52, b[1] == 0x61, b[2] == 0x72, b[3] == 0x21 { return .rar }
                if b[0] == 0x37, b[1] == 0x7A, b[2] == 0xBC, b[3] == 0xAF { return .sevenZ }
                if b[0] == 0x1F, b[1] == 0x8B { return .gzip }
                if head.prefix(4) == Data("PACK".utf8) { return .pak }
                if head.prefix(5) == Data("ustar".utf8) { return .tar }
            }
        }
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar") { return .tar }
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { return .gzip }
        if name.hasSuffix(".zip") || name.hasSuffix(".pk3") { return .zip }
        if name.hasSuffix(".rar") { return .rar }
        if name.hasSuffix(".7z") { return .sevenZ }
        if name.hasSuffix(".pak") { return .pak }
        return .unknown
    }

    static func extract(_ archive: URL, to dest: URL) throws {
        switch sniff(archive) {
        case .pak:
            try fm.copyItem(at: archive, to: dest.appendingPathComponent(archive.lastPathComponent.lowercased()))
        case .zip:
            try run("/usr/bin/unzip", ["-oq", archive.path, "-d", dest.path], okUpTo: 1)
        case .tar:
            try run("/usr/bin/tar", ["-xf", archive.path, "-C", dest.path], okUpTo: 0)
        case .gzip:
            if archive.lastPathComponent.lowercased().contains(".tar") {
                try run("/usr/bin/tar", ["-xzf", archive.path, "-C", dest.path], okUpTo: 0)
            } else {
                try unarExtract(archive, to: dest)
            }
        case .rar, .sevenZ:
            try unarExtract(archive, to: dest)
        case .unknown:
            if (try? run("/usr/bin/unzip", ["-oq", archive.path, "-d", dest.path], okUpTo: 1)) == nil {
                try unarExtract(archive, to: dest)
            }
        }
    }

    private static func unarExtract(_ archive: URL, to dest: URL) throws {
        let unar = ["/opt/homebrew/bin/unar", "/usr/local/bin/unar", "/usr/bin/unar"].first {
            fm.isExecutableFile(atPath: $0)
        }
        guard let unar else {
            throw NSError(domain: "PackageFS", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Nie umiem rozpakować \(archive.lastPathComponent) (brak unar). Potrzebny ZIP albo The Unarchiver CLI.",
            ])
        }
        try run(unar, ["-o", dest.path, "-f", archive.path], okUpTo: 0)
    }

    /// Zip w zipie albo pojedyncze archiwum obok readme — typowe na ModDB i SlipSeer.
    static func peelNestedArchives(in dir: URL, depth: Int = 0) throws {
        guard depth < 3 else { return }
        lowercaseNames(in: dir)
        let entries = usefulEntries(dir)
        guard entries.count == 1, sniff(entries[0]) != .unknown, sniff(entries[0]) != .pak else { return }
        let inner = dir.appendingPathComponent(".nested-\(depth)")
        try fm.createDirectory(at: inner, withIntermediateDirectories: true)
        try extract(entries[0], to: inner)
        try? fm.removeItem(at: entries[0])
        lowercaseNames(in: inner)
        try peelNestedArchives(in: inner, depth: depth + 1)
        try mergeMove(from: inner, to: dir)
        try? fm.removeItem(at: inner)
    }

    /// Umieszcza rozpakowaną zawartość w katalogu gry i zwraca jego nazwę.
    /// Katalog gry (ad/, quoth/) zachowuje własną nazwę — silnik i mapy często tego wymagają.
    static func placeGameDir(from staging: URL, fallbackName: String, base: URL) throws -> String {
        let work = unwrapWrappers(staging)
        hoistLooseMaps(in: work)

        if looksLikeGameDir(work), work != staging {
            let name = work.lastPathComponent
            try mergeMove(from: work, to: base.appendingPathComponent(name))
            return name
        }
        let gameKids = usefulEntries(work).filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && looksLikeGameDir($0)
        }
        if gameKids.count == 1 {
            let name = gameKids[0].lastPathComponent
            try mergeMove(from: gameKids[0], to: base.appendingPathComponent(name))
            return name
        }
        let targetName = fallbackName.lowercased()
        try mergeMove(from: work, to: base.appendingPathComponent(targetName))
        return targetName
    }

    static func run(_ exe: String, _ args: [String], okUpTo: Int32) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus <= okUpTo else {
            throw NSError(domain: "PackageFS", code: Int(p.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "\(exe) zakończył się kodem \(p.terminationStatus)",
            ])
        }
    }
}
