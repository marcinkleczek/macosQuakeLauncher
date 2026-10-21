import SwiftUI

struct PlayerTab: View {
    @ObservedObject var model: ConfigModel

    private var nameOption: CvarOption { ALL_OPTIONS.first { $0.cvar == "name" }! }

    private var goldBinding: Binding<Bool> {
        Binding(
            get: { model.isGoldName },
            set: { on in
                model.values["name"] = ConfigModel.gold(model.values["name"] ?? "", on: on)
                model.dirty = true
            }
        )
    }

    var body: some View {
        Form {
            Section("Multiplayer") {
                HStack {
                    Text("Player name")
                    Spacer()
                    TextField("player", text: model.stringBinding(nameOption))
                        .frame(width: 240).multilineTextAlignment(.trailing)
                }
                Toggle("Gold letters", isOn: goldBinding)
                    .disabled((model.values["name"] ?? "").isEmpty)
                Text("Gold letters are characters 128–255 of the Quake charset — they only work in engines that use the original charset. The game displays ASCII only; accented characters will show up as “?”.")
                    .font(.caption).foregroundStyle(.secondary)
                // puste pole = gra użyje domyślnego "player", więc tak też pokazujemy podgląd
                QuakeTextPreview(text: (model.values["name"] ?? "").isEmpty ? "player" : model.values["name"]!,
                                 font: model.font)
                if model.font == nil {
                    Text("Couldn't find the game font in id1/pak0.pak — showing a fallback preview.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Section("After the config loads") {
                Toggle("Show a message in the console", isOn: Binding(
                    get: { model.greeting },
                    set: { model.greeting = $0; model.dirty = true }
                ))
                Text("An `echo` line at the end of autoexec.cfg — confirms that the config was executed. Visible in the console (~ key).")
                    .font(.caption).foregroundStyle(.secondary)
                if model.greeting {
                    QuakeTextPreview(text: model.greetingText(), font: model.font, scale: 2)
                }
            }
        }
        .formStyle(.grouped)
    }
}
