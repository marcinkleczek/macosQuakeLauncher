import SwiftUI

// MARK: - Wspólna lista pobranych rzeczy
//
// Jedno okno na wszystkie źródła: co, skąd, kiedy i czy da się w to zagrać.
// Daty biorą się z rejestru — instalacje sprzed jego wprowadzenia mają puste pole,
// bo nikt ich wtedy nie zapisywał i nie da się tego odtworzyć.

struct LibraryView: View {
    @ObservedObject var launcher: LauncherModel
    @ObservedObject var registry: InstallRegistry

    @State private var searchText = ""
    @State private var sourceFilter: InstallSource?
    @State private var selection: String?
    @State private var sortOrder = [KeyPathComparator(\InstallEntry.sortDate, order: .reverse)]

    private var rows: [InstallEntry] {
        var result = registry.all()
        if let sourceFilter { result = result.filter { $0.source == sourceFilter } }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.displayTitle.lowercased().contains(query)
                    || $0.slug.lowercased().contains(query)
                    || ($0.gameDir ?? "").lowercased().contains(query)
            }
        }
        return result.sorted(using: sortOrder)
    }

    private var datedCount: Int { registry.all().filter { $0.date != nil }.count }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Szukaj w pobranych…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $sourceFilter) {
                    Text("Wszystkie źródła").tag(Optional<InstallSource>.none)
                    ForEach(InstallSource.allCases) { Text($0.label).tag(Optional($0)) }
                }
                .labelsHidden().frame(width: 160)
            }
            .padding([.top, .horizontal], 10)

            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Nazwa", value: \.displayTitle) { entry in
                    HStack(spacing: 4) {
                        if playable(entry) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        Text(entry.displayTitle).lineLimit(1)
                    }
                }
                TableColumn("Źródło", value: \.source.rawValue) { Text($0.source.label) }.width(90)
                TableColumn("Pobrano", value: \.sortDate) { entry in
                    Text(entry.dateText)
                        .foregroundStyle(entry.date == nil ? .secondary : .primary)
                }
                .width(90)
                TableColumn("Katalog gry", value: \.slug) { entry in
                    Text(entry.gameDir ?? "—").foregroundStyle(entry.gameDir == nil ? .secondary : .primary)
                }
                .width(130)
                TableColumn("Mapy") { entry in
                    Text(entry.maps.isEmpty ? "—" : "\(entry.maps.count)")
                        .foregroundStyle(entry.maps.isEmpty ? .secondary : .primary)
                }
                .width(50)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let entry = registry.entries[id] {
                    if playable(entry) {
                        Button("Graj") { play(entry) }
                    }
                    Button("Usuń z listy (pliki zostają)") {
                        registry.forget(entry.source, entry.slug, base: launcher.baseDir)
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first, let entry = registry.entries[id], playable(entry) { play(entry) }
            }

            HStack {
                Text(datedCount == registry.entries.count
                     ? "\(registry.entries.count) pozycji"
                     : "\(registry.entries.count) pozycji, z datą \(datedCount)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(rows.count) widocznych").font(.caption).foregroundStyle(.secondary)
            }
            .padding([.bottom, .horizontal], 10)
        }
        .frame(minWidth: 720, minHeight: 420)
        .task { registry.migrateIfNeeded(base: launcher.baseDir) }
    }

    /// Da się uruchomić tylko to, co faktycznie leży na dysku jako katalog gry.
    private func playable(_ entry: InstallEntry) -> Bool {
        guard let base = launcher.baseDir, let dir = entry.gameDir else { return false }
        return PackageFS.looksLikeGameDir(base.appendingPathComponent(launcher.actualGameDir(dir)))
    }

    private func play(_ entry: InstallEntry) {
        // pojedyncza mapa startuje wprost; przy wielu wchodzimy w menu, bo nie wiadomo, od której zacząć
        launcher.runGame(gameDir: entry.gameDir,
                         map: entry.maps.count == 1 ? entry.maps[0] : nil)
    }
}
