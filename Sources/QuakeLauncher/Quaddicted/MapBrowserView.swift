import SwiftUI

// MARK: - Quaddicted: widoki

struct MapBrowserView: View {
    @ObservedObject var launcher: LauncherModel
    @ObservedObject var browser: BrowserModel
    @ObservedObject var registry: InstallRegistry
    @State private var selectedID: String?
    @State private var sortOrder = [KeyPathComparator(\MapPackage.sortDate, order: .reverse)]

    private var filtered: [MapPackage] {
        browser.filtered(launcher: launcher).sorted(using: sortOrder)
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 8) {
                HStack {
                    TextField("Szukaj (tytuł, autor, id)…", text: $browser.searchText)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $browser.kindFilter) {
                        ForEach(PackageKind.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().frame(width: 130)
                    .help("Baza Quaddicted zawiera nie tylko mapy — także mody, epizody i jamy.")
                    Toggle("Zainstalowane", isOn: $browser.onlyInstalled)
                    Button {
                        Task { await browser.load(force: true) }
                    } label: { Image(systemName: "arrow.clockwise") }
                        .help("Odśwież bazę z Quaddicted")
                        .disabled(browser.loading)
                }
                .padding([.top, .horizontal], 10)

                Table(filtered, selection: $selectedID, sortOrder: $sortOrder) {
                    TableColumn("Tytuł", value: \.title) { pkg in
                        HStack(spacing: 4) {
                            if browser.isInstalled(pkg, launcher: launcher) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                            Text(pkg.title.isEmpty ? pkg.id : pkg.title)
                        }
                    }
                    TableColumn("Autor", value: \.author)
                    TableColumn("Rodzaj", value: \.kindText) { Text($0.kindText) }.width(110)
                    TableColumn("Data", value: \.sortDate) { Text($0.date) }.width(80)
                    TableColumn("Pobrano", value: \.installedSort) { pkg in
                        Text(pkg.installedText)
                            .foregroundStyle(pkg.installedAt == nil ? .secondary : .primary)
                    }
                    .width(85)
                    TableColumn("Ocena", value: \.rating) { Text($0.stars) }.width(70)
                }

                HStack {
                    if browser.loading { ProgressView().controlSize(.small) }
                    Text(browser.statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text("\(filtered.count) z \(browser.packages.count)").font(.caption).foregroundStyle(.secondary)
                }
                .padding([.bottom, .horizontal], 10)
            }
            .frame(minWidth: 440)

            Group {
                if let pkg = filtered.first(where: { $0.id == selectedID })
                    ?? browser.packages.first(where: { $0.id == selectedID }) {
                    PackageDetail(launcher: launcher, browser: browser, registry: registry, pkg: pkg)
                } else {
                    Text("Wybierz mapę z listy").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 340)
        }
        .frame(minWidth: 920, minHeight: 560)
        .task {
            // kolejność ma znaczenie: najpierw to, co zna dysk, potem odzysk z katalogów,
            // a na końcu zrzut scalonego stanu z powrotem na dysk
            browser.loadInstallHistory(launcher: launcher)
            browser.backfillInstallDates(launcher: launcher)
            browser.saveInstallHistory(launcher: launcher)
            await browser.loadIfNeeded()
            // tagi paczek znamy dopiero po wczytaniu indeksu
            browser.backfillFromIndex(registry: registry, launcher: launcher)
        }
    }
}
