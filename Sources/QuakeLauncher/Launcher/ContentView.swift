import SwiftUI

// MARK: - UI

struct ContentView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var registry: InstallRegistry
    @Environment(\.openWindow) private var openWindow

    static let modLabels = [
        "id1": "id1 (bez moda)",
        "hipnotic": "hipnotic (Scourge of Armagon)",
        "rogue": "rogue (Dissolution of Eternity)",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.baseDir == nil {
                setupView
            } else {
                launcherForm
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var setupView: some View {
        VStack(spacing: 12) {
            Text("Wskaż katalog Quake'a").font(.title2)
            Text("Katalog, w którym znajduje się podkatalog id1 (z pak0.pak) oraz katalogi modów.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Wybierz katalog…") { pickBaseDir() }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var launcherForm: some View {
        Group {
            Grid(alignment: .leading, verticalSpacing: 10) {
                GridRow {
                    Text("Silnik:")
                    HStack {
                        Picker("", selection: $model.selectedEngine) {
                            ForEach(model.engines) { engine in
                                Text(engine.name).tag(Optional(engine))
                            }
                        }
                        .labelsHidden()
                        Button("…") { pickEngine() }
                            .help("Dodaj inny silnik (aplikację lub binarkę)")
                    }
                }
                GridRow {
                    Text("Mod:")
                    Picker("", selection: $model.selectedMod) {
                        ForEach(model.mods, id: \.self) { mod in
                            Text(Self.modLabels[mod] ?? mod).tag(mod)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Mapa:")
                    Picker("", selection: $model.selectedMap) {
                        Text("(menu główne)").tag("")
                        ForEach(model.maps, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Monitor:")
                    Picker("", selection: $model.selectedDisplay) {
                        Text("Domyślny").tag(Optional<DisplayOption>.none)
                        ForEach(model.displays) { display in
                            Text(display.name).tag(Optional(display))
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("")
                    Toggle("Pełny ekran", isOn: $model.fullscreen)
                        .toggleStyle(.checkbox)
                }
                GridRow {
                    Text("Skill:")
                    Picker("", selection: $model.skill) {
                        Text("Domyślny").tag(-1)
                        Text("Easy").tag(0)
                        Text("Normal").tag(1)
                        Text("Hard").tag(2)
                        Text("Nightmare").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                GridRow {
                    Text("Parametry:")
                    TextField("np. -width 2560", text: $model.params)
                }
            }

            // Dwa rzędy: sześć przycisków w jednej linii nie mieściło się w oknie
            // o szerokości 420 i etykiety obcinały się do „Mapy onli…”.
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Pobieraj z:")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Quaddicted") { openWindow(id: "maps") }
                    Button("SlipSeer") { openWindow(id: "slipseer") }
                    Button("ModDB") { openWindow(id: "moddb") }
                    Spacer()
                    Button("Pobrane") { openWindow(id: "library") }
                        .help("Wszystko, co pobrałeś — ze wszystkich źródeł, z datami.")
                }

                HStack(spacing: 8) {
                    Button("Zmień katalog…") { pickBaseDir() }
                    Button("Odśwież") { model.rescan() }
                    Spacer()
                    Button("Launch ▶") { model.launch() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(model.selectedEngine == nil)
                }
            }

            if !model.status.isEmpty {
                Text(model.status)
                    .font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func pickBaseDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Wybierz katalog Quake'a (zawierający id1)"
        if panel.runModal() == .OK, let url = panel.url {
            model.setBaseDir(url)
        }
    }

    private func pickEngine() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.message = "Wybierz aplikację (.app) lub binarkę silnika Quake"
        if panel.runModal() == .OK, let url = panel.url {
            model.addCustomEngine(url)
        }
    }
}
