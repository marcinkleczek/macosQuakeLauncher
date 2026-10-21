import SwiftUI

struct PackageDetail: View {
    @ObservedObject var launcher: LauncherModel
    @ObservedObject var browser: BrowserModel
    @ObservedObject var registry: InstallRegistry
    let pkg: MapPackage

    private var subtitle: String {
        var parts = [pkg.author, pkg.date]
        if pkg.sizeKB > 0 { parts.append(pkg.sizeText) }
        if pkg.ratingAvg > 0 { parts.append(String(format: "ocena %.1f★ (%d głosów)", pkg.ratingAvg, pkg.ratingCount)) }
        parts.append("id: \(pkg.id)")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(pkg.title.isEmpty ? pkg.id : pkg.title).font(.title2).bold()
                Text(subtitle)
                    .font(.caption).foregroundStyle(.secondary)

                AsyncImage(url: browser.screenshotURL(for: pkg)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 6))
                    case .failure:
                        Label("Brak zrzutu ekranu", systemImage: "photo")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
                    default:
                        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
                .frame(maxHeight: 280)

                HStack {
                    if !pkg.detailLoaded, !browser.installing.contains(pkg.id) {
                        ProgressView().controlSize(.small)
                        Text("Pobieram szczegóły…").font(.caption).foregroundStyle(.secondary)
                    } else if browser.installing.contains(pkg.id) {
                        ProgressView().controlSize(.small)
                        Text("Instaluję…")
                    } else if browser.isInstalled(pkg, launcher: launcher) {
                        Button("Graj ▶") { browser.play(pkg, launcher: launcher) }
                            .buttonStyle(.borderedProminent)
                        let maps = browser.availableMaps(pkg)
                        if maps.count > 1 {
                            Menu("mapa ▾") {
                                ForEach(maps, id: \.self) { map in
                                    Button(map) { browser.play(pkg, launcher: launcher, map: map) }
                                }
                            }
                            .frame(width: 90)
                        }
                        Label("zainstalowana", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    } else {
                        Button("Pobierz i zainstaluj") {
                            Task { await browser.install(pkg, launcher: launcher, registry: registry) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                    Link("Quaddicted ↗", destination: URL(string: "https://www.quaddicted.com/db/v2/maps/\(pkg.sha256)")!)
                }

                if !pkg.requirements.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wymaga:").font(.callout).bold()
                        ForEach(pkg.requirements, id: \.self) { reqID in
                            requirementRow(reqID)
                        }
                    }
                }
                if let mod = pkg.requiredMod, !launcher.baseModInstalled(mod) {
                    // duże mody (Arcane Dimensions, Copper, Quoth) nie są hostowane
                    // na Quaddicted — bazę trzeba zdobyć samemu. Sam katalog nie wystarczy:
                    // tworzą go same mapy, a bez progs.dat mapa startuje bez logiki moda.
                    Label("Wymaga moda \"\(mod)\" — w katalogu gry są tylko mapy, brakuje samego moda "
                          + "(progs.dat/pak). Bez niego mapa uruchomi się bez logiki dodatku.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                if !pkg.startmaps.isEmpty {
                    Text("Mapa startowa: \(pkg.startmaps.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !pkg.commandline.isEmpty {
                    Text("Parametry: \(pkg.commandline)").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                if !pkg.tags.isEmpty {
                    Text("Tagi: \(pkg.tags.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                }
                if browser.isInstalled(pkg, launcher: launcher), !browser.availableMaps(pkg).isEmpty {
                    Divider()
                    MapSpoilerPanel(launcher: launcher,
                                    mapNames: browser.availableMaps(pkg),
                                    preferredGame: browser.playGameDir(pkg, launcher: launcher))
                        .id(pkg.id) // przy zmianie paczki panel wraca do stanu zamkniętego
                }
                Divider()
                Text(pkg.descriptionText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
        }
        .task(id: pkg.id) { await browser.ensureDetail(pkg.id) }
    }

    @ViewBuilder private func requirementRow(_ reqID: String) -> some View {
        HStack(spacing: 6) {
            if let req = browser.packages.first(where: { $0.id == reqID }) {
                let installed = browser.isInstalled(req, launcher: launcher)
                Image(systemName: installed ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(installed ? .green : .orange)
                Text(req.title.isEmpty ? req.id : req.title)
                if !installed, !browser.installing.contains(req.id) {
                    Button("Zainstaluj") {
                        Task { await browser.install(req, launcher: launcher, registry: registry) }
                    }
                    .controlSize(.small)
                } else if browser.installing.contains(req.id) {
                    ProgressView().controlSize(.small)
                }
            } else {
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                Text(reqID)
            }
        }
        .font(.callout)
    }
}
