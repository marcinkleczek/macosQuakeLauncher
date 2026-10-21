import SwiftUI

// MARK: - SlipSeer
//
// slipseer.com to XenForo z Resource Managerem: zwykły HTML, HTTP 200, bez Cloudflare —
// więc w przeciwieństwie do ModDB wystarcza URLSession. Struktura listy jest przewidywalna
// (`structItem--resource`, `js-resourceListItem-<id>`), a plik siedzi pod /download.
// Uwaga: część zasobów to nie pliki na serwerze, tylko odsyłacze na zewnętrzne hosty —
// wtedy /download odpowiada przekierowaniem na stronę WWW, a nie archiwum.

struct SlipSeerResource: Identifiable, Hashable, Codable {
    /// XenForo adresuje zasób jako "nazwa.id", np. "quake-brutalist-jam-iii.549".
    var slug: String
    var title = ""
    var author = ""
    var summary = ""
    var category = ""
    var updated: Date?
    var iconURL: URL?
    var rating = 0.0
    var descriptionText = ""
    var detailLoaded = false
    /// Data pobrania z rejestru — wstrzykiwana przy filtrowaniu, żeby tabela mogła sortować.
    var installedAt: Date?

    var id: String { slug }

    var pageURL: URL { URL(string: "https://www.slipseer.com/index.php?resources/\(slug)/")! }
    var downloadURL: URL { URL(string: "https://www.slipseer.com/index.php?resources/\(slug)/download")! }

    /// Sama nazwa bez numeru — na katalog gry i tak trafia wersja małymi literami.
    var name: String {
        guard let dot = slug.lastIndex(of: "."), slug[slug.index(after: dot)...].allSatisfy(\.isNumber)
        else { return slug }
        return String(slug[..<dot])
    }

    var updatedText: String {
        guard let updated else { return "—" }
        return Self.day.string(from: updated)
    }

    var updatedSort: Date { updated ?? .distantPast }

    var installedSort: Date { installedAt ?? .distantPast }

    var installedText: String {
        guard let installedAt else { return "—" }
        return Self.day.string(from: installedAt)
    }

    /// Kategorie SlipSeera, które nie są mapami do zainstalowania w katalogu gry.
    var isTooling: Bool {
        let c = category.lowercased()
        return c.contains("tool") || c.contains("asset") || c.contains("3d model")
            || c.contains("texture") || c.contains("sound") || c.contains("source")
    }

    /// Mody bazowe, na których stoją inne mapy — warto je mieć zanim pobierze się resztę.
    var isBaseMod: Bool {
        ["alkaline", "arcane dimensions", "copper", "quoth", "progs_dump"].contains {
            category.lowercased().contains($0)
        }
    }

    private static let day: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
}

enum SlipSeerHTML {
    static func listing(_ html: String) -> [SlipSeerResource] {
        // każdy wiersz zaczyna się markerem js-resourceListItem-<id>; tniemy po nim,
        // bo zagnieżdżone <div>y uniemożliwiają dopasowanie całego bloku regexpem
        let chunks = html.components(separatedBy: "js-resourceListItem-").dropFirst()
        var result: [SlipSeerResource] = []
        var seen = Set<String>()
        for chunk in chunks {
            guard let slug = ModDBHTML.first(chunk, #"href="/index\.php\?resources/([^"/?#&]+\.\d+)/?""#),
                  seen.insert(slug).inserted else { continue }
            var res = SlipSeerResource(slug: slug)
            res.author = ModDBHTML.first(chunk, #"data-author="([^"]*)""#) ?? ""
            if let title = ModDBHTML.first(chunk, #"class="structItem-title">\s*<a[^>]*>(.*?)</a>"#) {
                res.title = QuaddictedIndex.stripTags(title)
            }
            if let tag = ModDBHTML.first(chunk, #"class="structItem-resourceTagLine">(.*?)</div>"#) {
                res.summary = QuaddictedIndex.stripTags(tag)
            }
            if let cat = ModDBHTML.first(chunk, #"\?resources/categories/[^"]*">(.*?)</a>"#) {
                res.category = QuaddictedIndex.stripTags(cat)
            }
            if let stamp = ModDBHTML.first(chunk, #"data-timestamp="(\d+)""#), let secs = Double(stamp) {
                res.updated = Date(timeIntervalSince1970: secs)
            }
            if let icon = ModDBHTML.first(chunk, #"<img src="([^"]+resource_icons[^"]+)""#) {
                res.iconURL = URL(string: icon.replacingOccurrences(of: "&amp;", with: "&"))
            }
            if let rating = ModDBHTML.first(chunk, #"title="([0-9.]+) star"#) {
                res.rating = Double(rating) ?? 0
            }
            result.append(res)
        }
        return result
    }

    /// Ostatnia strona listy. Uwaga: w HTML link wygląda jak `?resources/&amp;page=29`,
    /// więc bezpośrednio przed „page=" stoi średnik z encji, a nie „&" — wzorzec
    /// wymagający `[?&]page=` nie trafiał niczego i lista kończyła się na pierwszej stronie.
    static func pages(_ html: String) -> Int {
        let nums = ModDBHTML.all(html, #"page=(\d+)"#).compactMap(Int.init)
            + ModDBHTML.all(html, #"page-(\d+)"#).compactMap(Int.init)
        return max(1, nums.max() ?? 1)
    }

    static func applyDetail(to res: inout SlipSeerResource, html: String) {
        if let desc = ModDBHTML.first(html, #"property="og:description" content="([^"]+)""#) {
            res.descriptionText = QuaddictedIndex.stripTags(desc)
                .replacingOccurrences(of: "&amp;", with: "&")
        }
        if res.title.isEmpty, let title = ModDBHTML.first(html, #"property="og:title" content="([^"]+)""#) {
            res.title = QuaddictedIndex.stripTags(title)
        }
        res.detailLoaded = true
    }
}
