import SwiftUI

// MARK: - Panel zawartości mapy
//
// Domyślnie zwinięty i zwijany z powrotem przy każdej zmianie mapy: kto gra po raz
// pierwszy, nie powinien przypadkiem zobaczyć, ile sekretów przegapił. Analiza pliku
// rusza dopiero po kliknięciu — dopóki panel jest zamknięty, nie czytamy dysku.

struct InspectableMap: Identifiable, Hashable {
    let name: String
    let source: MapSource

    var id: String { name }
}

struct MapSpoilerPanel: View {
    @ObservedObject var launcher: LauncherModel
    let mapNames: [String]
    let preferredGame: String?

    @State private var maps: [InspectableMap] = []
    @State private var selected: String = ""
    @State private var info: MapInfo?
    @State private var revealed = false
    @State private var failed = false

    private var current: InspectableMap? {
        maps.first { $0.name == selected } ?? maps.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                revealed.toggle()
                if revealed { reload() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: revealed ? "chevron.down" : "chevron.right")
                        .font(.caption.bold())
                        .frame(width: 10)
                    Image(systemName: revealed ? "eye" : "eye.slash")
                    Text(revealed ? "Map contents" : "Show map contents (spoiler)")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Reads the entity list from the .bsp file — weapons, secrets, buttons, monsters.")

            if revealed {
                if maps.count > 1 {
                    Picker("", selection: $selected) {
                        ForEach(maps) { Text($0.name).tag($0.name) }
                    }
                    .labelsHidden()
                }
                if let info {
                    details(info)
                } else if failed {
                    Label(maps.isEmpty
                            ? "Couldn't find this package's map files in the game folder."
                            : "Couldn't read this map (unknown BSP format).",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        // poziom trudności i wybór mapy decydują, co w ogóle powstanie — przelicz
        .task(id: "\(selected)|\(launcher.skill)") {
            if revealed { reload() }
        }
    }

    private func reload() {
        // wyszukanie plików rusza dopiero tutaj — panel zamknięty nie dotyka dysku
        if maps.isEmpty {
            maps = launcher.locateMaps(named: mapNames, preferredGame: preferredGame)
        }
        guard let map = current else { info = nil; failed = true; return }
        if selected.isEmpty { selected = map.name }
        info = launcher.inspect(map.source)
        failed = info == nil
    }

    @ViewBuilder private func details(_ info: MapInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if !info.title.isEmpty {
                    Text(info.title).font(.callout).bold()
                }
                Text(info.headline.joined(separator: " · ") + " · skill: \(info.skillLabel)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // bez własnego ScrollView — panel siedzi w przewijanym widoku paczki
            VStack(alignment: .leading, spacing: 12) {
                ForEach(info.sections) { section in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(section.title.uppercased())
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        ForEach(section.items) { item in
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.label)
                                Spacer(minLength: 8)
                                Text(item.detail)
                                    .foregroundStyle(item.muted ? .tertiary : .primary)
                            }
                            .font(.callout)
                            .foregroundStyle(item.muted ? .secondary : .primary)
                        }
                        if let note = section.note {
                            Text(note).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .textSelection(.enabled)
    }
}
