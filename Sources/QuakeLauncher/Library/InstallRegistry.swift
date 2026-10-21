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
    /// Mod bazowy, na którym stoi ta paczka (tag `mod=` z Quaddicted: quoth, copper,
    /// arcanedimensions). Bez niego mapa startuje bez potrzebnych progs.dat i modeli.
    var requiresMod: String?

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
                gameDir: String?, maps: [String], base: URL?,
                requiresMod: String? = nil, at date: Date = Date()) {
        let key = "\(source.rawValue):\(slug)"
        var entry = entries[key] ?? InstallEntry(source: source, slug: slug, date: date.timeIntervalSince1970)
        if entry.date == nil { entry.date = date.timeIntervalSince1970 }
        if !title.isEmpty { entry.title = title }
        if let gameDir { entry.gameDir = gameDir }
        if !maps.isEmpty { entry.maps = maps }
        if let requiresMod, !requiresMod.isEmpty { entry.requiresMod = requiresMod }
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
            if current.requiresMod == nil { current.requiresMod = incoming.requiresMod }
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
