import Foundation

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
        "monster_shalrath_x": "Vore (enhanced)",
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
        case 1: return ("Silver Runekey", "Gold Runekey")
        case 2: return ("Silver Keycard", "Gold Keycard")
        default: return ("Silver Key", "Gold Key")
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
        let styles = ["medieval", "runic (metal)", "base (tech)"]
        info.headline.append("Style: \(styles.indices.contains(worldtype) ? styles[worldtype] : "unknown (\(worldtype))")")
        info.headline.append("Entities in file: \(entities.count)")
        let skillNames = ["Easy", "Normal", "Hard", "Nightmare"]
        info.skillLabel = skillNames.indices.contains(skill) ? skillNames[skill] : "skill \(skill)"
        if !skillWasExplicit { info.skillLabel += " (default)" }

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
                                            detail: dmOnly ? "deathmatch only" : "other skill",
                                            muted: true))
            } else {
                let hidden = onMap.count - available.count
                weaponItems.append(InfoItem(label: label,
                                            detail: "\(available.count)×" + (hidden > 0 ? " (+\(hidden) on other skills)" : "")))
            }
        }
        info.sections.append(InfoSection(title: "Weapons", items: weaponItems,
                                         note: "You start with the Shotgun and Axe."))

        // — sekrety i mechanizmy —
        let buttons = all("func_button")
        let shootable = buttons.filter { $0.health > 0 }
        let secretDoors = all("func_door_secret")
        // trigger_counter zbiera N aktywacji (domyślnie 2) zanim odpali cel
        let counters = all("trigger_counter")
        var progressItems: [InfoItem] = [
            InfoItem(label: "Secrets", detail: count("trigger_secret") == 0 ? "none" : "\(count("trigger_secret"))",
                     muted: count("trigger_secret") == 0),
            InfoItem(label: "Push buttons", detail: "\(buttons.count - shootable.count)",
                     muted: buttons.count == shootable.count),
            InfoItem(label: "Shootable buttons", detail: "\(shootable.count)", muted: shootable.isEmpty),
            InfoItem(label: "Secret doors (func_door_secret)", detail: "\(secretDoors.count)", muted: secretDoors.isEmpty),
        ]
        if !counters.isEmpty {
            let needed = counters.map { Int($0.keys["count"] ?? "") ?? 2 }
            progressItems.append(InfoItem(label: "Trigger counters",
                                          detail: needed.map { "\($0)×" }.joined(separator: ", ")))
        }
        progressItems.append(InfoItem(label: "Teleporters", detail: "\(count("trigger_teleport"))",
                                      muted: count("trigger_teleport") == 0))
        let changelevels = all("trigger_changelevel").compactMap { $0.keys["map"] }
        if !changelevels.isEmpty {
            progressItems.append(InfoItem(label: "Exit leads to",
                                          detail: Array(Set(changelevels)).sorted().joined(separator: ", ")))
        }
        info.sections.append(InfoSection(title: "Secrets and mechanisms", items: progressItems,
                                         note: shootable.isEmpty ? nil : "A “shootable” button is a func_button with health > 0."))

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
            InfoItem(label: "Key doors", detail: "silver \(silverDoors), gold \(goldDoors)",
                     muted: silverDoors + goldDoors == 0),
            InfoItem(label: "Moving doors (total)", detail: "\(doors.count)", muted: doors.isEmpty),
        ]
        let runes = all("item_sigil")
        if !runes.isEmpty {
            let numbers = runes.map { entity -> String in
                // spawnflags 1/2/4/8 = runa epizodu 1–4
                let bit = entity.spawnflags
                let index = (1 ... 4).first { bit & (1 << ($0 - 1)) != 0 }
                return index.map(String.init) ?? "?"
            }
            keyItems.append(InfoItem(label: "Rune", detail: "episode \(numbers.joined(separator: ", "))"))
        }
        info.sections.append(InfoSection(title: "Keys and doors", items: keyItems))

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
        if monsterItems.isEmpty { monsterItems = [InfoItem(label: "No monsters", detail: "—", muted: true)] }
        info.sections.append(InfoSection(
            title: "Monsters — \(monsters.count) total", items: monsterItems,
            note: ambush > 0 ? "\(ambush) in ambush (they only wake on sight)." : nil))

        // — amunicja —
        // spawnflags bit 1 = duże pudełko, czyli podwójna zawartość
        func ammo(_ classname: String, small: Int) -> (boxes: Int, total: Int) {
            let boxes = all(classname)
            return (boxes.count, boxes.reduce(0) { $0 + ($1.spawnflags & 1 != 0 ? small * 2 : small) })
        }
        let ammoSpecs = [("item_shells", "Shells", 20), ("item_spikes", "Nails", 25),
                         ("item_rockets", "Rockets", 5), ("item_cells", "Cells", 6)]
        let ammoItems = ammoSpecs.map { classname, label, small -> InfoItem in
            let (boxes, total) = ammo(classname, small: small)
            return InfoItem(label: label, detail: boxes == 0 ? "—" : "\(total) in \(boxes) " + (boxes == 1 ? "box" : "boxes"), muted: boxes == 0)
        }
        info.sections.append(InfoSection(title: "Ammo", items: ammoItems,
                                         note: "Not counting backpacks dropped by killed monsters."))

        // — zdrowie i pancerz —
        let healths = all("item_health")
        let rotten = healths.filter { $0.spawnflags & 1 != 0 }.count
        let mega = healths.filter { $0.spawnflags & 2 != 0 }.count
        let normal = healths.count - rotten - mega
        var vitalItems = [
            InfoItem(label: "Health 25", detail: normal == 0 ? "—" : "\(normal)×", muted: normal == 0),
            InfoItem(label: "Health 15 (rotten)", detail: rotten == 0 ? "—" : "\(rotten)×", muted: rotten == 0),
            InfoItem(label: "Megahealth 100", detail: mega == 0 ? "—" : "\(mega)×", muted: mega == 0),
        ]
        for (classname, label) in [("item_armor1", "Green Armor (100)"),
                                   ("item_armor2", "Yellow Armor (150)"),
                                   ("item_armorInv", "Red Armor (200)")] {
            let n = count(classname)
            vitalItems.append(InfoItem(label: label, detail: n == 0 ? "—" : "\(n)×", muted: n == 0))
        }
        info.sections.append(InfoSection(title: "Health and armor", items: vitalItems))

        // — powerupy —
        let powerupItems = powerups.map { classname, label -> InfoItem in
            let n = count(classname)
            return InfoItem(label: label, detail: n == 0 ? "—" : "\(n)×", muted: n == 0)
        }
        info.sections.append(InfoSection(title: "Artifacts", items: powerupItems))

        return info
    }
}
