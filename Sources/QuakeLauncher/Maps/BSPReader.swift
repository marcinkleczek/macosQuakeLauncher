import Foundation

// MARK: - Odczyt encji z pliku BSP
//
// Mapa Quake'a trzyma listę encji jako zwykły tekst w lumpie 0 pliku .bsp:
//     { "classname" "weapon_rocketlauncher" "origin" "128 64 -32" }
// Nagłówek BSP to wersja (29 dla Quake'a) albo magic "BSP2"/"2PSB" dla map
// przekraczających limity oryginalnego formatu; w każdym wariancie lump 0 jest
// pierwszą parą (offset, długość) zaraz za wersją, więc czyta się je tak samo.

/// Gdzie leży mapa: luźny plik .bsp albo wpis wewnątrz archiwum .pak.
struct MapSource: Hashable {
    let file: URL
    let offset: UInt64 // przesunięcie początku BSP w pliku (0 dla luźnego .bsp)
}

struct MapEntity {
    let keys: [String: String]

    var classname: String { keys["classname"] ?? "" }
    var spawnflags: Int { Int(keys["spawnflags"] ?? "") ?? 0 }
    var health: Int { Int(keys["health"] ?? "") ?? 0 }

    // Bity, po których silnik usuwa encję przed spawnem (world.c / ED_LoadFromFile).
    static let notEasy = 256, notMedium = 512, notHard = 1024, notDeathmatch = 2048

    /// Czy encja pojawi się w grze jednoosobowej na danym poziomie trudności.
    /// Nightmare (3) dzieli bit z Hard — silnik traktuje skill >= 2 tak samo.
    func spawns(skill: Int) -> Bool {
        let bit = skill <= 0 ? Self.notEasy : (skill == 1 ? Self.notMedium : Self.notHard)
        return spawnflags & bit == 0
    }

    /// Encja postawiona wyłącznie dla deathmatchu — w kampanii nie istnieje na żadnym skillu.
    var deathmatchOnly: Bool {
        let all = Self.notEasy | Self.notMedium | Self.notHard
        return spawnflags & all == all
    }
}

enum BSPReader {
    /// Katalog archiwum .pak: nazwa wpisu → (offset, długość).
    static func pakEntries(_ url: URL) -> [String: (offset: UInt32, length: UInt32)] {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return [:] }
        defer { try? fh.close() }
        guard let header = try? fh.read(upToCount: 12), header.count == 12,
              header.prefix(4) == Data("PACK".utf8) else { return [:] }
        let dirOffset = le32(header, header.startIndex + 4)
        let dirLength = le32(header, header.startIndex + 8)
        guard dirLength > 0, dirLength % 64 == 0, dirLength < 32_000_000,
              (try? fh.seek(toOffset: UInt64(dirOffset))) != nil,
              let dir = try? fh.read(upToCount: Int(dirLength)) else { return [:] }

        var result: [String: (UInt32, UInt32)] = [:]
        var i = dir.startIndex
        while i + 64 <= dir.endIndex {
            let raw = dir.subdata(in: i ..< i + 56)
            if let name = String(bytes: raw.prefix(while: { $0 != 0 }), encoding: .ascii) {
                result[name] = (le32(dir, i + 56), le32(dir, i + 60))
            }
            i += 64
        }
        return result
    }

    /// Wyciąga i parsuje lump encji wskazanej mapy.
    static func entities(at source: MapSource) -> [MapEntity]? {
        guard let fh = try? FileHandle(forReadingFrom: source.file) else { return nil }
        defer { try? fh.close() }
        guard (try? fh.seek(toOffset: source.offset)) != nil,
              let header = try? fh.read(upToCount: 12), header.count == 12 else { return nil }

        let magic = header.prefix(4)
        let version = le32(header, header.startIndex)
        guard version == 29 || magic == Data("BSP2".utf8) || magic == Data("2PSB".utf8) else { return nil }

        let lumpOffset = le32(header, header.startIndex + 4)
        let lumpLength = le32(header, header.startIndex + 8)
        guard lumpLength > 0, lumpLength < 16_000_000,
              (try? fh.seek(toOffset: source.offset + UInt64(lumpOffset))) != nil,
              let lump = try? fh.read(upToCount: Int(lumpLength)) else { return nil }

        // lump bywa zakończony bajtem zerowym, a teksty encji to latin-1 (nie UTF-8)
        let text = String(decoding: lump.prefix(while: { $0 != 0 }), as: UTF8.self)
        return parse(text.isEmpty ? String(decoding: lump, as: UTF8.self) : text)
    }

    /// Prosty skaner "{ "klucz" "wartość" ... }" — bez regexpów, bo lump bywa duży.
    static func parse(_ text: String) -> [MapEntity] {
        var entities: [MapEntity] = []
        var keys: [String: String] = [:]
        var pending: String?
        var inEntity = false
        var chars = text.makeIterator()

        func readQuoted(_ iter: inout String.Iterator) -> String {
            var out = ""
            while let c = iter.next(), c != "\"" { out.append(c) }
            return out
        }

        while let c = chars.next() {
            switch c {
            case "{": inEntity = true; keys = [:]; pending = nil
            case "}":
                if inEntity { entities.append(MapEntity(keys: keys)) }
                inEntity = false
            case "\"":
                guard inEntity else { break }
                let token = readQuoted(&chars)
                if let key = pending {
                    keys[key] = token
                    pending = nil
                } else {
                    pending = token
                }
            default: break
            }
        }
        return entities
    }

    private static func le32(_ data: Data, _ index: Data.Index) -> UInt32 {
        var value: UInt32 = 0
        for shift in 0 ..< 4 { value |= UInt32(data[index + shift]) << (8 * shift) }
        return value
    }
}
