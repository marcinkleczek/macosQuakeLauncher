import SwiftUI

// MARK: - Okno przeglądarki
//
// Układ jak w przeglądarce Quaddicted: tabela po lewej, szczegóły po prawej.
// ModDB dokłada dwie rzeczy, których tamta nie potrzebuje — ramkę Cloudflare
// (challenge trzeba czasem kliknąć ręcznie) i wybór pliku, bo mod ma zwykle
// kilka pozycji do pobrania: pełną wersję, patch, wersję źródłową.

struct ModDBBrowserView: View {
    @ObservedObject var launcher: LauncherModel
    @ObservedObject var browser: ModDBModel
    @ObservedObject var registry: InstallRegistry

    @State private var selection: String?
    @State private var sortOrder = [KeyPathComparator(\ModDBMod.updatedSort, order: .reverse)]

    private var rows: [ModDBMod] {
        browser.filtered(launcher: launcher, registry: registry).sorted(using: sortOrder)
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 8) {
                HStack {
                    TextField("Search ModDB…", text: $browser.searchText)
                        .textFieldStyle(.roundedBorder)
                    Toggle("Released", isOn: $browser.onlyReleased)
                    Toggle("Downloaded", isOn: $browser.onlyInstalled)
                    Button {
                        Task { await browser.load(force: true) }
                    } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh list from ModDB")
                        .disabled(browser.loading)
                }
                .padding([.top, .horizontal], 10)

                if browser.challengeVisible {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("ModDB asks for confirmation — click in the frame below.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                        ModDBWebView(client: browser.client)
                            .frame(height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                    }
                    .padding(.horizontal, 10)
                }

                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Title", value: \.title) { mod in
                        HStack(spacing: 4) {
                            if browser.isInstalled(mod, registry: registry, launcher: launcher) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                            Text(mod.title.isEmpty ? mod.slug : mod.title).lineLimit(1)
                        }
                    }
                    // tytuł potrzebuje gwarantowanego minimum — bez tego sztywne kolumny
                    // zjadały całą szerokość i zostawało „Lib…”
                    .width(min: 200, ideal: 300)
                    TableColumn("Status", value: \.status) { Text($0.statusText).lineLimit(1) }.width(150)
                    TableColumn("Genre", value: \.genre) { Text($0.genre).lineLimit(1) }.width(120)
                    TableColumn("Updated", value: \.updatedSort) { Text($0.updatedText) }.width(90)
                    TableColumn("Downloaded", value: \.installedSort) { mod in
                        Text(mod.installedText)
                            .foregroundStyle(mod.installedAt == nil ? .secondary : .primary)
                    }
                    .width(90)
                }

                HStack {
                    if browser.loading { ProgressView().controlSize(.small) }
                    Text(browser.statusText).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    Text("\(rows.count) of \(browser.mods.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding([.bottom, .horizontal], 10)
            }
            .frame(minWidth: 660)

            Group {
                if let mod = rows.first(where: { $0.slug == selection })
                    ?? browser.mods.first(where: { $0.slug == selection }) {
                    ModDBDetail(launcher: launcher, browser: browser, registry: registry, mod: mod)
                } else {
                    Text("Select a mod from the list")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 340)
        }
        .frame(minWidth: 1060, minHeight: 560)
        .task { await browser.loadIfNeeded() }
    }
}

struct ModDBDetail: View {
    @ObservedObject var launcher: LauncherModel
    @ObservedObject var browser: ModDBModel
    @ObservedObject var registry: InstallRegistry
    let mod: ModDBMod

    private var subtitle: String {
        [mod.author, mod.statusText, mod.genre, mod.updatedText]
            .filter { !$0.isEmpty && $0 != "—" }
            .joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(mod.title.isEmpty ? mod.slug : mod.title).font(.title3).bold()
                Text(subtitle).font(.caption).foregroundStyle(.secondary)

                AsyncImage(url: mod.screenshotURL ?? mod.thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 6))
                    case .failure:
                        Label("No screenshot", systemImage: "photo")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100)
                    default:
                        ProgressView().frame(maxWidth: .infinity, minHeight: 100)
                    }
                }
                .frame(maxHeight: 260)

                actions

                if let warn = mod.engineWarning {
                    Label(warn, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }

                if !mod.files.isEmpty {
                    Divider()
                    Text("DOWNLOADS").font(.caption2.bold()).foregroundStyle(.secondary)
                    ForEach(mod.files) { file in
                        fileRow(file)
                    }
                }

                if !mod.descriptionText.isEmpty {
                    Divider()
                    Text(mod.descriptionText).textSelection(.enabled)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: mod.slug) { await browser.ensureDetail(mod.slug) }
    }

    @ViewBuilder private var actions: some View {
        HStack {
            if browser.installing.contains(mod.slug) {
                ProgressView().controlSize(.small)
                Text("Installing…").font(.caption)
            } else if let entry = registry.entry(.moddb, mod.slug) {
                if launcher.canRun(gameDir: entry.gameDir) {
                    Button("Play ▶") { browser.play(mod, launcher: launcher, registry: registry) }
                        .buttonStyle(.borderedProminent)
                    if entry.maps.count > 1 {
                        Menu("map ▾") {
                            ForEach(entry.maps, id: \.self) { map in
                                Button(map) { browser.play(mod, launcher: launcher, registry: registry, map: map) }
                            }
                        }
                        .frame(width: 90)
                    }
                } else {
                    Text("not launchable").font(.caption).foregroundStyle(.orange)
                        .help("No pak/progs.dat/maps in \(entry.gameDir ?? "—").")
                }
                Label("downloaded on \(entry.dateText)", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else if !mod.detailLoaded {
                ProgressView().controlSize(.small)
                Text("Loading details…").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Download and install") {
                    Task { await browser.install(mod, file: nil, launcher: launcher, registry: registry) }
                }
                .buttonStyle(.borderedProminent)
                .help("Picks a file automatically — you can choose a specific one below.")
            }
            Spacer()
            Link("ModDB ↗", destination: mod.pageURL)
        }
    }

    /// Pozycja listy plików. ModDB trzyma pod jednym modem pełne wersje, patche i paczki
    /// źródłowe — automat wybiera „full", ale czasem trzeba wskazać coś ręcznie.
    @ViewBuilder private func fileRow(_ file: ModDBFile) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(file.title).font(.callout).lineLimit(1)
                Text([file.category, file.date, file.sizeText]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if file.isInstaller {
                Text("installer").font(.caption2).foregroundStyle(.orange)
                    .help(".exe/.dmg file — the launcher can't unpack it.")
            } else if !browser.installing.contains(mod.slug) {
                Button("Download") {
                    Task { await browser.install(mod, file: file, launcher: launcher, registry: registry) }
                }
                .controlSize(.small)
            }
        }
    }
}
