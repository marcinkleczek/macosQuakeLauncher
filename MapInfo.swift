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

// MARK: - Analiza zawartości mapy

struct InfoItem: Identifiable {
    let label: String
    let detail: String
    var muted = false // pozycja "brak"/nieaktywna — UI wyszarza

    var id: String { label }
}

struct InfoSection: Identifiable {
    let title: String
    let items: [InfoItem]
    var note: String?

    var id: String { title }
}

struct MapInfo {
    var title = ""
    var headline: [String] = [] // wiersze nagłówka: nie zdradzają rozgrywki
    var sections: [InfoSection] = []
    var skillLabel = ""
}

enum MapAnalyzer {
    // Kolejność jak w grze — chcemy stałej listy, także dla broni nieobecnych na mapie.
    private static let weapons: [(String, String)] = [
        ("weapon_supershotgun", "Super Shotgun"),
        ("weapon_nailgun", "Nailgun"),
        ("weapon_supernailgun", "Super Nailgun"),
        ("weapon_grenadelauncher", "Grenade Launcher"),
        ("weapon_rocketlauncher", "Rocket Launcher"),
        ("weapon_lightning", "Thunderbolt"),
    ]

    private static let monsterNames: [String: String] = [
        "monster_army": "Grunt",
        "monster_dog": "Rottweiler",
        "monster_enforcer": "Enforcer",
        "monster_ogre": "Ogre",
        "monster_ogre_marksman": "Ogre (marksman)",
        "monster_knight": "Knight",
        "monster_hell_knight": "Death Knight",
        "monster_wizard": "Scrag",
        "monster_demon1": "Fiend",
        "monster_shalrath": "Vore",
        "monster_shambler": "Shambler",
        "monster_tarbaby": "Spawn",
        "monster_fish": "Rotfish",
        "monster_zombie": "Zombie",
        "monster_boss": "Chthon (boss)",
        "monster_oldone": "Shub-Niggurath (boss)",
        // Scourge of Armagon
        "monster_armagon": "Armagon (boss)",
        "monster_gremlin": "Gremlin",
        // Dissolution of Eternity
        "monster_wrath": "Wrath",
        "monster_morph": "Morph",
        "monster_lava_man": "Lava Man",
        "monster_eel": "Electric Eel",
        "monster_mummy": "Mummy",
        "monster_hellfish": "Hell Fish",
        "monster_shalrath_x": "Vore (wzmocniony)",
    ]

    private static let powerups: [(String, String)] = [
        ("item_artifact_super_damage", "Quad Damage"),
        ("item_artifact_invulnerability", "Pentagram of Protection"),
        ("item_artifact_invisibility", "Ring of Shadows"),
        ("item_artifact_envirosuit", "Biosuit"),
    ]

    /// Nazwy kluczy zależą od stylu mapy (worldspawn "worldtype").
    private static func keyNames(worldtype: Int) -> (String, String) {
        switch worldtype {
        case 1: return ("Srebrny runekey", "Złoty runekey")
        case 2: return ("Srebrna karta", "Złota karta")
        default: return ("Srebrny klucz", "Złoty klucz")
        }
    }

    static func analyze(_ entities: [MapEntity], skill: Int, skillWasExplicit: Bool) -> MapInfo {
        var info = MapInfo()
        let world = entities.first { $0.classname == "worldspawn" } ?? entities.first
        let live = entities.filter { $0.spawns(skill: skill) }

        func count(_ classname: String) -> Int { live.filter { $0.classname == classname }.count }
        func all(_ classname: String) -> [MapEntity] { live.filter { $0.classname == classname } }

        // — nagłówek: informacje o samej mapie, nie o jej zawartości —
        info.title = world?.keys["message"] ?? ""
        let worldtype = Int(world?.keys["worldtype"] ?? "") ?? 0
        let styles = ["średniowieczna", "runiczna (metal)", "baza (elektro)"]
        info.headline.append("Styl: \(styles.indices.contains(worldtype) ? styles[worldtype] : "nieznany (\(worldtype))")")
        info.headline.append("Encji w pliku: \(entities.count)")
        let skillNames = ["Easy", "Normal", "Hard", "Nightmare"]
        info.skillLabel = skillNames.indices.contains(skill) ? skillNames[skill] : "skill \(skill)"
        if !skillWasExplicit { info.skillLabel += " (domyślny)" }

        // — bronie —
        var weaponItems: [InfoItem] = []
        for (classname, label) in weapons {
            let onMap = entities.filter { $0.classname == classname }
            let available = onMap.filter { $0.spawns(skill: skill) }
            if onMap.isEmpty {
                weaponItems.append(InfoItem(label: label, detail: "—", muted: true))
            } else if available.isEmpty {
                let dmOnly = onMap.allSatisfy(\.deathmatchOnly)
                weaponItems.append(InfoItem(label: label,
                                            detail: dmOnly ? "tylko deathmatch" : "inny poziom trudności",
                                            muted: true))
            } else {
                let hidden = onMap.count - available.count
                weaponItems.append(InfoItem(label: label,
                                            detail: "\(available.count)×" + (hidden > 0 ? " (+\(hidden) poza tym skillem)" : "")))
            }
        }
        info.sections.append(InfoSection(title: "Bronie", items: weaponItems,
                                         note: "Shotgun i topór masz od startu."))

        // — sekrety i mechanizmy —
        let buttons = all("func_button")
        let shootable = buttons.filter { $0.health > 0 }
        let secretDoors = all("func_door_secret")
        // trigger_counter zbiera N aktywacji (domyślnie 2) zanim odpali cel
        let counters = all("trigger_counter")
        var progressItems: [InfoItem] = [
            InfoItem(label: "Sekrety", detail: count("trigger_secret") == 0 ? "brak" : "\(count("trigger_secret"))",
                     muted: count("trigger_secret") == 0),
            InfoItem(label: "Przyciski do wciśnięcia", detail: "\(buttons.count - shootable.count)",
                     muted: buttons.count == shootable.count),
            InfoItem(label: "Przyciski do wystrzelenia", detail: "\(shootable.count)", muted: shootable.isEmpty),
            InfoItem(label: "Ukryte drzwi (func_door_secret)", detail: "\(secretDoors.count)", muted: secretDoors.isEmpty),
        ]
        if !counters.isEmpty {
            let needed = counters.map { Int($0.keys["count"] ?? "") ?? 2 }
            progressItems.append(InfoItem(label: "Liczniki wyzwalaczy",
                                          detail: needed.map { "\($0)×" }.joined(separator: ", ")))
        }
        progressItems.append(InfoItem(label: "Teleporty", detail: "\(count("trigger_teleport"))",
                                      muted: count("trigger_teleport") == 0))
        let changelevels = all("trigger_changelevel").compactMap { $0.keys["map"] }
        if !changelevels.isEmpty {
            progressItems.append(InfoItem(label: "Wyjście prowadzi do",
                                          detail: Array(Set(changelevels)).sorted().joined(separator: ", ")))
        }
        info.sections.append(InfoSection(title: "Sekrety i mechanizmy", items: progressItems,
                                         note: shootable.isEmpty ? nil : "Przycisk „do wystrzelenia” to func_button z health > 0."))

        // — klucze, drzwi, runy —
        let (silver, gold) = keyNames(worldtype: worldtype)
        let doors = all("func_door")
        let silverDoors = doors.filter { $0.spawnflags & 8 != 0 }.count
        let goldDoors = doors.filter { $0.spawnflags & 16 != 0 }.count
        var keyItems: [InfoItem] = [
            InfoItem(label: silver, detail: count("item_key1") == 0 ? "—" : "\(count("item_key1"))×",
                     muted: count("item_key1") == 0),
            InfoItem(label: gold, detail: count("item_key2") == 0 ? "—" : "\(count("item_key2"))×",
                     muted: count("item_key2") == 0),
            InfoItem(label: "Drzwi na klucz", detail: "srebrne \(silverDoors), złote \(goldDoors)",
                     muted: silverDoors + goldDoors == 0),
            InfoItem(label: "Drzwi ruchome łącznie", detail: "\(doors.count)", muted: doors.isEmpty),
        ]
        let runes = all("item_sigil")
        if !runes.isEmpty {
            let numbers = runes.map { entity -> String in
                // spawnflags 1/2/4/8 = runa epizodu 1–4
                let bit = entity.spawnflags
                let index = (1 ... 4).first { bit & (1 << ($0 - 1)) != 0 }
                return index.map(String.init) ?? "?"
            }
            keyItems.append(InfoItem(label: "Runa", detail: "epizod \(numbers.joined(separator: ", "))"))
        }
        info.sections.append(InfoSection(title: "Klucze i drzwi", items: keyItems))

        // — potwory —
        let monsters = live.filter { $0.classname.hasPrefix("monster_") }
        let byClass: [String: [MapEntity]] = Dictionary(grouping: monsters, by: { $0.classname })
        var grouped: [(name: String, count: Int)] = []
        for (classname, group) in byClass {
            grouped.append((monsterNames[classname] ?? classname, group.count))
        }
        grouped.sort { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
        let ambush = monsters.filter { $0.spawnflags & 1 != 0 }.count
        var monsterItems = grouped.map { InfoItem(label: $0.name, detail: "\($0.count)×") }
        if monsterItems.isEmpty { monsterItems = [InfoItem(label: "Brak potworów", detail: "—", muted: true)] }
        info.sections.append(InfoSection(
            title: "Potwory — razem \(monsters.count)", items: monsterItems,
            note: ambush > 0 ? "\(ambush) w zasadzce (budzą się dopiero gdy je zobaczysz)." : nil))

        // — amunicja —
        // spawnflags bit 1 = duże pudełko, czyli podwójna zawartość
        func ammo(_ classname: String, small: Int) -> (boxes: Int, total: Int) {
            let boxes = all(classname)
            return (boxes.count, boxes.reduce(0) { $0 + ($1.spawnflags & 1 != 0 ? small * 2 : small) })
        }
        let ammoSpecs = [("item_shells", "Naboje (shells)", 20), ("item_spikes", "Gwoździe (nails)", 25),
                         ("item_rockets", "Rakiety", 5), ("item_cells", "Ogniwa (cells)", 6)]
        let ammoItems = ammoSpecs.map { classname, label, small -> InfoItem in
            let (boxes, total) = ammo(classname, small: small)
            return InfoItem(label: label, detail: boxes == 0 ? "—" : "\(total) szt. w \(boxes) pudełkach", muted: boxes == 0)
        }
        info.sections.append(InfoSection(title: "Amunicja", items: ammoItems,
                                         note: "Nie licząc plecaków po zabitych potworach."))

        // — zdrowie i pancerz —
        let healths = all("item_health")
        let rotten = healths.filter { $0.spawnflags & 1 != 0 }.count
        let mega = healths.filter { $0.spawnflags & 2 != 0 }.count
        let normal = healths.count - rotten - mega
        var vitalItems = [
            InfoItem(label: "Apteczki 25", detail: normal == 0 ? "—" : "\(normal)×", muted: normal == 0),
            InfoItem(label: "Apteczki 15 (rotten)", detail: rotten == 0 ? "—" : "\(rotten)×", muted: rotten == 0),
            InfoItem(label: "Megahealth 100", detail: mega == 0 ? "—" : "\(mega)×", muted: mega == 0),
        ]
        for (classname, label) in [("item_armor1", "Pancerz zielony (100)"),
                                   ("item_armor2", "Pancerz żółty (150)"),
                                   ("item_armorInv", "Pancerz czerwony (200)")] {
            let n = count(classname)
            vitalItems.append(InfoItem(label: label, detail: n == 0 ? "—" : "\(n)×", muted: n == 0))
        }
        info.sections.append(InfoSection(title: "Zdrowie i pancerz", items: vitalItems))

        // — powerupy —
        let powerupItems = powerups.map { classname, label -> InfoItem in
            let n = count(classname)
            return InfoItem(label: label, detail: n == 0 ? "—" : "\(n)×", muted: n == 0)
        }
        info.sections.append(InfoSection(title: "Artefakty", items: powerupItems))

        return info
    }
}
