import SwiftUI

// MARK: - UI

struct ContentView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var registry: InstallRegistry
    @Environment(\.openWindow) private var openWindow

    static let modLabels = [
        "id1": "id1 (no mod)",
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
            Text("Choose the Quake folder").font(.title2)
            Text("The folder that contains the id1 subfolder (with pak0.pak) and your mod folders.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose folder…") { pickBaseDir() }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var launcherForm: some View {
        Group {
            Grid(alignment: .leading, verticalSpacing: 10) {
                GridRow {
                    Text("Engine:")
                    HStack {
                        Picker("", selection: $model.selectedEngine) {
                            ForEach(model.engines) { engine in
                                Text(engine.name).tag(Optional(engine))
                            }
                        }
                        .labelsHidden()
                        Button("…") { pickEngine() }
                            .help("Add another engine (app or binary)")
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
                    Text("Map:")
                    Picker("", selection: $model.selectedMap) {
                        Text("(main menu)").tag("")
                        ForEach(model.maps, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Display:")
                    Picker("", selection: $model.selectedDisplay) {
                        Text("Default").tag(Optional<DisplayOption>.none)
                        ForEach(model.displays) { display in
                            Text(display.name).tag(Optional(display))
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("")
                    Toggle("Fullscreen", isOn: $model.fullscreen)
                        .toggleStyle(.checkbox)
                }
                GridRow {
                    Text("Skill:")
                    Picker("", selection: $model.skill) {
                        Text("Default").tag(-1)
                        Text("Easy").tag(0)
                        Text("Normal").tag(1)
                        Text("Hard").tag(2)
                        Text("Nightmare").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                GridRow {
                    Text("Extra arguments:")
                    TextField("e.g. -width 2560", text: $model.params)
                }
            }

            // Dwa rzędy: sześć przycisków w jednej linii nie mieściło się w oknie
            // o szerokości 420 i etykiety obcinały się do „Mapy onli…”.
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Download from:")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Quaddicted") { openWindow(id: "maps") }
                    Button("SlipSeer") { openWindow(id: "slipseer") }
                    Button("ModDB") { openWindow(id: "moddb") }
                    Spacer()
                    Button("Downloaded") { openWindow(id: "library") }
                        .help("Everything you've downloaded — from all sources, with dates.")
                }

                HStack(spacing: 8) {
                    Button("Change folder…") { pickBaseDir() }
                    Button("Refresh") { model.rescan() }
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
        panel.message = "Choose the Quake folder (containing id1)"
        if panel.runModal() == .OK, let url = panel.url {
            model.setBaseDir(url)
        }
    }

    private func pickEngine() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.message = "Choose a Quake engine app (.app) or binary"
        if panel.runModal() == .OK, let url = panel.url {
            model.addCustomEngine(url)
        }
    }
}
