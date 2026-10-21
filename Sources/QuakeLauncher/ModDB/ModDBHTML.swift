import SwiftUI

// MARK: - Parser HTML

enum ModDBHTML {
    /// Czy to strona blokująca, a nie zwykła treść.
    ///
    /// Uwaga na fałszywe trafienia: Cloudflare wstrzykuje `/cdn-cgi/challenge-platform/…`
    /// w KAŻDĄ chronioną stronę, także po pomyślnej weryfikacji. Sprawdzanie tego ciągu
    /// sprawiało, że każde pobranie uchodziło za challenge — launcher czekał 90 s na
    /// kliknięcie, którego nie było o co prosić, i kończył timeoutem, a lista modów
    /// zostawała na wiecznie nieodświeżanym cache. Zostają markery samego interstycjału.
    static func isCloudflare(_ html: String) -> Bool {
        let lower = html.lowercased()
        return lower.contains("just a moment")
            || lower.contains("window._cf_chl")
            || lower.contains("cf_chl_opt")
            || lower.contains("checking your browser")
    }

    static func listing(_ html: String) -> [ModDBMod] {
        let scope = slice(html, after: "id=\"modsbrowse\">", before: "class=\"pagination") ?? html
        guard let rowRe = try? NSRegularExpression(
            pattern: "<div class=\"row rowcontent[^\"]*\">(.*?)</div>\\s*</div>",
            options: .dotMatchesLineSeparators)
        else { return [] }

        var result: [ModDBMod] = []
        var seen = Set<String>()
        for match in rowRe.matches(in: scope, range: ns(scope)) {
            let row = slice(scope, match, 1)
            guard let slug = first(row, "href=\"/mods/([^\"/?#]+)\"") else { continue }
            guard seen.insert(slug).inserted else { continue }
            var mod = ModDBMod(slug: slug)
            mod.title = QuaddictedIndex.stripTags(first(row, "<h4><a[^>]*>(.*?)</a></h4>") ?? slug)
            mod.summary = QuaddictedIndex.stripTags(first(row, "<p>(.*?)</p>") ?? "")
            if let src = first(row, "<img src=\"([^\"]+)\"") { mod.thumbnailURL = URL(string: src) }
            let times = all(row, "<time datetime=\"([^\"]+)\"")
            if let first = times.first { mod.updated = parseTime(first) }
            if times.count > 1 { mod.released = parseTime(times[1]) }
            // Subheading to jeden ciąg w rodzaju „Released 2003 First Person Shooter".
            // Podział po dwóch spacjach nie działał, bo stripTags zostawia pojedyncze —
            // status wchłaniał cały tekst, a gatunek zostawał pusty. Tniemy po wzorcu statusu.
            let sub = QuaddictedIndex.stripTags(first(row, "class=\"subheading\">(.*?)</span>") ?? "")
            // „Coming Soon" przed „Coming" — inaczej alternatywa urwałaby się na pierwszym słowie.
            // Po słowie statusu bierzemy też datę („Released Aug 14, 2026" albo „Released 1997"),
            // inaczej wpadała do gatunku i kolumna pokazywała „Aug 14, 2026 First Person Shooter".
            if let head = first(sub, #"^((?:Released|Releasing|Coming Soon|Coming|Early Access|TBD)(?:\s+\w{3}\s+\d{1,2},\s*\d{4}|\s+\d{4})?)"#) {
                mod.status = head.trimmingCharacters(in: .whitespaces)
                mod.genre = String(sub.dropFirst(head.count)).trimmingCharacters(in: .whitespaces)
            } else {
                mod.genre = sub
            }
            result.append(mod)
        }
        return result
    }

    static func listingTotal(_ html: String) -> Int? {
        first(html, #"of (\d+)"#).flatMap(Int.init)
    }

    static func listingPages(_ html: String) -> Int {
        let nums = all(html, "/mods/page/(\\d+)").compactMap(Int.init)
        if let max = nums.max(), max > 0 { return max }
        if let total = listingTotal(html) { return max(1, (total + 29) / 30) }
        return 1
    }

    static func files(in html: String, slug: String) -> [ModDBFile] {
        let escaped = NSRegularExpression.escapedPattern(for: slug)
        let scope = slice(html, after: "class=\"heading\">Files", before: "id=\"comments\"") ?? html
        guard let rowRe = try? NSRegularExpression(
            pattern: "<div class=\"row rowcontent[^\"]*\">(.*?)</div>\\s*</div>",
            options: .dotMatchesLineSeparators)
        else { return [] }

        var result: [ModDBFile] = []
        var seen = Set<String>()
        let hrefRe = "href=\"/mods/\(escaped)/downloads/([^\"/?#]+)\""
        for match in rowRe.matches(in: scope, range: ns(scope)) {
            let row = slice(scope, match, 1)
            guard let fileSlug = first(row, hrefRe), fileSlug != "add" else { continue }
            guard seen.insert(fileSlug).inserted else { continue }
            var file = ModDBFile(slug: fileSlug)
            file.title = QuaddictedIndex.stripTags(first(row, "<h4><a[^>]*>(.*?)</a></h4>") ?? fileSlug)
            file.date = QuaddictedIndex.stripTags(first(row, "<time[^>]*>(.*?)</time>") ?? "")
            file.category = QuaddictedIndex.stripTags(first(row, "class=\"subheading\">(.*?)</span>") ?? "")
            file.summary = QuaddictedIndex.stripTags(first(row, "<p>(.*?)</p>") ?? "")
            if let src = first(row, "<img src=\"([^\"]+)\"") {
                file.imageURL = URL(string: src)
                file.fileID = idFromMediaPath(src)
            }
            result.append(file)
        }
        return result
    }

    static func applyDetail(to mod: inout ModDBMod, html: String) {
        if let title = first(html, "property=\"og:title\" content=\"([^\"]+)\"") {
            let cleaned = title.replacingOccurrences(of: " mod for Quake", with: "")
            if !cleaned.isEmpty { mod.title = QuaddictedIndex.stripTags(cleaned) }
        }
        if let desc = first(html, "property=\"og:description\" content=\"([^\"]+)\"")
            ?? first(html, "name=\"description\" content=\"([^\"]+)\"") {
            mod.descriptionText = QuaddictedIndex.stripTags(desc)
        }
        if let img = first(html, "property=\"og:image\" content=\"([^\"]+)\"") {
            mod.screenshotURL = URL(string: img)
        }
        if let author = first(html, "<h5>Creator</h5>.*?itemprop=\"name\">(.*?)</span>")
            ?? first(html, "<h5>Creator</h5>.*?<a[^>]*>(.*?)</a>") {
            mod.author = QuaddictedIndex.stripTags(author)
        }
        if let value = first(html, "itemprop=\"ratingValue\" content=\"([0-9.]+)\"") {
            mod.rating = Double(value) ?? 0
        }
        if let count = first(html, "itemprop=\"ratingCount\" content=\"(\\d+)\"") {
            mod.ratingCount = Int(count) ?? 0
        }
        let files = files(in: html, slug: mod.slug)
        if !files.isEmpty { mod.files = files }
        mod.detailLoaded = true
    }

    static func applyFilePage(to file: inout ModDBFile, html: String) {
        if let name = labeled(html, "Filename") { file.filename = name }
        if let hash = labeled(html, "MD5 Hash") { file.md5 = hash.lowercased() }
        if let size = labeled(html, "Size"),
           let bytes = first(size, "\\(([0-9,]+)\\s*bytes\\)") ?? first(size, "\\(([0-9,]+)") {
            file.sizeBytes = Int(bytes.replacingOccurrences(of: ",", with: "")) ?? 0
        }
        if let cat = first(html, "<h5>Category</h5>.*?<a[^>]*>(.*?)</a>") {
            file.category = QuaddictedIndex.stripTags(cat)
        }
        if let id = first(html, "/downloads/start/(\\d+)") ?? first(html, "siteareaid=(\\d+)") {
            file.fileID = Int(id)
        }
        if file.fileID == nil, let src = first(html, "images/downloads/\\d+/\\d+/(\\d+)/") {
            file.fileID = Int(src)
        }
    }

    static func mirrorURL(in html: String, filename: String?) -> URL? {
        if let path = first(html, "href=\"(/downloads/mirror/[^\"]+)\""),
           let url = URL(string: "https://www.moddb.com" + path) {
            return url
        }
        if let filename, !filename.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: filename)
            if let path = first(html, "href=\"([^\"]+)\"[^>]*>\\s*download\\s+\(escaped)"),
               let url = absolute(path) {
                return url
            }
        }
        if let path = first(html, "href=\"([^\"]+)\"[^>]*>\\s*download\\s+", options: [.caseInsensitive]),
           let url = absolute(path) {
            return url
        }
        return nil
    }

    static func preferredFile(_ files: [ModDBFile]) -> ModDBFile? {
        let skip = files.filter {
            let c = $0.category.lowercased()
            return !c.contains("tutorial") && !c.contains("source")
        }
        let pool = skip.isEmpty ? files : skip
        if let full = pool.first(where: { $0.category.lowercased().contains("full") }) { return full }
        if let zip = pool.first(where: { $0.ext == "zip" || $0.filename.lowercased().hasSuffix(".zip") }) { return zip }
        return pool.first
    }

    static func idFromMediaPath(_ src: String) -> Int? {
        first(src, "images/downloads/\\d+/\\d+/(\\d+)/").flatMap(Int.init)
    }

    // MARK: drobne

    private static func labeled(_ html: String, _ label: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: label)
        return first(html, "<h5>\\s*\(escaped)\\s*</h5>\\s*<span[^>]*>(.*?)</span>")
            .map { QuaddictedIndex.stripTags($0) }
    }

    private static func parseTime(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        if raw.count >= 10 {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd"
            return df.date(from: String(raw.prefix(10)))
        }
        return nil
    }

    private static func absolute(_ path: String) -> URL? {
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: path.hasPrefix("/") ? "https://www.moddb.com\(path)" : "https://www.moddb.com/\(path)")
    }

    private static func slice(_ html: String, after: String, before: String) -> String? {
        guard let a = html.range(of: after) else { return nil }
        let rest = html[a.upperBound...]
        guard let b = rest.range(of: before) else { return String(rest) }
        return String(rest[..<b.lowerBound])
    }

    private static func ns(_ s: String) -> NSRange { NSRange(s.startIndex..., in: s) }

    private static func slice(_ s: String, _ match: NSTextCheckingResult, _ group: Int) -> String {
        let range = match.range(at: group)
        guard let swift = Range(range, in: s) else { return "" }
        return String(s[swift])
    }

    static func first(_ s: String, _ pattern: String, options: NSRegularExpression.Options = [.dotMatchesLineSeparators]) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options),
              let match = re.firstMatch(in: s, range: ns(s)), match.numberOfRanges > 1
        else { return nil }
        return slice(s, match, 1)
    }

    static func all(_ s: String, _ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        return re.matches(in: s, range: ns(s)).compactMap { match in
            match.numberOfRanges > 1 ? slice(s, match, 1) : nil
        }
    }
}
