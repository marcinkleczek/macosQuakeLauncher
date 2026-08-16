import SwiftUI

// MARK: - Definicje opcji

struct Choice: Identifiable, Hashable {
    let label: String
    let value: String
    var id: String { value }
}

struct CvarOption: Identifiable {
    enum Kind {
        case toggle(on: String, off: String)
        case slider(ClosedRange<Double>, step: Double)
        case choice([Choice])
        case text(placeholder: String)
    }

    let cvar: String
    let label: String
    let section: String
    let kind: Kind
    let defaultValue: String
    var help: String? = nil

    var id: String { cvar }
}

let ALL_OPTIONS: [CvarOption] = [
    // Mysz
    CvarOption(cvar: "sensitivity", label: "Czułość myszy", section: "Mysz", kind: .slider(1...15, step: 0.5), defaultValue: "3"),
    CvarOption(cvar: "m_pitch", label: "Odwrócona oś Y", section: "Mysz", kind: .toggle(on: "-0.022", off: "0.022"), defaultValue: "0.022"),
    CvarOption(cvar: "lookspring", label: "Powrót widoku do poziomu", section: "Mysz", kind: .toggle(on: "1", off: "0"), defaultValue: "0"),
    // Ruch
    CvarOption(cvar: "cl_alwaysrun", label: "Zawsze biegaj", section: "Ruch", kind: .toggle(on: "1", off: "0"), defaultValue: "1"),
    // Widok
    CvarOption(cvar: "fov", label: "Pole widzenia (FOV)", section: "Widok", kind: .slider(60...130, step: 1), defaultValue: "90"),
    CvarOption(cvar: "r_drawviewmodel", label: "Pokazuj broń", section: "Widok", kind: .toggle(on: "1", off: "0"), defaultValue: "1"),
    CvarOption(cvar: "cl_bob", label: "Kołysanie broni przy ruchu", section: "Widok", kind: .toggle(on: "0.02", off: "0"), defaultValue: "0.02"),
    CvarOption(cvar: "cl_rollangle", label: "Przechył ekranu w skrętach", section: "Widok", kind: .toggle(on: "2", off: "0"), defaultValue: "2"),
    CvarOption(cvar: "crosshair", label: "Celownik", section: "Widok", kind: .toggle(on: "1", off: "0"), defaultValue: "1"),
    CvarOption(cvar: "scr_crosshairscale", label: "Wielkość celownika", section: "Widok", kind: .slider(1...5, step: 0.5), defaultValue: "1"),
    // Tryb wideo
    CvarOption(cvar: "vid_fullscreen", label: "Pełny ekran", section: "Tryb wideo", kind: .toggle(on: "1", off: "0"), defaultValue: "1"),
    CvarOption(cvar: "vid_desktopfullscreen", label: "Natywna rozdzielczość pulpitu", section: "Tryb wideo", kind: .toggle(on: "1", off: "0"), defaultValue: "1",
               help: "Gdy włączone, pola szerokość/wysokość nie mają znaczenia w trybie pełnoekranowym."),
    CvarOption(cvar: "vid_width", label: "Szerokość", section: "Tryb wideo", kind: .text(placeholder: "puste = bez zmian"), defaultValue: ""),
    CvarOption(cvar: "vid_height", label: "Wysokość", section: "Tryb wideo", kind: .text(placeholder: "puste = bez zmian"), defaultValue: ""),
    CvarOption(cvar: "vid_vsync", label: "Synchronizacja pionowa (VSync)", section: "Tryb wideo", kind: .toggle(on: "1", off: "0"), defaultValue: "1"),
    CvarOption(cvar: "host_maxfps", label: "Limit FPS", section: "Tryb wideo",
               kind: .choice([Choice(label: "60", value: "60"), Choice(label: "72 (klasyczny)", value: "72"), Choice(label: "120", value: "120"),
                              Choice(label: "144", value: "144"), Choice(label: "165", value: "165"), Choice(label: "240", value: "240")]),
               defaultValue: "72"),
    CvarOption(cvar: "vid_fsaa", label: "Antyaliasing (MSAA)", section: "Tryb wideo",
               kind: .choice([Choice(label: "Wyłączony", value: "0"), Choice(label: "2×", value: "2"), Choice(label: "4×", value: "4"), Choice(label: "8×", value: "8")]),
               defaultValue: "0", help: "Zmiana wymaga restartu silnika."),
    // Grafika
    CvarOption(cvar: "gl_texturemode", label: "Tekstury", section: "Grafika",
               kind: .choice([Choice(label: "Pikselowe (klasyczne)", value: "GL_NEAREST_MIPMAP_LINEAR"),
                              Choice(label: "Filtrowane (wygładzone)", value: "GL_LINEAR_MIPMAP_LINEAR")]),
               defaultValue: "GL_LINEAR_MIPMAP_LINEAR"),
    CvarOption(cvar: "r_particles", label: "Cząsteczki", section: "Grafika",
               kind: .choice([Choice(label: "Okrągłe", value: "1"), Choice(label: "Klasyczne kwadraty", value: "2"), Choice(label: "Wyłączone", value: "0")]),
               defaultValue: "1"),
    CvarOption(cvar: "r_shadows", label: "Cienie pod obiektami", section: "Grafika", kind: .toggle(on: "1", off: "0"), defaultValue: "0"),
    CvarOption(cvar: "r_lerpmodels", label: "Płynna animacja modeli", section: "Grafika", kind: .toggle(on: "1", off: "0"), defaultValue: "1"),
    CvarOption(cvar: "r_lerpmove", label: "Płynny ruch potworów", section: "Grafika", kind: .toggle(on: "1", off: "0"), defaultValue: "1"),
    CvarOption(cvar: "r_scale", label: "Pikselizacja obrazu (retro)", section: "Grafika",
               kind: .choice([Choice(label: "Wyłączona", value: "1"), Choice(label: "2×", value: "2"), Choice(label: "3×", value: "3"), Choice(label: "4×", value: "4")]),
               defaultValue: "1", help: "Renderuje obraz w ułamku rozdzielczości — wygląd jak w 1996."),
    CvarOption(cvar: "r_wateralpha", label: "Przezroczystość wody", section: "Grafika", kind: .slider(0.3...1, step: 0.05), defaultValue: "1",
               help: "Na oryginalnych mapach wymaga silnika z obsługą przezroczystej wody (QuakeSpasm/vkQuake ją mają)."),
    CvarOption(cvar: "gamma", label: "Gamma (mniej = jaśniej)", section: "Grafika", kind: .slider(0.5...1.3, step: 0.05), defaultValue: "1"),
    CvarOption(cvar: "contrast", label: "Kontrast", section: "Grafika", kind: .slider(1...2, step: 0.1), defaultValue: "1"),
    // HUD
    CvarOption(cvar: "scr_sbarscale", label: "Skala paska statusu", section: "HUD",
               kind: .choice([Choice(label: "1×", value: "1"), Choice(label: "2×", value: "2"), Choice(label: "3×", value: "3"), Choice(label: "4×", value: "4")]),
               defaultValue: "2"),
    CvarOption(cvar: "scr_menuscale", label: "Skala menu", section: "HUD",
               kind: .choice([Choice(label: "1×", value: "1"), Choice(label: "2×", value: "2"), Choice(label: "3×", value: "3"), Choice(label: "4×", value: "4")]),
               defaultValue: "2"),
    CvarOption(cvar: "scr_conscale", label: "Skala konsoli", section: "HUD",
               kind: .choice([Choice(label: "1×", value: "1"), Choice(label: "2×", value: "2"), Choice(label: "3×", value: "3"), Choice(label: "4×", value: "4")]),
               defaultValue: "2"),
    CvarOption(cvar: "scr_sbaralpha", label: "Nieprzezroczystość paska statusu", section: "HUD", kind: .slider(0...1, step: 0.05), defaultValue: "0.75"),
    CvarOption(cvar: "scr_showfps", label: "Licznik FPS", section: "HUD", kind: .toggle(on: "1", off: "0"), defaultValue: "0"),
    // Dźwięk
    CvarOption(cvar: "volume", label: "Głośność efektów", section: "Dźwięk", kind: .slider(0...1, step: 0.05), defaultValue: "0.7"),
    CvarOption(cvar: "bgmvolume", label: "Głośność muzyki", section: "Dźwięk", kind: .slider(0...1, step: 0.05), defaultValue: "1"),
    // Multiplayer — sekcja ma własną zakładkę (PlayerTab), nie trafia do OptionsTab
    CvarOption(cvar: "name", label: "Imię gracza", section: "Multiplayer", kind: .text(placeholder: "player"), defaultValue: ""),
]

let DEFAULT_BINDS: [(String, String)] = [
    ("w", "+forward"), ("s", "+back"), ("a", "+moveleft"), ("d", "+moveright"),
    ("SPACE", "+jump"), ("MOUSE1", "+attack"),
    ("MWHEELUP", "impulse 12"), ("MWHEELDOWN", "impulse 10"),
    ("TAB", "+showscores"), ("F12", "screenshot"),
]

struct BindEntry: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var command: String
}

// MARK: - Układ klawiatury

struct KeyDef: Identifiable {
    let id: String
    let label: String
    let quake: String? // nil = klawisz zarezerwowany (Esc, `, Caps) albo przerwa w układzie
    var width: CGFloat = 1

    var isGap: Bool { quake == nil && label.isEmpty }
}

private func k(_ id: String, _ label: String, _ quake: String?, _ width: CGFloat = 1) -> KeyDef {
    KeyDef(id: id, label: label, quake: quake, width: width)
}

let KEYBOARD_ROWS: [[KeyDef]] = [
    [k("esc", "Esc", nil), k("gap1", "", nil, 2)] + (1...12).map { k("f\($0)", "F\($0)", "F\($0)") },
    [k("bq", "`", nil)] + ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].map { k("n\($0)", $0, $0) }
        + [k("minus", "-", "-"), k("eq", "=", "="), k("bksp", "⌫", "BACKSPACE", 2)],
    [k("tab", "Tab", "TAB", 1.5)] + "qwertyuiop".map { k(String($0), String($0), String($0)) }
        + [k("lbr", "[", "["), k("rbr", "]", "]"), k("bsl", "\\", "\\", 1.5)],
    [k("caps", "Caps", nil, 1.75)] + "asdfghjkl".map { k(String($0), String($0), String($0)) }
        + [k("semi", ";", "SEMICOLON"), k("quote", "'", "'"), k("ent", "Enter", "ENTER", 2.25)],
    [k("lsh", "Shift", "SHIFT", 2.25)] + "zxcvbnm".map { k(String($0), String($0), String($0)) }
        + [k("com", ",", ","), k("dot", ".", "."), k("sl", "/", "/"), k("rsh", "Shift", "SHIFT", 2.75)],
    [k("lct", "Ctrl", "CTRL", 1.5), k("lal", "Alt", "ALT", 1.5), k("spc", "Spacja", "SPACE", 9),
     k("ral", "Alt", "ALT", 1.5), k("rct", "Ctrl", "CTRL", 1.5)],
]

let SIDE_ROWS: [[KeyDef]] = [
    [k("ins", "Ins", "INS"), k("home", "Home", "HOME"), k("pgup", "PgUp", "PGUP")],
    [k("del", "Del", "DEL"), k("end", "End", "END"), k("pgdn", "PgDn", "PGDN")],
]

let ARROW_KEYS = (up: k("up", "▲", "UPARROW"), left: k("left", "◀", "LEFTARROW"),
                  down: k("down", "▼", "DOWNARROW"), right: k("right", "▶", "RIGHTARROW"))

let MOUSE_KEYS: [KeyDef] = [
    k("m1", "LPM", "MOUSE1", 1.8), k("m2", "PPM", "MOUSE2", 1.8), k("m3", "ŚPM", "MOUSE3", 1.8),
    k("mwu", "Kółko ▲", "MWHEELUP", 2.2), k("mwd", "Kółko ▼", "MWHEELDOWN", 2.2),
    k("m4", "M4", "MOUSE4", 1.2), k("m5", "M5", "MOUSE5", 1.2),
]

// MARK: - Typowe komendy

struct CommandDef {
    let cmd: String
    let label: String
}

let COMMAND_GROUPS: [(name: String, color: Color, commands: [CommandDef])] = [
    ("Ruch", .blue, [
        CommandDef(cmd: "+forward", label: "Naprzód"),
        CommandDef(cmd: "+back", label: "W tył"),
        CommandDef(cmd: "+moveleft", label: "W lewo (strafe)"),
        CommandDef(cmd: "+moveright", label: "W prawo (strafe)"),
        CommandDef(cmd: "+jump", label: "Skok / pływanie w górę"),
        CommandDef(cmd: "+moveup", label: "Pływanie w górę"),
        CommandDef(cmd: "+movedown", label: "Pływanie w dół"),
        CommandDef(cmd: "+speed", label: "Bieg (gdy wyłączone „zawsze biegaj”)"),
    ]),
    ("Broń", .red, [
        CommandDef(cmd: "impulse 1", label: "Siekiera"),
        CommandDef(cmd: "impulse 2", label: "Shotgun"),
        CommandDef(cmd: "impulse 3", label: "Super Shotgun"),
        CommandDef(cmd: "impulse 4", label: "Nailgun"),
        CommandDef(cmd: "impulse 5", label: "Super Nailgun"),
        CommandDef(cmd: "impulse 6", label: "Granatnik"),
        CommandDef(cmd: "impulse 7", label: "Wyrzutnia rakiet"),
        CommandDef(cmd: "impulse 8", label: "Thunderbolt"),
        CommandDef(cmd: "impulse 10", label: "Następna broń"),
        CommandDef(cmd: "impulse 12", label: "Poprzednia broń"),
    ]),
    ("Akcje", .orange, [
        CommandDef(cmd: "+attack", label: "Strzał"),
        CommandDef(cmd: "+showscores", label: "Tablica wyników"),
        CommandDef(cmd: "screenshot", label: "Zrzut ekranu"),
        CommandDef(cmd: "save quick", label: "Szybki zapis"),
        CommandDef(cmd: "load quick", label: "Szybkie wczytanie"),
        CommandDef(cmd: "messagemode", label: "Czat"),
        CommandDef(cmd: "messagemode2", label: "Czat drużynowy"),
        CommandDef(cmd: "pause", label: "Pauza"),
        CommandDef(cmd: "toggleconsole", label: "Konsola"),
    ]),
]

func categoryColor(for command: String) -> Color? {
    let trimmed = command.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    for group in COMMAND_GROUPS where group.commands.contains(where: { $0.cmd == trimmed }) {
        return group.color
    }
    if trimmed.hasPrefix("impulse") { return .red }
    return .purple // własna komenda spoza listy
}

// MARK: - Czcionka konsoli Quake'a

/// Oryginalna czcionka gry: lump CONCHARS (128×128 indeksów palety, 256 glifów 8×8)
/// z gfx.wad w id1/pak0.pak, kolorowany paletą gfx/palette.lmp.
/// Znaki 128–255 to te same glify w wersji „złotej" — stąd bierze się kolor.
final class QuakeFont {
    private let chars: [UInt8]
    private let palette: [UInt8]

    init?(baseDir: URL) {
        guard let pak = try? Data(contentsOf: baseDir.appendingPathComponent("id1/pak0.pak")),
              let wad = Self.pakEntry(pak, "gfx.wad"),
              let pal = Self.pakEntry(pak, "gfx/palette.lmp"), pal.count >= 768,
              let glyphs = Self.wadLump(wad, "CONCHARS"), glyphs.count >= 128 * 128
        else { return nil }
        chars = [UInt8](glyphs.prefix(128 * 128))
        palette = [UInt8](pal.prefix(768))
    }

    /// Kod znaku dla Quake'a; poza ASCII/high-bit gra nic sensownego nie wyświetli.
    static func code(_ scalar: UnicodeScalar) -> UInt8 {
        scalar.value <= 0xFF ? UInt8(scalar.value) : 0x3F // '?'
    }

    func image(for text: String) -> NSImage? {
        let codes = text.unicodeScalars.map(Self.code)
        guard !codes.isEmpty else { return nil }
        let width = codes.count * 8, height = 8
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for (i, code) in codes.enumerated() {
            let sx = Int(code % 16) * 8, sy = Int(code / 16) * 8
            for y in 0 ..< 8 {
                for x in 0 ..< 8 {
                    let index = Int(chars[(sy + y) * 128 + sx + x])
                    if index == 0 { continue } // 0 = przezroczysty
                    let o = (y * width + i * 8 + x) * 4
                    pixels[o] = palette[index * 3]
                    pixels[o + 1] = palette[index * 3 + 1]
                    pixels[o + 2] = palette[index * 3 + 2]
                    pixels[o + 3] = 255
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }

    // MARK: Parsery formatów id Software

    private static func u32(_ d: Data, _ offset: Int) -> Int {
        Int(d[offset]) | Int(d[offset + 1]) << 8 | Int(d[offset + 2]) << 16 | Int(d[offset + 3]) << 24
    }

    private static func name(_ d: Data, _ offset: Int, _ length: Int) -> String {
        let bytes = [UInt8](d[offset ..< offset + length]).prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// PAK: nagłówek "PACK" + tablica wpisów po 64 B (56 B nazwa, offset, długość).
    private static func pakEntry(_ pak: Data, _ wanted: String) -> Data? {
        guard pak.count > 12, name(pak, 0, 4) == "PACK" else { return nil }
        let dirOffset = u32(pak, 4), dirLength = u32(pak, 8)
        guard dirOffset + dirLength <= pak.count else { return nil }
        for i in stride(from: 0, to: dirLength, by: 64) {
            let entry = dirOffset + i
            guard name(pak, entry, 56).lowercased() == wanted.lowercased() else { continue }
            let offset = u32(pak, entry + 56), length = u32(pak, entry + 60)
            guard offset + length <= pak.count else { return nil }
            return Data(pak[offset ..< offset + length])
        }
        return nil
    }

    /// WAD2: nagłówek "WAD2" + tablica lumpów po 32 B (pozycja, rozmiary, typ, 16 B nazwa).
    private static func wadLump(_ wad: Data, _ wanted: String) -> Data? {
        guard wad.count > 12, name(wad, 0, 4) == "WAD2" else { return nil }
        let count = u32(wad, 4), table = u32(wad, 8)
        for i in 0 ..< count {
            let entry = table + i * 32
            guard entry + 32 <= wad.count else { return nil }
            guard name(wad, entry + 16, 16).uppercased() == wanted.uppercased() else { continue }
            let offset = u32(wad, entry), length = u32(wad, entry + 8)
            guard offset + length <= wad.count else { return nil }
            return Data(wad[offset ..< offset + length])
        }
        return nil
    }
}

// MARK: - Model

final class ConfigModel: ObservableObject {
    @Published var baseDir: URL?
    @Published var gameDirs: [String] = []
    @Published var selectedDir = "id1"
    @Published var values: [String: String] = [:]
    @Published var binds: [BindEntry] = []
    @Published var customText = ""
    @Published var status = ""
    @Published var dirty = false
    @Published var greeting = true          // komunikat `echo` po wczytaniu konfigu
    @Published private(set) var font: QuakeFont?

    private let defaults = UserDefaults.standard
    private let fm = FileManager.default
    private static let marker = "// [QCE]"

    var fileURL: URL? {
        baseDir?.appendingPathComponent(selectedDir).appendingPathComponent("autoexec.cfg")
    }

    init() {
        if let path = defaults.string(forKey: "baseDir") {
            baseDir = URL(fileURLWithPath: path)
        } else if let shared = CFPreferencesCopyAppValue("baseDir" as CFString, "com.marcinkleczek.quakelauncher" as CFString) as? String {
            baseDir = URL(fileURLWithPath: shared) // katalog ustawiony w QuakeLauncherze
        } else {
            let guess = fm.homeDirectoryForCurrentUser.appendingPathComponent("Quake")
            if fm.fileExists(atPath: guess.appendingPathComponent("id1").path) { baseDir = guess }
        }
        scanGameDirs()
        if let saved = defaults.string(forKey: "gameDir"), gameDirs.contains(saved) { selectedDir = saved }
        font = baseDir.flatMap { QuakeFont(baseDir: $0) }
        load()
    }

    func setBaseDir(_ url: URL) {
        baseDir = url
        defaults.set(url.path, forKey: "baseDir")
        scanGameDirs()
        selectedDir = "id1"
        font = QuakeFont(baseDir: url)
        load()
    }

    func scanGameDirs() {
        guard let base = baseDir,
              let entries = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        else { gameDirs = []; return }
        var found: [String] = []
        for dir in entries where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let name = dir.lastPathComponent
            if name == "id1" { continue }
            let contents = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            let looksLikeMod = contents.contains { c in
                let l = c.lowercased()
                return l.hasSuffix(".pak") || l.hasSuffix(".pk3") || l == "progs.dat" || l == "maps"
            }
            if looksLikeMod { found.append(name) }
        }
        gameDirs = ["id1"] + found.sorted()
    }

    func switchDir(to newDir: String) {
        guard newDir != selectedDir else { return }
        if dirty {
            let alert = NSAlert()
            alert.messageText = "Niezapisane zmiany w \(selectedDir)/autoexec.cfg"
            alert.informativeText = "Co zrobić przed przełączeniem na \(newDir)?"
            alert.addButton(withTitle: "Zapisz i przełącz")
            alert.addButton(withTitle: "Porzuć zmiany")
            alert.addButton(withTitle: "Anuluj")
            switch alert.runModal() {
            case .alertFirstButtonReturn: save()
            case .alertSecondButtonReturn: break
            default: return
            }
        }
        selectedDir = newDir
        defaults.set(newDir, forKey: "gameDir")
        load()
    }

    // MARK: Wczytywanie

    func resetDefaults() {
        values = Dictionary(uniqueKeysWithValues: ALL_OPTIONS.map { ($0.cvar, $0.defaultValue) })
        binds = DEFAULT_BINDS.map { BindEntry(key: $0.0, command: $0.1) }
        customText = ""
        greeting = true
        dirty = true
    }

    func load() {
        values = Dictionary(uniqueKeysWithValues: ALL_OPTIONS.map { ($0.cvar, $0.defaultValue) })
        binds = []
        customText = ""
        dirty = false
        greeting = false

        guard let url = fileURL, let data = try? Data(contentsOf: url) else {
            binds = DEFAULT_BINDS.map { BindEntry(key: $0.0, command: $0.1) }
            greeting = true
            status = "Nowy konfig — plik \(selectedDir)/autoexec.cfg jeszcze nie istnieje."
            return
        }
        let raw = Self.decode(data)

        var custom: [String] = []
        let knownCvars = Set(ALL_OPTIONS.map(\.cvar))
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix(Self.marker) { continue }
            // linia powitania — nasza, oznaczona markerem na końcu; nie traktuj jak własnej komendy
            if trimmed.contains(Self.marker), trimmed.lowercased().hasPrefix("echo") {
                greeting = true
                continue
            }
            let tokens = Self.tokenize(trimmed)
            if tokens.count >= 3, tokens[0].lowercased() == "bind" {
                binds.append(BindEntry(key: tokens[1], command: tokens[2...].joined(separator: " ")))
            } else if tokens.count == 2, knownCvars.contains(tokens[0].lowercased()) {
                values[tokens[0].lowercased()] = tokens[1]
            } else {
                custom.append(line)
            }
        }
        customText = custom.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        status = "Wczytano \(selectedDir)/autoexec.cfg"
    }

    /// Dzieli linię na tokeny, honorując cudzysłowy i ucinając komentarze //.
    static func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuote = false
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if inQuote {
                if c == "\"" { inQuote = false; tokens.append(current); current = "" }
                else { current.append(c) }
            } else if c == "\"" {
                inQuote = true
            } else if c == "/", line.index(after: i) < line.endIndex, line[line.index(after: i)] == "/" {
                break
            } else if c == " " || c == "\t" {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(c)
            }
            i = line.index(after: i)
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    // MARK: Zapis

    /// macOS potrafi podmienić proste cudzysłowy na typograficzne (""'') przy pisaniu
    /// w polu tekstowym — silnik ich nie rozumie, więc prostujemy przy zapisie.
    private static func straightQuotes(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{201E}", with: "\"")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
    }

    /// Wartość w cudzysłowach; cfg nie zna escapowania, więc wewnętrzne " wycinamy.
    private static func quoted(_ s: String) -> String {
        "\"\(straightQuotes(s).replacingOccurrences(of: "\"", with: ""))\""
    }

    /// Plik cfg jest bajtowy: „złote" znaki Quake'a (128–255) muszą zostać
    /// pojedynczymi bajtami, reszta idzie normalnym UTF-8.
    static func encode(_ text: String) -> Data {
        var bytes: [UInt8] = []
        for scalar in text.unicodeScalars {
            if scalar.value >= 0x80, scalar.value <= 0xFF {
                bytes.append(UInt8(scalar.value))
            } else {
                bytes.append(contentsOf: Array(String(scalar).utf8))
            }
        }
        return Data(bytes)
    }

    /// Odwrotność `encode`: UTF-8 tam, gdzie się da; pojedyncze bajty 128–255 w pozostałych miejscach.
    static func decode(_ data: Data) -> String {
        var scalars = String.UnicodeScalarView()
        var i = data.startIndex
        while i < data.endIndex {
            let byte = data[i]
            let length = byte >= 0xF0 ? 4 : (byte >= 0xE0 ? 3 : (byte >= 0xC0 ? 2 : 1))
            if length > 1, i + length <= data.endIndex,
               let piece = String(data: data[i ..< i + length], encoding: .utf8) {
                scalars.append(contentsOf: piece.unicodeScalars)
                i += length
            } else {
                scalars.append(UnicodeScalar(byte))
                i += 1
            }
        }
        return String(scalars)
    }

    /// Przełącza tekst między zwykłym a „złotym" wariantem charsetu (znak ±128).
    static func gold(_ text: String, on: Bool) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            switch (on, scalar.value) {
            case (true, 0x20 ... 0x7E): return UnicodeScalar(scalar.value + 0x80)!
            case (false, 0xA0 ... 0xFE): return UnicodeScalar(scalar.value - 0x80)!
            default: return scalar
            }
        }))
    }

    var isGoldName: Bool {
        (values["name"] ?? "").unicodeScalars.contains { $0.value >= 0xA0 && $0.value <= 0xFE }
    }

    /// Komunikat wypisywany w konsoli po wykonaniu autoexec.cfg (charset gry = ASCII).
    func greetingText() -> String {
        let player = values["name"] ?? ""
        let base = "QCE: konfig \(selectedDir) wczytany"
        return player.isEmpty ? base : "\(base) | gracz: \(player)"
    }

    func configText() -> String {
        var out: [String] = [
            "\(Self.marker) Wygenerowano przez Quake Config Editor (\(selectedDir))",
            "\(Self.marker) Linie spoza aplikacji są zachowywane w sekcji \"Własne komendy\".",
            "",
        ]
        var lastSection = ""
        for option in ALL_OPTIONS {
            let value = values[option.cvar] ?? option.defaultValue
            if case .text = option.kind, value.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if option.section != lastSection {
                out.append("\(Self.marker) \(option.section)")
                lastSection = option.section
            }
            out.append("\(option.cvar) \(Self.quoted(value))")
        }
        let validBinds = binds.filter { !$0.key.isEmpty && !$0.command.isEmpty }
        if !validBinds.isEmpty {
            out.append("")
            out.append("\(Self.marker) Bindy")
            for bind in validBinds {
                out.append("bind \(Self.quoted(bind.key)) \(Self.quoted(bind.command))")
            }
        }
        if greeting {
            out.append("")
            out.append("\(Self.marker) Powitanie")
            // marker na końcu linii, żeby przy ponownym wczytaniu nie trafiła do "Własnych komend"
            out.append("echo \(Self.quoted(greetingText())) \(Self.marker)")
        }
        let custom = customText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            out.append("")
            out.append("\(Self.marker) Własne komendy")
            out.append(Self.straightQuotes(custom))
        }
        return out.joined(separator: "\n") + "\n"
    }

    func save() {
        guard let url = fileURL else { return }
        do {
            if fm.fileExists(atPath: url.path) {
                let backup = url.deletingPathExtension().appendingPathExtension("cfg.bak")
                try? fm.removeItem(at: backup)
                try fm.copyItem(at: url, to: backup)
            }
            try Self.encode(configText()).write(to: url, options: .atomic)
            dirty = false
            status = "Zapisano \(selectedDir)/autoexec.cfg (kopia zapasowa: autoexec.cfg.bak)"
        } catch {
            status = "Błąd zapisu: \(error.localizedDescription)"
        }
    }

    // MARK: Bindingi dla UI

    func stringBinding(_ option: CvarOption) -> Binding<String> {
        Binding(
            get: { self.values[option.cvar] ?? option.defaultValue },
            set: { self.values[option.cvar] = $0; self.dirty = true }
        )
    }

    func doubleBinding(_ option: CvarOption) -> Binding<Double> {
        Binding(
            get: { Double(self.values[option.cvar] ?? option.defaultValue) ?? 0 },
            set: { self.values[option.cvar] = String(format: "%g", $0); self.dirty = true }
        )
    }

    func boolBinding(_ option: CvarOption, on: String, off: String) -> Binding<Bool> {
        Binding(
            get: { (self.values[option.cvar] ?? option.defaultValue) == on },
            set: { self.values[option.cvar] = $0 ? on : off; self.dirty = true }
        )
    }

    // MARK: Bindy per klawisz (dla wizualnej klawiatury)

    func command(forKey key: String) -> String {
        binds.last { $0.key.lowercased() == key.lowercased() }?.command ?? ""
    }

    /// Quake trzyma jeden bind na klawisz — podmiana usuwa wcześniejsze wpisy dla tego klawisza.
    func setBind(key: String, command: String) {
        binds.removeAll { $0.key.lowercased() == key.lowercased() }
        if !command.isEmpty { binds.append(BindEntry(key: key, command: command)) }
        dirty = true
    }

    func commandBinding(forKey key: String) -> Binding<String> {
        Binding(
            get: { self.command(forKey: key) },
            set: { self.setBind(key: key, command: $0) }
        )
    }
}

// MARK: - Widoki

struct OptionRow: View {
    @ObservedObject var model: ConfigModel
    let option: CvarOption

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            control
            if let help = option.help {
                Text(help).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var control: some View {
        switch option.kind {
        case .toggle(let on, let off):
            Toggle(option.label, isOn: model.boolBinding(option, on: on, off: off))
        case .slider(let range, let step):
            HStack {
                Text(option.label)
                Spacer()
                Slider(value: model.doubleBinding(option), in: range, step: step).frame(width: 200)
                Text(model.values[option.cvar] ?? option.defaultValue)
                    .monospacedDigit().frame(width: 48, alignment: .trailing)
            }
        case .choice(let items):
            Picker(option.label, selection: model.stringBinding(option)) {
                ForEach(items) { Text($0.label).tag($0.value) }
            }
        case .text(let placeholder):
            HStack {
                Text(option.label)
                Spacer()
                TextField(placeholder, text: model.stringBinding(option))
                    .frame(width: 200).multilineTextAlignment(.trailing)
            }
        }
    }
}

struct OptionsTab: View {
    @ObservedObject var model: ConfigModel
    let sections: [String]

    var body: some View {
        Form {
            ForEach(sections, id: \.self) { section in
                Section(section) {
                    ForEach(ALL_OPTIONS.filter { $0.section == section }) { option in
                        OptionRow(model: model, option: option)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Podgląd tekstu prawdziwą czcionką konsoli Quake'a, na czarnym tle jak w grze.
struct QuakeTextPreview: View {
    let text: String
    let font: QuakeFont?
    var scale: CGFloat = 3

    var body: some View {
        HStack {
            if let font, let image = font.image(for: text) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: image.size.width * scale, height: image.size.height * scale)
            } else {
                Text(text.isEmpty ? " " : text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct PlayerTab: View {
    @ObservedObject var model: ConfigModel

    private var nameOption: CvarOption { ALL_OPTIONS.first { $0.cvar == "name" }! }

    private var goldBinding: Binding<Bool> {
        Binding(
            get: { model.isGoldName },
            set: { on in
                model.values["name"] = ConfigModel.gold(model.values["name"] ?? "", on: on)
                model.dirty = true
            }
        )
    }

    var body: some View {
        Form {
            Section("Multiplayer") {
                HStack {
                    Text("Imię gracza")
                    Spacer()
                    TextField("player", text: model.stringBinding(nameOption))
                        .frame(width: 240).multilineTextAlignment(.trailing)
                }
                Toggle("Złote litery", isOn: goldBinding)
                    .disabled((model.values["name"] ?? "").isEmpty)
                Text("Złote litery to znaki 128–255 charsetu Quake'a — działają tylko w silnikach z oryginalnym charsetem. Gra wyświetla wyłącznie ASCII, polskie znaki pojawią się jako „?”.")
                    .font(.caption).foregroundStyle(.secondary)
                // puste pole = gra użyje domyślnego "player", więc tak też pokazujemy podgląd
                QuakeTextPreview(text: (model.values["name"] ?? "").isEmpty ? "player" : model.values["name"]!,
                                 font: model.font)
                if model.font == nil {
                    Text("Nie znalazłem czcionki gry w id1/pak0.pak — podgląd zastępczy.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Po wczytaniu konfigu") {
                Toggle("Pokaż komunikat w konsoli", isOn: Binding(
                    get: { model.greeting },
                    set: { model.greeting = $0; model.dirty = true }
                ))
                Text("Linia `echo` na końcu autoexec.cfg — potwierdza, że konfig się wykonał. Widoczna w konsoli (klawisz ~).")
                    .font(.caption).foregroundStyle(.secondary)
                if model.greeting {
                    QuakeTextPreview(text: model.greetingText(), font: model.font, scale: 2)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct KeyCap: View {
    @ObservedObject var model: ConfigModel
    let key: KeyDef
    @Binding var selectedKeyID: String?

    private static let unit: CGFloat = 30
    private static let spacing: CGFloat = 3

    private var capWidth: CGFloat {
        Self.unit * key.width + Self.spacing * (key.width - 1)
    }

    var body: some View {
        if key.isGap {
            Color.clear.frame(width: capWidth, height: 30)
        } else {
            let command = key.quake.map { model.command(forKey: $0) } ?? ""
            Button {
                if key.quake != nil { selectedKeyID = key.id }
            } label: {
                Text(key.label)
                    .font(.system(size: 10, weight: .medium))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .frame(width: capWidth, height: 30)
            }
            .buttonStyle(.plain)
            .background(capColor(command), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary))
            .opacity(key.quake == nil ? 0.35 : 1)
            .help(helpText(command))
            .popover(isPresented: Binding(
                get: { selectedKeyID == key.id },
                set: { if !$0 { selectedKeyID = nil } }
            ), arrowEdge: .bottom) {
                KeyPopover(model: model, keyDef: key)
            }
        }
    }

    private func capColor(_ command: String) -> AnyShapeStyle {
        if let color = categoryColor(for: command) {
            return AnyShapeStyle(color.opacity(0.55))
        }
        return AnyShapeStyle(.quaternary.opacity(0.5))
    }

    private func helpText(_ command: String) -> String {
        if key.quake == nil { return "Klawisz zarezerwowany (menu / konsola)" }
        return command.isEmpty ? "Wolny klawisz — kliknij, aby przypisać" : command
    }
}

struct KeyPopover: View {
    @ObservedObject var model: ConfigModel
    let keyDef: KeyDef

    var body: some View {
        let quake = keyDef.quake ?? ""
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(keyDef.label).font(.headline)
                Text(quake).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            TextField("komenda (puste = wolny klawisz)", text: model.commandBinding(forKey: quake))
                .frame(width: 270)
            Menu("Typowe komendy") {
                ForEach(COMMAND_GROUPS, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.commands, id: \.cmd) { command in
                            Button("\(command.label)  —  \(command.cmd)") {
                                model.setBind(key: quake, command: command.cmd)
                            }
                        }
                    }
                }
            }
            if !model.command(forKey: quake).isEmpty {
                Button("Uwolnij klawisz", role: .destructive) {
                    model.setBind(key: quake, command: "")
                }
            }
        }
        .padding(12)
    }
}

struct BindsTab: View {
    @ObservedObject var model: ConfigModel
    @State private var selectedKeyID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            legend
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 3) {
                    ForEach(KEYBOARD_ROWS.indices, id: \.self) { row in
                        HStack(spacing: 3) {
                            ForEach(KEYBOARD_ROWS[row]) { key in
                                KeyCap(model: model, key: key, selectedKeyID: $selectedKeyID)
                            }
                        }
                    }
                }
                VStack(spacing: 3) {
                    ForEach(SIDE_ROWS.indices, id: \.self) { row in
                        HStack(spacing: 3) {
                            ForEach(SIDE_ROWS[row]) { key in
                                KeyCap(model: model, key: key, selectedKeyID: $selectedKeyID)
                            }
                        }
                    }
                    Spacer().frame(height: 30)
                    KeyCap(model: model, key: ARROW_KEYS.up, selectedKeyID: $selectedKeyID)
                    HStack(spacing: 3) {
                        KeyCap(model: model, key: ARROW_KEYS.left, selectedKeyID: $selectedKeyID)
                        KeyCap(model: model, key: ARROW_KEYS.down, selectedKeyID: $selectedKeyID)
                        KeyCap(model: model, key: ARROW_KEYS.right, selectedKeyID: $selectedKeyID)
                    }
                }
            }
            HStack(spacing: 3) {
                Text("Mysz:").font(.caption).frame(width: 44, alignment: .leading)
                ForEach(MOUSE_KEYS) { key in
                    KeyCap(model: model, key: key, selectedKeyID: $selectedKeyID)
                }
            }
            Divider()
            Text("Wszystkie bindy (także klawisze spoza rysunku):").font(.callout)
            List {
                ForEach($model.binds) { $bind in
                    HStack {
                        TextField("klawisz", text: $bind.key).frame(width: 120)
                        TextField("komenda", text: $bind.command)
                        Button {
                            model.binds.removeAll { $0.id == bind.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .onChange(of: model.binds) { model.dirty = true }
            Button("Dodaj bind") { model.binds.append(BindEntry(key: "", command: "")) }
        }
        .padding(12)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(COMMAND_GROUPS, id: \.name) { group in
                Label(group.name, systemImage: "circle.fill")
                    .font(.caption).foregroundStyle(group.color)
            }
            Label("Własne", systemImage: "circle.fill").font(.caption).foregroundStyle(.purple)
            Spacer()
            Text("Kliknij klawisz, aby przypisać komendę").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct AdvancedTab: View {
    @ObservedObject var model: ConfigModel

    var body: some View {
        VSplitView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Własne komendy (zachowywane przy zapisie):").font(.callout)
                TextEditor(text: $model.customText)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: model.customText) { model.dirty = true }
            }
            .padding(10)
            VStack(alignment: .leading, spacing: 4) {
                Text("Podgląd pliku autoexec.cfg:").font(.callout)
                ScrollView {
                    Text(model.configText())
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(.quaternary.opacity(0.4))
            }
            .padding(10)
        }
    }
}

struct ConfigView: View {
    @StateObject private var model = ConfigModel()

    var body: some View {
        VStack(spacing: 0) {
            if model.baseDir == nil {
                setupView
            } else {
                headerBar
                Divider()
                TabView {
                    OptionsTab(model: model, sections: ["Mysz", "Ruch", "Widok"])
                        .tabItem { Text("Sterowanie") }
                    OptionsTab(model: model, sections: ["Tryb wideo", "Grafika"])
                        .tabItem { Text("Obraz") }
                    OptionsTab(model: model, sections: ["HUD", "Dźwięk"])
                        .tabItem { Text("HUD i dźwięk") }
                    BindsTab(model: model)
                        .tabItem { Text("Bindy") }
                    PlayerTab(model: model)
                        .tabItem { Text("Gracz") }
                    AdvancedTab(model: model)
                        .tabItem { Text("Zaawansowane") }
                }
                statusBar
            }
        }
        .frame(minWidth: 780, minHeight: 620)
    }

    private var setupView: some View {
        VStack(spacing: 12) {
            Text("Wskaż katalog Quake'a").font(.title2)
            Text("Katalog zawierający id1 i katalogi modów.").foregroundStyle(.secondary)
            Button("Wybierz katalog…") { pickBaseDir() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerBar: some View {
        HStack {
            Text("Konfig dla:")
            Picker("", selection: Binding(get: { model.selectedDir }, set: { model.switchDir(to: $0) })) {
                ForEach(model.gameDirs, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().frame(width: 160)
            .help("Mission packi i mody bez własnego autoexec.cfg dziedziczą ten z id1.")
            Button("Zmień katalog…") { pickBaseDir() }
            Spacer()
            Button("Przywróć domyślne") { model.resetDefaults() }
            Button("Zapisz") { model.save() }
                .keyboardShortcut("s")
                .buttonStyle(.borderedProminent)
        }
        .padding(10)
    }

    private var statusBar: some View {
        HStack {
            Text(model.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Spacer()
            if model.dirty {
                Text("● niezapisane zmiany").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
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
}

@main
struct QuakeConfigApp: App {
    init() {
        // wyłącz "inteligentne" podmiany macOS w polach tekstowych — komendy Quake'a
        // wymagają prostych cudzysłowów i myślników (zapis do domeny aplikacji
        // wygrywa z ustawieniem systemowym)
        UserDefaults.standard.set(false, forKey: "NSAutomaticQuoteSubstitutionEnabled")
        UserDefaults.standard.set(false, forKey: "NSAutomaticDashSubstitutionEnabled")
    }

    var body: some Scene {
        WindowGroup("Quake Config Editor") {
            ConfigView()
        }
    }
}
