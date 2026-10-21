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
                    TextField("Search (title, author, id)…", text: $browser.searchText)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $browser.kindFilter) {
                        ForEach(PackageKind.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().frame(width: 130)
                    .help("The Quaddicted database has more than maps — mods, episodes and jams too.")
                    Toggle("Installed", isOn: $browser.onlyInstalled)
                    Button {
                        Task { await browser.load(force: true) }
                    } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh database from Quaddicted")
                        .disabled(browser.loading)
                }
                .padding([.top, .horizontal], 10)

                Table(filtered, selection: $selectedID, sortOrder: $sortOrder) {
                    TableColumn("Title", value: \.title) { pkg in
                        HStack(spacing: 4) {
                            if browser.isInstalled(pkg, launcher: launcher) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                            Text(pkg.title.isEmpty ? pkg.id : pkg.title)
                        }
                    }
                    TableColumn("Author", value: \.author)
                    TableColumn("Type", value: \.kindText) { Text($0.kindText) }.width(110)
                    TableColumn("Released", value: \.sortDate) { Text($0.date) }.width(80)
                    TableColumn("Downloaded", value: \.installedSort) { pkg in
                        Text(pkg.installedText)
                            .foregroundStyle(pkg.installedAt == nil ? .secondary : .primary)
                    }
                    .width(85)
                    TableColumn("Rating", value: \.rating) { Text($0.stars) }.width(70)
                }

                HStack {
                    if browser.loading { ProgressView().controlSize(.small) }
                    Text(browser.statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text("\(filtered.count) of \(browser.packages.count)").font(.caption).foregroundStyle(.secondary)
                }
                .padding([.bottom, .horizontal], 10)
            }
            .frame(minWidth: 440)

            Group {
                if let pkg = filtered.first(where: { $0.id == selectedID })
                    ?? browser.packages.first(where: { $0.id == selectedID }) {
                    PackageDetail(launcher: launcher, browser: browser, registry: registry, pkg: pkg)
                } else {
                    Text("Select a map from the list").foregroundStyle(.secondary)
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
