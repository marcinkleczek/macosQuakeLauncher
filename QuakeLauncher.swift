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
            status = "Ustaw silnik i katalog Quake'a."
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
            status = "Uruchomiono: \(args.joined(separator: " "))"
        } catch {
            status = "Błąd uruchamiania: \(error.localizedDescription)"
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
            status = "Brak silnika lub katalogu gry."
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
            status = "Uruchomiono: \(engine.name) \(args.joined(separator: " "))"
        } catch {
            status = "Błąd uruchamiania: \(error.localizedDescription)"
        }
    }
}

// MARK: - UI

struct ContentView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var registry: InstallRegistry
    @Environment(\.openWindow) private var openWindow

    static let modLabels = [
        "id1": "id1 (bez moda)",
        "hipnotic": "hipnotic (Scourge of Armagon)",
        "rogue": "rogue (Dissolution of Eternity)",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.baseDir == nil {
                setupView
            } else {
                launcherForm
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var setupView: some View {
        VStack(spacing: 12) {
            Text("Wskaż katalog Quake'a").font(.title2)
            Text("Katalog, w którym znajduje się podkatalog id1 (z pak0.pak) oraz katalogi modów.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Wybierz katalog…") { pickBaseDir() }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var launcherForm: some View {
        Group {
            Grid(alignment: .leading, verticalSpacing: 10) {
                GridRow {
                    Text("Silnik:")
                    HStack {
                        Picker("", selection: $model.selectedEngine) {
                            ForEach(model.engines) { engine in
                                Text(engine.name).tag(Optional(engine))
                            }
                        }
                        .labelsHidden()
                        Button("…") { pickEngine() }
                            .help("Dodaj inny silnik (aplikację lub binarkę)")
                    }
                }
                GridRow {
                    Text("Mod:")
                    Picker("", selection: $model.selectedMod) {
                        ForEach(model.mods, id: \.self) { mod in
                            Text(Self.modLabels[mod] ?? mod).tag(mod)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Mapa:")
                    Picker("", selection: $model.selectedMap) {
                        Text("(menu główne)").tag("")
                        ForEach(model.maps, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Monitor:")
                    Picker("", selection: $model.selectedDisplay) {
                        Text("Domyślny").tag(Optional<DisplayOption>.none)
                        ForEach(model.displays) { display in
                            Text(display.name).tag(Optional(display))
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("")
                    Toggle("Pełny ekran", isOn: $model.fullscreen)
                        .toggleStyle(.checkbox)
                }
                GridRow {
                    Text("Skill:")
                    Picker("", selection: $model.skill) {
                        Text("Domyślny").tag(-1)
                        Text("Easy").tag(0)
                        Text("Normal").tag(1)
                        Text("Hard").tag(2)
                        Text("Nightmare").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                GridRow {
                    Text("Parametry:")
                    TextField("np. -width 2560", text: $model.params)
                }
            }

            // Dwa rzędy: sześć przycisków w jednej linii nie mieściło się w oknie
            // o szerokości 420 i etykiety obcinały się do „Mapy onli…”.
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Pobieraj z:")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Quaddicted") { openWindow(id: "maps") }
                    Button("SlipSeer") { openWindow(id: "slipseer") }
                    Button("ModDB") { openWindow(id: "moddb") }
                    Spacer()
                    Button("Pobrane") { openWindow(id: "library") }
                        .help("Wszystko, co pobrałeś — ze wszystkich źródeł, z datami.")
                }

                HStack(spacing: 8) {
                    Button("Zmień katalog…") { pickBaseDir() }
                    Button("Odśwież") { model.rescan() }
                    Spacer()
                    Button("Launch ▶") { model.launch() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(model.selectedEngine == nil)
                }
            }

            if !model.status.isEmpty {
                Text(model.status)
                    .font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func pickBaseDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Wybierz katalog Quake'a (zawierający id1)"
        if panel.runModal() == .OK, let url = panel.url {
            model.setBaseDir(url)
        }
    }

    private func pickEngine() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.message = "Wybierz aplikację (.app) lub binarkę silnika Quake"
        if panel.runModal() == .OK, let url = panel.url {
            model.addCustomEngine(url)
        }
    }
}

// MARK: - Panel zawartości mapy
//
// Domyślnie zwinięty i zwijany z powrotem przy każdej zmianie mapy: kto gra po raz
// pierwszy, nie powinien przypadkiem zobaczyć, ile sekretów przegapił. Analiza pliku
// rusza dopiero po kliknięciu — dopóki panel jest zamknięty, nie czytamy dysku.

struct InspectableMap: Identifiable, Hashable {
    let name: String
    let source: MapSource

    var id: String { name }
}

struct MapSpoilerPanel: View {
    @ObservedObject var launcher: LauncherModel
    let mapNames: [String]
    let preferredGame: String?

    @State private var maps: [InspectableMap] = []
    @State private var selected: String = ""
    @State private var info: MapInfo?
    @State private var revealed = false
    @State private var failed = false

    private var current: InspectableMap? {
        maps.first { $0.name == selected } ?? maps.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                revealed.toggle()
                if revealed { reload() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: revealed ? "chevron.down" : "chevron.right")
                        .font(.caption.bold())
                        .frame(width: 10)
                    Image(systemName: revealed ? "eye" : "eye.slash")
                    Text(revealed ? "Zawartość mapy" : "Pokaż zawartość mapy (spoiler)")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Czyta listę encji z pliku .bsp — bronie, sekrety, przyciski, potwory.")

            if revealed {
                if maps.count > 1 {
                    Picker("", selection: $selected) {
                        ForEach(maps) { Text($0.name).tag($0.name) }
                    }
                    .labelsHidden()
                }
                if let info {
                    details(info)
                } else if failed {
                    Label(maps.isEmpty
                            ? "Nie znalazłem plików map tej paczki w katalogu gry."
                            : "Nie udało się odczytać tej mapy (nieznany format BSP).",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        // poziom trudności i wybór mapy decydują, co w ogóle powstanie — przelicz
        .task(id: "\(selected)|\(launcher.skill)") {
            if revealed { reload() }
        }
    }

    private func reload() {
        // wyszukanie plików rusza dopiero tutaj — panel zamknięty nie dotyka dysku
        if maps.isEmpty {
            maps = launcher.locateMaps(named: mapNames, preferredGame: preferredGame)
        }
        guard let map = current else { info = nil; failed = true; return }
        if selected.isEmpty { selected = map.name }
        info = launcher.inspect(map.source)
        failed = info == nil
    }

    @ViewBuilder private func details(_ info: MapInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if !info.title.isEmpty {
                    Text(info.title).font(.callout).bold()
                }
                Text(info.headline.joined(separator: " · ") + " · poziom: \(info.skillLabel)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // bez własnego ScrollView — panel siedzi w przewijanym widoku paczki
            VStack(alignment: .leading, spacing: 12) {
                ForEach(info.sections) { section in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(section.title.uppercased())
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        ForEach(section.items) { item in
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.label)
                                Spacer(minLength: 8)
                                Text(item.detail)
                                    .foregroundStyle(item.muted ? .tertiary : .primary)
                            }
                            .font(.callout)
                            .foregroundStyle(item.muted ? .secondary : .primary)
                        }
                        if let note = section.note {
                            Text(note).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .textSelection(.enabled)
    }
}

// MARK: - Quaddicted: dane

/// Rodzaj paczki w bazie Quaddicted (tag `type=`). Baza zawiera nie tylko mapy —
/// mody, epizody, jamy i speedmapy są w tym samym indeksie, tylko inaczej otagowane.
enum PackageKind: String, CaseIterable, Identifiable {
    case all, map, mod, episode, mapjam, speedmap

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Wszystko"
        case .map: return "Mapy"
        case .mod: return "Mody"
        case .episode: return "Epizody"
        case .mapjam: return "Jamy"
        case .speedmap: return "Speedmapy"
        }
    }

    /// Nazwa pojedynczej paczki tego rodzaju (do kolumny w tabeli).
    var singular: String {
        switch self {
        case .all: return ""
        case .map: return "mapa"
        case .mod: return "mod"
        case .episode: return "epizod"
        case .mapjam: return "jam"
        case .speedmap: return "speedmapa"
        }
    }
}

struct MapPackage: Identifiable, Hashable {
    let id: String
    var sha256 = ""
    var filename = ""
    var title = ""
    var author = ""
    var date = ""
    var sortDate = Date.distantPast
    var sizeKB = 0
    var rating = 0
    var ratingAvg = 0.0
    var ratingCount = 0
    var downloadURL: URL?
    var detailLoaded = false
    var descriptionText = ""
    var commandline = ""
    var zipbasedir = ""
    var startmaps: [String] = []
    var requirements: [String] = []
    var tags: [String] = []

    /// Rodzaje z tagów `type=` (paczka może mieć kilka, np. mod + epizod).
    var kinds: [PackageKind] {
        tags.filter { $0.hasPrefix("type=") }
            .compactMap { PackageKind(rawValue: String($0.dropFirst(5))) }
    }

    /// Opis rodzaju do tabeli. Paczka bywa kilku rodzajów naraz (np. mapa z własnym
    /// modem) — pokazujemy wszystkie; nieznane typy (demo, contest…) wprost z bazy.
    var kindText: String {
        let known = kinds.filter { $0 != .all }
        if !known.isEmpty { return known.map(\.singular).joined(separator: ", ") }
        return tags.first { $0.hasPrefix("type=") }.map { String($0.dropFirst(5)) } ?? ""
    }

    /// Mod, na którym paczka ma być uruchamiana (tag `mod=`), np. quoth, copper.
    var requiredMod: String? {
        tags.first { $0.hasPrefix("mod=") }.map { String($0.dropFirst(4)) }
    }

    /// Kiedy paczka trafiła na dysk. Zapisujemy przy instalacji; dla starszych
    /// wpisów bywa odtworzona z daty katalogu, a często po prostu nieznana.
    var installedAt: Date?

    /// Klucz sortowania kolumny „Zainstalowano" — nieznane lądują na końcu.
    var installedSort: Date { installedAt ?? .distantPast }

    var installedText: String {
        guard let installedAt else { return "—" }
        return Self.installedFormatter.string(from: installedAt)
    }

    private static let installedFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    var sizeText: String {
        sizeKB >= 1024 ? String(format: "%.1f MB", Double(sizeKB) / 1024) : "\(sizeKB) KB"
    }
    var stars: String {
        rating > 0 ? String(repeating: "★", count: rating) + String(repeating: "☆", count: max(0, 5 - rating)) : "—"
    }
}

// MARK: - Trwała historia instalacji
//
// UserDefaults żyją na komputerze, a paczki na dysku z grą — po przesiadce na inny Mac
// albo po wyczyszczeniu preferencji lista zainstalowanych paczek znikała, mimo że pliki
// leżały na miejscu. Dlatego równolegle zapisujemy ją do katalogu bazowego: jedzie razem
// z dyskiem. Plik jest ukryty (kropka), więc skan modów go nie widzi.

struct InstallRecord: Codable {
    var date: Double? // sekundy od 1970; nil dla instalacji sprzed wprowadzenia znacznika
    var maps: [String]?
}

struct InstallHistory: Codable {
    var version = 1
    var installs: [String: InstallRecord] = [:]
}

/// Odpowiedź /api/v1/?q=+sha256:<hash> — szczegóły jednej paczki.
struct APIPackage: Decodable {
    let bytes: Int?
    let description: String?
    let install: [String: String]?
    let sha256: String?
    let tags: [String]?
    let urls: [String]?
}

/// Parser indeksu https://www.quaddicted.com/db/v2/ — tabela HTML ze wszystkimi paczkami.
enum QuaddictedIndex {
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    static func stripTags(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        out = out.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // &#039; i &#39; to ta sama encja zapisana z zerem wiodącym i bez — SlipSeer używa pierwszej
        for (entity, char) in [("&amp;", "&"), ("&quot;", "\""), ("&lt;", "<"), ("&gt;", ">"),
                               ("&#039;", "'"), ("&#39;", "'"), ("&#8217;", "'"), ("&nbsp;", " ")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parse(_ html: String) -> [MapPackage] {
        guard let rowRegex = try? NSRegularExpression(
                  pattern: "<tr id=\"sha256_([a-f0-9]{64})\">(.*?)</tr>",
                  options: [.dotMatchesLineSeparators]),
              let tdRegex = try? NSRegularExpression(
                  pattern: "<td[^>]*>(.*?)</td>",
                  options: [.dotMatchesLineSeparators]),
              // tagi (type=mod, mod=quoth, theme=base…) siedzą w indeksie jako przyciski filtra
              let tagRegex = try? NSRegularExpression(pattern: "include_tag_in_query\\('([^']+)'\\)")
        else { return [] }

        let ns = html as NSString
        var seen = Set<String>()
        var result: [MapPackage] = []
        for match in rowRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let sha = ns.substring(with: match.range(at: 1))
            guard seen.insert(sha).inserted else { continue }
            let body = ns.substring(with: match.range(at: 2))
            let bodyNS = body as NSString
            // kolumny: sha | data | autor | plik | tytuł | śr. ocena | mediana | głosy | …
            let tds = tdRegex.matches(in: body, range: NSRange(location: 0, length: bodyNS.length))
                .map { stripTags(bodyNS.substring(with: $0.range(at: 1))) }
            guard tds.count >= 8 else { continue }
            let filename = tds[3]
            let id = filename.hasSuffix(".zip") ? String(filename.dropLast(4)) : filename
            guard !id.isEmpty, id != "000", id != "zzz" else { continue }
            var pkg = MapPackage(id: id)
            pkg.sha256 = sha
            pkg.filename = filename
            pkg.date = tds[1]
            pkg.sortDate = dateFormatter.date(from: tds[1]) ?? .distantPast
            pkg.author = tds[2]
            pkg.title = tds[4]
            pkg.ratingAvg = Double(tds[5]) ?? 0
            pkg.ratingCount = Int(tds[7]) ?? 0
            pkg.rating = Int((Double(tds[5]) ?? 0).rounded())
            pkg.tags = tagRegex.matches(in: body, range: NSRange(location: 0, length: bodyNS.length))
                .map { bodyNS.substring(with: $0.range(at: 1)) }
            result.append(pkg)
        }
        return result
    }
}

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

// MARK: - Quaddicted: widoki

struct MapBrowserView: View {
    @ObservedObject var launcher: LauncherModel
    @ObservedObject var browser: BrowserModel
    @ObservedObject var registry: InstallRegistry
    @State private var selectedID: String?
    @State private var sortOrder = [KeyPathComparator(\MapPackage.sortDate, order: .reverse)]

    private var filtered: [MapPackage] {
        browser.filtered(launcher: launcher).sorted(using: sortOrder)
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 8) {
                HStack {
                    TextField("Szukaj (tytuł, autor, id)…", text: $browser.searchText)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $browser.kindFilter) {
                        ForEach(PackageKind.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().frame(width: 130)
                    .help("Baza Quaddicted zawiera nie tylko mapy — także mody, epizody i jamy.")
                    Toggle("Zainstalowane", isOn: $browser.onlyInstalled)
                    Button {
                        Task { await browser.load(force: true) }
                    } label: { Image(systemName: "arrow.clockwise") }
                        .help("Odśwież bazę z Quaddicted")
                        .disabled(browser.loading)
                }
                .padding([.top, .horizontal], 10)

                Table(filtered, selection: $selectedID, sortOrder: $sortOrder) {
                    TableColumn("Tytuł", value: \.title) { pkg in
                        HStack(spacing: 4) {
                            if browser.isInstalled(pkg, launcher: launcher) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                            Text(pkg.title.isEmpty ? pkg.id : pkg.title)
                        }
                    }
                    TableColumn("Autor", value: \.author)
                    TableColumn("Rodzaj", value: \.kindText) { Text($0.kindText) }.width(110)
                    TableColumn("Data", value: \.sortDate) { Text($0.date) }.width(80)
                    TableColumn("Pobrano", value: \.installedSort) { pkg in
                        Text(pkg.installedText)
                            .foregroundStyle(pkg.installedAt == nil ? .secondary : .primary)
                    }
                    .width(85)
                    TableColumn("Ocena", value: \.rating) { Text($0.stars) }.width(70)
                }

                HStack {
                    if browser.loading { ProgressView().controlSize(.small) }
                    Text(browser.statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text("\(filtered.count) z \(browser.packages.count)").font(.caption).foregroundStyle(.secondary)
                }
                .padding([.bottom, .horizontal], 10)
            }
            .frame(minWidth: 440)

            Group {
                if let pkg = filtered.first(where: { $0.id == selectedID })
                    ?? browser.packages.first(where: { $0.id == selectedID }) {
                    PackageDetail(launcher: launcher, browser: browser, registry: registry, pkg: pkg)
                } else {
                    Text("Wybierz mapę z listy").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 340)
        }
        .frame(minWidth: 920, minHeight: 560)
        .task {
            // kolejność ma znaczenie: najpierw to, co zna dysk, potem odzysk z katalogów,
            // a na końcu zrzut scalonego stanu z powrotem na dysk
            browser.loadInstallHistory(launcher: launcher)
            browser.backfillInstallDates(launcher: launcher)
            browser.saveInstallHistory(launcher: launcher)
            await browser.loadIfNeeded()
            // tagi paczek znamy dopiero po wczytaniu indeksu
            browser.backfillFromIndex(registry: registry, launcher: launcher)
        }
    }
}

struct PackageDetail: View {
    @ObservedObject var launcher: LauncherModel
    @ObservedObject var browser: BrowserModel
    @ObservedObject var registry: InstallRegistry
    let pkg: MapPackage

    private var subtitle: String {
        var parts = [pkg.author, pkg.date]
        if pkg.sizeKB > 0 { parts.append(pkg.sizeText) }
        if pkg.ratingAvg > 0 { parts.append(String(format: "ocena %.1f★ (%d głosów)", pkg.ratingAvg, pkg.ratingCount)) }
        parts.append("id: \(pkg.id)")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(pkg.title.isEmpty ? pkg.id : pkg.title).font(.title2).bold()
                Text(subtitle)
                    .font(.caption).foregroundStyle(.secondary)

                AsyncImage(url: browser.screenshotURL(for: pkg)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 6))
                    case .failure:
                        Label("Brak zrzutu ekranu", systemImage: "photo")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
                    default:
                        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
                .frame(maxHeight: 280)

                HStack {
                    if !pkg.detailLoaded, !browser.installing.contains(pkg.id) {
                        ProgressView().controlSize(.small)
                        Text("Pobieram szczegóły…").font(.caption).foregroundStyle(.secondary)
                    } else if browser.installing.contains(pkg.id) {
                        ProgressView().controlSize(.small)
                        Text("Instaluję…")
                    } else if browser.isInstalled(pkg, launcher: launcher) {
                        Button("Graj ▶") { browser.play(pkg, launcher: launcher) }
                            .buttonStyle(.borderedProminent)
                        let maps = browser.availableMaps(pkg)
                        if maps.count > 1 {
                            Menu("mapa ▾") {
                                ForEach(maps, id: \.self) { map in
                                    Button(map) { browser.play(pkg, launcher: launcher, map: map) }
                                }
                            }
                            .frame(width: 90)
                        }
                        Label("zainstalowana", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    } else {
                        Button("Pobierz i zainstaluj") {
                            Task { await browser.install(pkg, launcher: launcher, registry: registry) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                    Link("Quaddicted ↗", destination: URL(string: "https://www.quaddicted.com/db/v2/maps/\(pkg.sha256)")!)
                }

                if !pkg.requirements.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wymaga:").font(.callout).bold()
                        ForEach(pkg.requirements, id: \.self) { reqID in
                            requirementRow(reqID)
                        }
                    }
                }
                if let mod = pkg.requiredMod, !launcher.baseModInstalled(mod) {
                    // duże mody (Arcane Dimensions, Copper, Quoth) nie są hostowane
                    // na Quaddicted — bazę trzeba zdobyć samemu. Sam katalog nie wystarczy:
                    // tworzą go same mapy, a bez progs.dat mapa startuje bez logiki moda.
                    Label("Wymaga moda \"\(mod)\" — w katalogu gry są tylko mapy, brakuje samego moda "
                          + "(progs.dat/pak). Bez niego mapa uruchomi się bez logiki dodatku.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                if !pkg.startmaps.isEmpty {
                    Text("Mapa startowa: \(pkg.startmaps.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !pkg.commandline.isEmpty {
                    Text("Parametry: \(pkg.commandline)").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                if !pkg.tags.isEmpty {
                    Text("Tagi: \(pkg.tags.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                }
                if browser.isInstalled(pkg, launcher: launcher), !browser.availableMaps(pkg).isEmpty {
                    Divider()
                    MapSpoilerPanel(launcher: launcher,
                                    mapNames: browser.availableMaps(pkg),
                                    preferredGame: browser.playGameDir(pkg, launcher: launcher))
                        .id(pkg.id) // przy zmianie paczki panel wraca do stanu zamkniętego
                }
                Divider()
                Text(pkg.descriptionText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
        }
        .task(id: pkg.id) { await browser.ensureDetail(pkg.id) }
    }

    @ViewBuilder private func requirementRow(_ reqID: String) -> some View {
        HStack(spacing: 6) {
            if let req = browser.packages.first(where: { $0.id == reqID }) {
                let installed = browser.isInstalled(req, launcher: launcher)
                Image(systemName: installed ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(installed ? .green : .orange)
                Text(req.title.isEmpty ? req.id : req.title)
                if !installed, !browser.installing.contains(req.id) {
                    Button("Zainstaluj") {
                        Task { await browser.install(req, launcher: launcher, registry: registry) }
                    }
                    .controlSize(.small)
                } else if browser.installing.contains(req.id) {
                    ProgressView().controlSize(.small)
                }
            } else {
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                Text(reqID)
            }
        }
        .font(.callout)
    }
}

@main
struct QuakeLauncherApp: App {
    @StateObject private var model = LauncherModel()
    @StateObject private var browser = BrowserModel()
    @StateObject private var moddb = ModDBModel()
    @StateObject private var slipseer = SlipSeerModel()
    @StateObject private var registry = InstallRegistry()

    init() {
        // proste cudzysłowy/myślniki w polu parametrów (jak w QuakeConfig)
        UserDefaults.standard.set(false, forKey: "NSAutomaticQuoteSubstitutionEnabled")
        UserDefaults.standard.set(false, forKey: "NSAutomaticDashSubstitutionEnabled")
    }

    var body: some Scene {
        WindowGroup("Quake Launcher") {
            ContentView(model: model, registry: registry)
                .task { registry.migrateIfNeeded(base: model.baseDir) }
        }
        .windowResizability(.contentSize)

        Window("Mapy — Quaddicted", id: "maps") {
            MapBrowserView(launcher: model, browser: browser, registry: registry)
        }

        Window("ModDB", id: "moddb") {
            ModDBBrowserView(launcher: model, browser: moddb, registry: registry)
        }

        Window("SlipSeer", id: "slipseer") {
            SlipSeerView(launcher: model, browser: slipseer, registry: registry)
        }

        Window("Pobrane", id: "library") {
            LibraryView(launcher: model, registry: registry)
        }
    }
}
