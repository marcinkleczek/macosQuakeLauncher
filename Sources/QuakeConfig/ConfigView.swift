import SwiftUI

struct AdvancedTab: View {
    @ObservedObject var model: ConfigModel

    var body: some View {
        VSplitView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Własne komendy (zachowywane przy zapisie):").font(.callout)
                TextEditor(text: $model.customText)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: model.customText) { model.dirty = true }
            }
            .padding(10)
            VStack(alignment: .leading, spacing: 4) {
                Text("Podgląd pliku autoexec.cfg:").font(.callout)
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
                    OptionsTab(model: model, sections: ["Mysz", "Ruch", "Widok"])
                        .tabItem { Text("Sterowanie") }
                    OptionsTab(model: model, sections: ["Tryb wideo", "Grafika"])
                        .tabItem { Text("Obraz") }
                    OptionsTab(model: model, sections: ["HUD", "Dźwięk"])
                        .tabItem { Text("HUD i dźwięk") }
                    BindsTab(model: model)
                        .tabItem { Text("Bindy") }
                    PlayerTab(model: model)
                        .tabItem { Text("Gracz") }
                    AdvancedTab(model: model)
                        .tabItem { Text("Zaawansowane") }
                }
                statusBar
            }
        }
        .frame(minWidth: 780, minHeight: 620)
    }

    private var setupView: some View {
        VStack(spacing: 12) {
            Text("Wskaż katalog Quake'a").font(.title2)
            Text("Katalog zawierający id1 i katalogi modów.").foregroundStyle(.secondary)
            Button("Wybierz katalog…") { pickBaseDir() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerBar: some View {
        HStack {
            Text("Konfig dla:")
            Picker("", selection: Binding(get: { model.selectedDir }, set: { model.switchDir(to: $0) })) {
                ForEach(model.gameDirs, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().frame(width: 160)
            .help("Mission packi i mody bez własnego autoexec.cfg dziedziczą ten z id1.")
            Button("Zmień katalog…") { pickBaseDir() }
            Spacer()
            Button("Przywróć domyślne") { model.resetDefaults() }
            Button("Zapisz") { model.save() }
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
                Text("● niezapisane zmiany").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
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
}
