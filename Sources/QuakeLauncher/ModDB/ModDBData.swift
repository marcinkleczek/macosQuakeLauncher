import SwiftUI
import WebKit

// MARK: - ModDB: dane
//
// ModDB nie ma publicznego API. Lista i pliki są w HTML, a właściwy bajtowy
// download idzie przez /downloads/start/<id> → /downloads/mirror/….
// Cloudflare często blokuje goły URLSession, więc przy challenge'u dokładamy
// WKWebView (ten sam silnik co Safari) i przepisujemy ciastka do sesji.

struct ModDBMod: Identifiable, Hashable, Codable {
    var slug: String
    var title = ""
    var summary = ""
    var thumbnailURL: URL?
    var screenshotURL: URL?
    var updated: Date?
    var released: Date?
    var status = ""
    var genre = ""
    var author = ""
    var rating = 0.0
    var ratingCount = 0
    var descriptionText = ""
    var files: [ModDBFile] = []
    var detailLoaded = false
    /// Kiedy pobraliśmy tego moda — wstrzykiwane z rejestru przy filtrowaniu,
    /// żeby tabela mogła po tym sortować (Table sortuje po właściwościach modelu).
    var installedAt: Date?
    var pageURL: URL { URL(string: "https://www.moddb.com/mods/\(slug)")! }
    var id: String { slug }

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

    var statusText: String {
        if !status.isEmpty { return status }
        if released != nil { return "Wydany" }
        return "—"
    }

    var isReleased: Bool {
        let s = status.lowercased()
        return s.contains("released") || s.hasPrefix("wydany")
    }

    /// Silniki / formaty, z którymi typowy QuakeSpasm sobie nie poradzi.
    var engineWarning: String? {
        let blob = "\(title) \(summary) \(descriptionText)".lowercased()
        var need: [String] = []
        if blob.contains("darkplaces") { need.append("DarkPlaces") }
        if blob.contains("fteqw") || blob.contains("fte quake") || blob.contains("ftequake")
            || blob.contains(" for fte") { need.append("FTE") }
        if blob.contains("zircon") { need.append("Zircon") }
        var notes: [String] = []
        if title.lowercased().contains("engine") || slug.contains("engine") {
            notes.append("To wygląda na silnik, nie na katalog -game — launcher rozpakuje archiwum, ale nie uruchomi tego jako moda.")
        }
        if !need.isEmpty {
            notes.append("Ten mod jest pod \(need.joined(separator: "/")) — QuakeSpasm/vkQuake mogą go nie załadować.")
        }
        return notes.isEmpty ? nil : notes.joined(separator: " ")
    }

    private static let day: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
}

struct ModDBFile: Identifiable, Hashable, Codable {
    var slug: String
    var title = ""
    var category = ""
    var date = ""
    var summary = ""
    var filename = ""
    var sizeBytes = 0
    var md5 = ""
    var fileID: Int?
    var imageURL: URL?

    var id: String { slug }

    var sizeText: String {
        guard sizeBytes > 0 else { return "" }
        if sizeBytes >= 1_048_576 { return String(format: "%.1f MB", Double(sizeBytes) / 1_048_576) }
        if sizeBytes >= 1024 { return String(format: "%.0f KB", Double(sizeBytes) / 1024) }
        return "\(sizeBytes) B"
    }

    var ext: String {
        URL(fileURLWithPath: filename.isEmpty ? slug : filename).pathExtension.lowercased()
    }

    var isArchive: Bool {
        ["zip", "7z", "rar", "tar", "gz", "tgz", "pk3", "pak"].contains(ext)
    }

    var isInstaller: Bool {
        ["exe", "msi", "dmg", "pkg", "app"].contains(ext)
    }

}
