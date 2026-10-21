import SwiftUI

// MARK: - Silnik

struct Engine: Identifiable, Hashable {
    let name: String
    let appURL: URL // bundle .app albo goła binarka

    var id: String { appURL.path }

    var execURL: URL? {
        if appURL.pathExtension == "app" {
            return Bundle(url: appURL)?.executableURL
        }
        return appURL
    }
}

// MARK: - Monitor

struct DisplayOption: Identifiable, Hashable {
    let name: String
    let position: CGPoint // globalne współrzędne CG wewnątrz danego ekranu

    var id: String { "\(name)@\(Int(position.x)),\(Int(position.y))" }
}

// MARK: - Model

final class LauncherModel: ObservableObject {
    @Published var baseDir: URL?
    @Published var engines: [Engine] = []
    @Published var mods: [String] = []
    @Published var maps: [String] = []

    @Published var displays: [DisplayOption] = []
    @Published var selectedDisplay: DisplayOption? { didSet { defaults.set(selectedDisplay?.name, forKey: "display") } }
    @Published var selectedEngine: Engine? { didSet { defaults.set(selectedEngine?.appURL.path, forKey: "engine") } }
    @Published var selectedMod = "id1" { didSet { defaults.set(selectedMod, forKey: "mod"); scanMaps() } }
    @Published var selectedMap = "" { didSet { defaults.set(selectedMap, forKey: "map") } }
    @Published var fullscreen = true { didSet { defaults.set(fullscreen, forKey: "fullscreen") } }
    @Published var skill = -1 { didSet { defaults.set(skill, forKey: "skill") } }
    @Published var params = "" { didSet { defaults.set(params, forKey: "params") } }
    @Published var status = ""

    private let defaults = UserDefaults.standard
    private let fm = FileManager.default

    init() {
        if let path = defaults.string(forKey: "baseDir") {
            baseDir = URL(fileURLWithPath: path)
        }
        selectedMod = defaults.string(forKey: "mod") ?? "id1"
        selectedMap = defaults.string(forKey: "map") ?? ""
        fullscreen = defaults.object(forKey: "fullscreen") as? Bool ?? true
        skill = defaults.object(forKey: "skill") as? Int ?? -1
        params = defaults.string(forKey: "params") ?? ""
        rescan()
    }

    func setBaseDir(_ url: URL) {
        baseDir = url
        defaults.set(url.path, forKey: "baseDir")
        rescan()
    }

    func rescan() {
        scanEngines()
        scanMods()
        scanMaps()
        scanDisplays()
    }

    // MARK: Monitory

    private func scanDisplays() {
        displays = NSScreen.screens.map { screen in
            let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let bounds = CGDisplayBounds(CGDirectDisplayID(number))
            // punkt wyraźnie wewnątrz ekranu — SDL umieści tam okno, a fullscreen pójdzie na ten monitor
            return DisplayOption(name: screen.localizedName,
                                 position: CGPoint(x: bounds.origin.x + 120, y: bounds.origin.y + 120))
        }
        let saved = defaults.string(forKey: "display")
        selectedDisplay = displays.first { $0.name == saved }
    }

    /// Środowisko procesu gry: przy wybranym monitorze wstrzykuje shim ustawiający pozycję okna SDL.
    func gameEnvironment() -> [String: String]? {
        guard let display = selectedDisplay,
              let shim = Bundle.main.url(forResource: "libdisplayshim", withExtension: "dylib")?.path
        else { return nil }
        var env = ProcessInfo.processInfo.environment
        env["DYLD_INSERT_LIBRARIES"] = shim
        env["QL_WINDOW_POS"] = "\(Int(display.position.x)),\(Int(display.position.y))"
        return env
    }

    // MARK: Skan silników

    private func scanEngines() {
        var found: [Engine] = []
        let pattern = try! NSRegularExpression(pattern: "quake|spasm|ironwail|darkplaces|fte", options: .caseInsensitive)
        for root in ["/Applications", NSHomeDirectory() + "/Applications"] {
            guard let level1 = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in level1 {
                let url = URL(fileURLWithPath: root).appendingPathComponent(entry)
                if url.pathExtension == "app" {
                    if matches(pattern, entry) { found.append(Engine(name: appName(url), appURL: url)) }
                } else if var isDir = ObjCBool(false) as ObjCBool?, fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    // jeden poziom w głąb, np. /Applications/QuakeSpasm/QuakeSpasm-SDL2.app
                    for sub in (try? fm.contentsOfDirectory(atPath: url.path)) ?? [] where sub.hasSuffix(".app") {
                        if matches(pattern, sub) { found.append(Engine(name: appName(url.appendingPathComponent(sub)), appURL: url.appendingPathComponent(sub))) }
                    }
                }
            }
        }
        for path in defaults.stringArray(forKey: "customEngines") ?? [] where fm.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            found.append(Engine(name: appName(url), appURL: url))
        }
        engines = found.sorted { $0.name < $1.name }
        let savedPath = defaults.string(forKey: "engine")
        selectedEngine = engines.first { $0.appURL.path == savedPath } ?? engines.first
    }

    func addCustomEngine(_ url: URL) {
        var custom = defaults.stringArray(forKey: "customEngines") ?? []
        if !custom.contains(url.path) { custom.append(url.path) }
        defaults.set(custom, forKey: "customEngines")
        scanEngines()
        selectedEngine = engines.first { $0.appURL.path == url.path }
    }

    private func matches(_ regex: NSRegularExpression, _ s: String) -> Bool {
        regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private func appName(_ url: URL) -> String { url.deletingPathExtension().lastPathComponent }

    // MARK: Skan modów

    private func scanMods() {
        guard let base = baseDir,
              let entries = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        else { mods = []; return }

        var found: [String] = []
        for dir in entries where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let name = dir.lastPathComponent
            if name == "id1" { continue }
            if looksLikeGameDir(dir) { found.append(name) }
        }
        mods = ["id1"] + found.sorted()
        if !mods.contains(selectedMod) { selectedMod = "id1" }
    }

    // MARK: Skan map (luźne .bsp + wnętrza .pak)

    private func scanMaps() {
        guard let base = baseDir else { maps = []; return }
        var found = mapsInGameDir(base.appendingPathComponent(selectedMod))
        if found.isEmpty, selectedMod != "id1" {
            found = mapsInGameDir(base.appendingPathComponent("id1"))
        }
        maps = found.keys.sorted()
        if !selectedMap.isEmpty, !maps.contains(selectedMap) { selectedMap = "" }
    }

    /// Dopasowuje nazwę katalogu gry do tego, co faktycznie leży na dysku.
    /// Quaddicted podaje commandline z oryginalną pisownią (np. „-game Maelstrm"), a instalator
    /// normalizuje rozpakowane nazwy do małych liter. Na case-sensitive APFS silnik nie znajduje
    /// wtedy katalogu i zakłada nowy, pusty — mod milcząco się nie ładuje. Ręcznie skopiowane
    /// katalogi bywają z kolei zapisane wielkimi literami, więc nie wolno po prostu
    /// zamieniać nazwy na małe: trzeba sprawdzić, jak brzmi naprawdę.
    func actualGameDir(_ name: String) -> String {
        guard let base = baseDir, !name.isEmpty else { return name }
        let entries = (try? fm.contentsOfDirectory(atPath: base.path)) ?? []
        let candidates = entries.filter { $0.lowercased() == name.lowercased() }
        guard candidates.count != 1 else { return candidates[0] }
        guard !candidates.isEmpty else { return name }
        // Kilka katalogów różniących się tylko wielkością liter to ślad po tym właśnie błędzie:
        // silnik uruchomiony ze złą pisownią zakłada pusty katalog i zapisuje w nim config.
        // Wybieramy ten z prawdziwą zawartością, żeby śmieć nie przykrywał danych.
        return candidates.first { looksLikeGameDir(base.appendingPathComponent($0)) } ?? candidates[0]
    }

    /// Czy katalog wygląda na katalog gry (dane moda), a nie na pustą skorupę po samym configu.
    private func looksLikeGameDir(_ url: URL) -> Bool {
        let contents = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
        return contents.contains { entry in
            let name = entry.lowercased()
            return name.hasSuffix(".pak") || name.hasSuffix(".pk3") || name == "progs.dat" || name == "maps"
        }
    }

    /// Uruchamia grę w podanym katalogu gry. Jedno miejsce dla wszystkich źródeł —
    /// nazwa katalogu jest po drodze prostowana do rzeczywistej pisowni na dysku,
    /// a mission packi dostają swoje flagi zamiast -game.
    func runGame(gameDir: String?, map: String? = nil, extraArgs: [String] = []) {
        guard let exec = selectedEngine?.execURL, let base = baseDir else {
            status = "Set the engine and Quake folder."
            return
        }
        var args = ["-basedir", base.path]
        // Świadomie JEDEN -game. Silnik przyjmuje ich wiele, ale progs.dat bierze
        // z ostatniego katalogu — mapa dla Quotha uruchomiona jako
        // „-game quoth -game mapa" ładowała się bez logiki moda (setki „no spawn
        // function"). Mapy dla modów i tak lądują w katalogu moda, więc wystarczy on sam.
        if let gameDir, !gameDir.isEmpty {
            let game = actualGameDir(gameDir)
            switch game.lowercased() {
            case "id1": break
            case "hipnotic": args += ["-hipnotic"]
            case "rogue": args += ["-rogue"]
            default: args += ["-game", game]
            }
        }
        args += extraArgs
        if !args.contains("-fullscreen"), !args.contains("-window") {
            args += [fullscreen ? "-fullscreen" : "-window"]
        }
        if skill >= 0, !args.contains("+skill") { args += ["+skill", String(skill)] }
        if let map, !map.isEmpty { args += ["+map", map] }

        let process = Process()
        process.executableURL = exec
        process.arguments = args
        process.currentDirectoryURL = base
        if let env = gameEnvironment() { process.environment = env }
        do {
            try process.run()
            status = "Launched: \(args.joined(separator: " "))"
        } catch {
            status = "Launch failed: \(error.localizedDescription)"
        }
    }

    /// Katalog moda bazowego wymaganego przez paczkę. Quaddicted tagują go nazwą z bazy,
    /// która nie zawsze odpowiada katalogowi na dysku — „arcanedimensions" leży w ad/,
    /// a Rubicon Rumble Pack w rubicon2/. Zwracamy nil, gdy moda po prostu nie ma.
    func baseModDir(for tag: String) -> String? {
        guard let base = baseDir else { return nil }
        let candidates: [String]
        switch tag.lowercased() {
        case "arcanedimensions", "ad": candidates = ["ad", "arcanedimensions"]
        case "rubicon": candidates = ["rubicon2", "rubicon"]
        case "progs_dump", "progsdump": candidates = ["progs_dump", "dump"]
        default: candidates = [tag]
        }
        for candidate in candidates {
            let actual = actualGameDir(candidate)
            if PackageFS.looksLikeGameDir(base.appendingPathComponent(actual)) { return actual }
        }
        return nil
    }

    /// Czy mod bazowy jest naprawdę zainstalowany, a nie reprezentowany przez sam katalog
    /// z mapami. Katalog w rodzaju ad/ powstaje przy rozpakowaniu mapy dla Arcane Dimensions,
    /// choć samego moda tam nie ma — Quaddicted nie hostuje dużych modów. Bez progs.dat albo
    /// paka silnik wystartuje mapę bez logiki dodatku (setki „no spawn function").
    func baseModInstalled(_ tag: String) -> Bool {
        guard let base = baseDir, let dir = baseModDir(for: tag) else { return false }
        let contents = (try? fm.contentsOfDirectory(atPath: base.appendingPathComponent(dir).path)) ?? []
        return contents.contains { entry in
            let name = entry.lowercased()
            return name == "progs.dat" || name.hasSuffix(".pak") || name.hasSuffix(".pk3")
        }
    }

    /// Czy w tym katalogu gry faktycznie da się coś odpalić.
    func canRun(gameDir: String?) -> Bool {
        guard let base = baseDir, let gameDir, !gameDir.isEmpty else { return false }
        return PackageFS.looksLikeGameDir(base.appendingPathComponent(actualGameDir(gameDir)))
    }

    /// Odnajduje pliki .bsp o podanych nazwach. Paczka trafia raz do własnego katalogu,
    /// raz do id1, a raz do katalogu moda (quoth, ad, copper) — więc gdy pierwsze
    /// typowanie zawiedzie, przeglądamy pozostałe katalogi gry.
    func locateMaps(named names: [String], preferredGame: String?) -> [InspectableMap] {
        guard baseDir != nil, !names.isEmpty else { return [] }
        var dirs = ["id1"]
        if let preferredGame, preferredGame != "id1" { dirs.insert(preferredGame, at: 0) }

        var result = match(names, in: dirs)
        if result.count < names.count {
            result = match(names, in: dirs + mods.filter { !dirs.contains($0) })
        }
        return result
    }

    /// Dla każdej nazwy pierwsze trafienie wg kolejności katalogów; wielkość liter bez znaczenia,
    /// bo instalator normalizuje nazwy do małych, a katalogi gry bywają zapisane inaczej.
    private func match(_ names: [String], in dirs: [String]) -> [InspectableMap] {
        guard let base = baseDir else { return [] }
        var byLowercase: [String: MapSource] = [:]
        for dir in dirs.reversed() { // wcześniejsze katalogi mają wygrać, więc idziemy od tyłu
            for (name, source) in mapsInGameDir(base.appendingPathComponent(dir)) {
                byLowercase[name.lowercased()] = source
            }
        }
        return names.compactMap { name in
            byLowercase[name.lowercased()].map { InspectableMap(name: name, source: $0) }
        }
    }

    /// Nazwa mapy → jej położenie. Kolejność wypełniania odwzorowuje priorytet silnika:
    /// późniejsze paki przykrywają wcześniejsze, a luźne pliki w maps/ przykrywają paki.
    private func mapsInGameDir(_ dir: URL) -> [String: MapSource] {
        var found: [String: MapSource] = [:]
        let paks = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.lowercased().hasSuffix(".pak") }
            .sorted()
        for pak in paks {
            let url = dir.appendingPathComponent(pak)
            for (entry, location) in BSPReader.pakEntries(url) {
                let lower = entry.lowercased()
                // b_*.bsp to modele przedmiotów (skrzynki amunicji), nie mapy
                guard lower.hasPrefix("maps/"), lower.hasSuffix(".bsp"),
                      !lower.dropFirst(5).contains("/"), !lower.hasPrefix("maps/b_") else { continue }
                found[String(entry.dropFirst(5).dropLast(4))] = MapSource(file: url, offset: UInt64(location.offset))
            }
        }
        let mapsDir = dir.appendingPathComponent("maps")
        for f in (try? fm.contentsOfDirectory(atPath: mapsDir.path)) ?? []
        where f.lowercased().hasSuffix(".bsp") && !f.lowercased().hasPrefix("b_") {
            found[String(f.dropLast(4))] = MapSource(file: mapsDir.appendingPathComponent(f), offset: 0)
        }
        return found
    }

    // MARK: Zawartość mapy (spoiler)

    /// Rozbiera mapę na czynniki pierwsze. Liczone dopiero na żądanie —
    /// dopóki użytkownik nie odsłoni panelu, nie ruszamy dysku.
    func inspect(_ source: MapSource) -> MapInfo? {
        guard let entities = BSPReader.entities(at: source) else { return nil }
        // -1 oznacza "nie podajemy +skill" — silnik startuje wtedy na Normal
        return MapAnalyzer.analyze(entities, skill: skill < 0 ? 1 : skill, skillWasExplicit: skill >= 0)
    }

    // MARK: Uruchomienie

    func launch() {
        guard let engine = selectedEngine, let exec = engine.execURL, let base = baseDir else {
            status = "No engine or Quake folder set."
            return
        }
        var args = ["-basedir", base.path]
        switch selectedMod {
        case "id1": break
        case "hipnotic": args += ["-hipnotic"] // mission packi mają dedykowane flagi
        case "rogue": args += ["-rogue"]       // (poprawny HUD i logika gry)
        default: args += ["-game", selectedMod]
        }
        args += [fullscreen ? "-fullscreen" : "-window"]
        if skill >= 0 { args += ["+skill", String(skill)] }
        args += params.split(separator: " ").map(String.init)
        if !selectedMap.isEmpty { args += ["+map", selectedMap] }

        let process = Process()
        process.executableURL = exec
        process.arguments = args
        process.currentDirectoryURL = base
        if let env = gameEnvironment() { process.environment = env }
        do {
            try process.run()
            status = "Launched: \(engine.name) \(args.joined(separator: " "))"
        } catch {
            status = "Launch failed: \(error.localizedDescription)"
        }
    }
}
