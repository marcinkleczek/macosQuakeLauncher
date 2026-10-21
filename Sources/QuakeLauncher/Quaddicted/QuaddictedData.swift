import SwiftUI

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
