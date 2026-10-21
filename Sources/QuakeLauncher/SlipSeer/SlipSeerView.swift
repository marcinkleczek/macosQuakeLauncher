import SwiftUI

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
