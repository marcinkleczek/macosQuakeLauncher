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
                    Text("Imię gracza")
                    Spacer()
                    TextField("player", text: model.stringBinding(nameOption))
                        .frame(width: 240).multilineTextAlignment(.trailing)
                }
                Toggle("Złote litery", isOn: goldBinding)
                    .disabled((model.values["name"] ?? "").isEmpty)
                Text("Złote litery to znaki 128–255 charsetu Quake'a — działają tylko w silnikach z oryginalnym charsetem. Gra wyświetla wyłącznie ASCII, polskie znaki pojawią się jako „?”.")
                    .font(.caption).foregroundStyle(.secondary)
                // puste pole = gra użyje domyślnego "player", więc tak też pokazujemy podgląd
                QuakeTextPreview(text: (model.values["name"] ?? "").isEmpty ? "player" : model.values["name"]!,
                                 font: model.font)
                if model.font == nil {
                    Text("Nie znalazłem czcionki gry w id1/pak0.pak — podgląd zastępczy.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Po wczytaniu konfigu") {
                Toggle("Pokaż komunikat w konsoli", isOn: Binding(
                    get: { model.greeting },
                    set: { model.greeting = $0; model.dirty = true }
                ))
                Text("Linia `echo` na końcu autoexec.cfg — potwierdza, że konfig się wykonał. Widoczna w konsoli (klawisz ~).")
                    .font(.caption).foregroundStyle(.secondary)
                if model.greeting {
                    QuakeTextPreview(text: model.greetingText(), font: model.font, scale: 2)
                }
            }
        }
        .formStyle(.grouped)
    }
}
