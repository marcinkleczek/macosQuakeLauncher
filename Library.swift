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
                         map: entry.maps.count == 1 ? entry.maps[0] : nil,
                         baseMod: entry.requiresMod)
    }
}

// MARK: - Przeglądarka SlipSeer

struct SlipSeerView: View {
    @ObservedObject var launcher: LauncherModel
    @ObservedObject var browser: SlipSeerModel
    @ObservedObject var registry: InstallRegistry

    @State private var selection: String?
    @State private var sortOrder = [KeyPathComparator(\SlipSeerResource.updatedSort, order: .reverse)]

    private var rows: [SlipSeerResource] {
        browser.filtered(registry: registry).sorted(using: sortOrder)
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 8) {
                HStack {
                    TextField("Szukaj na SlipSeer…", text: $browser.searchText)
                        .textFieldStyle(.roundedBorder)
                    Toggle("Bez narzędzi", isOn: $browser.hideTooling)
                        .help("Ukrywa narzędzia, tekstury i modele — rzeczy, których nie instaluje się jako mod.")
                    Button {
                        Task { await browser.load(force: true) }
                    } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(browser.loading)
                }
                .padding([.top, .horizontal], 10)

                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Tytuł", value: \.title) { res in
                        HStack(spacing: 4) {
                            if registry.isInstalled(.slipseer, res.slug) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                            Text(res.title.isEmpty ? res.name : res.title).lineLimit(1)
                        }
                    }
                    .width(min: 200, ideal: 300)
                    TableColumn("Autor", value: \.author) { Text($0.author).lineLimit(1) }.width(100)
                    TableColumn("Kategoria", value: \.category) { Text($0.category).lineLimit(1) }.width(115)
                    TableColumn("Data", value: \.updatedSort) { Text($0.updatedText) }.width(90)
                    TableColumn("Pobrano", value: \.installedSort) { res in
                        Text(res.installedText)
                            .foregroundStyle(res.installedAt == nil ? .secondary : .primary)
                    }
                    .width(90)
                }

                HStack {
                    if browser.loading { ProgressView().controlSize(.small) }
                    Text(browser.statusText).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    Text("\(rows.count) z \(browser.resources.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding([.bottom, .horizontal], 10)
            }
            .frame(minWidth: 640)

            Group {
                if let res = rows.first(where: { $0.slug == selection })
                    ?? browser.resources.first(where: { $0.slug == selection }) {
                    detail(res)
                } else {
                    Text("Wybierz pozycję z listy")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 300)
        }
        .frame(minWidth: 1020, minHeight: 520)
        .task { await browser.loadIfNeeded() }
    }

    @ViewBuilder private func detail(_ res: SlipSeerResource) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(res.title.isEmpty ? res.name : res.title).font(.title3).bold()
                Text([res.author, res.category, res.updatedText].filter { !$0.isEmpty && $0 != "—" }
                    .joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)

                if let icon = res.iconURL {
                    AsyncImage(url: icon) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .frame(maxHeight: 200)
                }

                HStack {
                    if browser.installing.contains(res.slug) {
                        ProgressView().controlSize(.small)
                        Text("Instaluję…").font(.caption)
                    } else if let entry = registry.entry(.slipseer, res.slug) {
                        if launcher.canRun(gameDir: entry.gameDir) {
                            Button("Graj ▶") { launcher.runGame(gameDir: entry.gameDir, map: entry.maps.count == 1 ? entry.maps[0] : nil) }
                                .buttonStyle(.borderedProminent)
                            if entry.maps.count > 1 {
                                Menu("mapa ▾") {
                                    ForEach(entry.maps, id: \.self) { map in
                                        Button(map) { launcher.runGame(gameDir: entry.gameDir, map: map) }
                                    }
                                }
                                .frame(width: 90)
                            }
                        } else {
                            Text("nie do odpalenia")
                                .font(.caption).foregroundStyle(.orange)
                                .help("W katalogu \(entry.gameDir ?? "—") nie ma pak/progs.dat/maps — to może być zasób, nie mod.")
                        }
                        Label("pobrane \(entry.dateText)", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    } else {
                        Button("Pobierz i zainstaluj") {
                            Task { await browser.install(res, launcher: launcher, registry: registry) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                    Link("SlipSeer ↗", destination: res.pageURL)
                }

                if res.isTooling {
                    Label("To narzędzie/zasób, nie mod do katalogu gry.", systemImage: "wrench.and.screwdriver")
                        .font(.caption).foregroundStyle(.orange)
                }
                if !res.summary.isEmpty {
                    Text(res.summary).font(.callout)
                }
                if !res.descriptionText.isEmpty {
                    Divider()
                    Text(res.descriptionText).textSelection(.enabled)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: res.slug) { await browser.ensureDetail(res.slug) }
    }
}
