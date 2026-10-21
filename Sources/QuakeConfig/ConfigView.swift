import SwiftUI

struct AdvancedTab: View {
    @ObservedObject var model: ConfigModel

    var body: some View {
        VSplitView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Custom commands (kept on save):").font(.callout)
                TextEditor(text: $model.customText)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: model.customText) { model.dirty = true }
            }
            .padding(10)
            VStack(alignment: .leading, spacing: 4) {
                Text("autoexec.cfg preview:").font(.callout)
                ScrollView {
                    Text(model.configText())
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(.quaternary.opacity(0.4))
            }
            .padding(10)
        }
    }
}

struct ConfigView: View {
    @StateObject private var model = ConfigModel()

    var body: some View {
        VStack(spacing: 0) {
            if model.baseDir == nil {
                setupView
            } else {
                headerBar
                Divider()
                TabView {
                    OptionsTab(model: model, sections: ["Mouse", "Movement", "View"])
                        .tabItem { Text("Controls") }
                    OptionsTab(model: model, sections: ["Video mode", "Graphics"])
                        .tabItem { Text("Display") }
                    OptionsTab(model: model, sections: ["HUD", "Sound"])
                        .tabItem { Text("HUD & Sound") }
                    BindsTab(model: model)
                        .tabItem { Text("Key bindings") }
                    PlayerTab(model: model)
                        .tabItem { Text("Player") }
                    AdvancedTab(model: model)
                        .tabItem { Text("Advanced") }
                }
                statusBar
            }
        }
        .frame(minWidth: 780, minHeight: 620)
    }

    private var setupView: some View {
        VStack(spacing: 12) {
            Text("Locate your Quake folder").font(.title2)
            Text("The folder that contains id1 and the mod folders.").foregroundStyle(.secondary)
            Button("Choose folder…") { pickBaseDir() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerBar: some View {
        HStack {
            Text("Config for:")
            Picker("", selection: Binding(get: { model.selectedDir }, set: { model.switchDir(to: $0) })) {
                ForEach(model.gameDirs, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().frame(width: 160)
            .help("Mission packs and mods without their own autoexec.cfg inherit the one from id1.")
            Button("Change folder…") { pickBaseDir() }
            Spacer()
            Button("Restore Defaults") { model.resetDefaults() }
            Button("Save") { model.save() }
                .keyboardShortcut("s")
                .buttonStyle(.borderedProminent)
        }
        .padding(10)
    }

    private var statusBar: some View {
        HStack {
            Text(model.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Spacer()
            if model.dirty {
                Text("● unsaved changes").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private func pickBaseDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose the Quake folder (the one containing id1)"
        if panel.runModal() == .OK, let url = panel.url {
            model.setBaseDir(url)
        }
    }
}
