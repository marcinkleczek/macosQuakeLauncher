import Foundation

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

    /// Mapy paczki: luźne .bsp oraz maps/*.bsp wewnątrz paków. Stare mody (np. Nike)
    /// trzymają wszystkie mapy w pak0.pak — bez tego „Graj" startował bez +map, na demach id1.
    static func bspNames(in dir: URL) -> [String] {
        var names: Set<String> = []
        guard let walker = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        for case let f as URL in walker.allObjects {
            switch f.pathExtension.lowercased() {
            case "bsp":
                names.insert(f.deletingPathExtension().lastPathComponent.lowercased())
            case "pak":
                for entry in BSPReader.pakEntries(f).keys {
                    let lower = entry.lowercased()
                    guard lower.hasPrefix("maps/"), lower.hasSuffix(".bsp"),
                          !lower.dropFirst(5).contains("/") else { continue }
                    names.insert(String(lower.dropFirst(5).dropLast(4)))
                }
            default: break
            }
        }
        return names.filter { !$0.hasPrefix("b_") }.sorted()
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
