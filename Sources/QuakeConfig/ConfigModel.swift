import SwiftUI

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
