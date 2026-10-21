import SwiftUI

struct KeyCap: View {
    @ObservedObject var model: ConfigModel
    let key: KeyDef
    @Binding var selectedKeyID: String?

    private static let unit: CGFloat = 30
    private static let spacing: CGFloat = 3

    private var capWidth: CGFloat {
        Self.unit * key.width + Self.spacing * (key.width - 1)
    }

    var body: some View {
        if key.isGap {
            Color.clear.frame(width: capWidth, height: 30)
        } else {
            let command = key.quake.map { model.command(forKey: $0) } ?? ""
            Button {
                if key.quake != nil { selectedKeyID = key.id }
            } label: {
                Text(key.label)
                    .font(.system(size: 10, weight: .medium))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .frame(width: capWidth, height: 30)
            }
            .buttonStyle(.plain)
            .background(capColor(command), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary))
            .opacity(key.quake == nil ? 0.35 : 1)
            .help(helpText(command))
            .popover(isPresented: Binding(
                get: { selectedKeyID == key.id },
                set: { if !$0 { selectedKeyID = nil } }
            ), arrowEdge: .bottom) {
                KeyPopover(model: model, keyDef: key)
            }
        }
    }

    private func capColor(_ command: String) -> AnyShapeStyle {
        if let color = categoryColor(for: command) {
            return AnyShapeStyle(color.opacity(0.55))
        }
        return AnyShapeStyle(.quaternary.opacity(0.5))
    }

    private func helpText(_ command: String) -> String {
        if key.quake == nil { return "Reserved key (menu / console)" }
        return command.isEmpty ? "Unbound key — click to assign" : command
    }
}

struct KeyPopover: View {
    @ObservedObject var model: ConfigModel
    let keyDef: KeyDef

    var body: some View {
        let quake = keyDef.quake ?? ""
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(keyDef.label).font(.headline)
                Text(quake).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            TextField("command (empty = unbound)", text: model.commandBinding(forKey: quake))
                .frame(width: 270)
            Menu("Common commands") {
                ForEach(COMMAND_GROUPS, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.commands, id: \.cmd) { command in
                            Button("\(command.label)  —  \(command.cmd)") {
                                model.setBind(key: quake, command: command.cmd)
                            }
                        }
                    }
                }
            }
            if !model.command(forKey: quake).isEmpty {
                Button("Unbind key", role: .destructive) {
                    model.setBind(key: quake, command: "")
                }
            }
        }
        .padding(12)
    }
}

struct BindsTab: View {
    @ObservedObject var model: ConfigModel
    @State private var selectedKeyID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            legend
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 3) {
                    ForEach(KEYBOARD_ROWS.indices, id: \.self) { row in
                        HStack(spacing: 3) {
                            ForEach(KEYBOARD_ROWS[row]) { key in
                                KeyCap(model: model, key: key, selectedKeyID: $selectedKeyID)
                            }
                        }
                    }
                }
                VStack(spacing: 3) {
                    ForEach(SIDE_ROWS.indices, id: \.self) { row in
                        HStack(spacing: 3) {
                            ForEach(SIDE_ROWS[row]) { key in
                                KeyCap(model: model, key: key, selectedKeyID: $selectedKeyID)
                            }
                        }
                    }
                    Spacer().frame(height: 30)
                    KeyCap(model: model, key: ARROW_KEYS.up, selectedKeyID: $selectedKeyID)
                    HStack(spacing: 3) {
                        KeyCap(model: model, key: ARROW_KEYS.left, selectedKeyID: $selectedKeyID)
                        KeyCap(model: model, key: ARROW_KEYS.down, selectedKeyID: $selectedKeyID)
                        KeyCap(model: model, key: ARROW_KEYS.right, selectedKeyID: $selectedKeyID)
                    }
                }
            }
            HStack(spacing: 3) {
                Text("Mouse:").font(.caption).frame(width: 44, alignment: .leading)
                ForEach(MOUSE_KEYS) { key in
                    KeyCap(model: model, key: key, selectedKeyID: $selectedKeyID)
                }
            }
            Divider()
            Text("All key bindings (including keys not shown above):").font(.callout)
            List {
                ForEach($model.binds) { $bind in
                    HStack {
                        TextField("key", text: $bind.key).frame(width: 120)
                        TextField("command", text: $bind.command)
                        Button {
                            model.binds.removeAll { $0.id == bind.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .onChange(of: model.binds) { model.dirty = true }
            Button("Add binding") { model.binds.append(BindEntry(key: "", command: "")) }
        }
        .padding(12)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(COMMAND_GROUPS, id: \.name) { group in
                Label(group.name, systemImage: "circle.fill")
                    .font(.caption).foregroundStyle(group.color)
            }
            Label("Custom", systemImage: "circle.fill").font(.caption).foregroundStyle(.purple)
            Spacer()
            Text("Click a key to assign a command").font(.caption).foregroundStyle(.secondary)
        }
    }
}
