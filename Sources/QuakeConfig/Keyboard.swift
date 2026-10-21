import SwiftUI

// MARK: - Układ klawiatury

struct KeyDef: Identifiable {
    let id: String
    let label: String
    let quake: String? // nil = klawisz zarezerwowany (Esc, `, Caps) albo przerwa w układzie
    var width: CGFloat = 1

    var isGap: Bool { quake == nil && label.isEmpty }
}

private func k(_ id: String, _ label: String, _ quake: String?, _ width: CGFloat = 1) -> KeyDef {
    KeyDef(id: id, label: label, quake: quake, width: width)
}

let KEYBOARD_ROWS: [[KeyDef]] = [
    [k("esc", "Esc", nil), k("gap1", "", nil, 2)] + (1...12).map { k("f\($0)", "F\($0)", "F\($0)") },
    [k("bq", "`", nil)] + ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].map { k("n\($0)", $0, $0) }
        + [k("minus", "-", "-"), k("eq", "=", "="), k("bksp", "⌫", "BACKSPACE", 2)],
    [k("tab", "Tab", "TAB", 1.5)] + "qwertyuiop".map { k(String($0), String($0), String($0)) }
        + [k("lbr", "[", "["), k("rbr", "]", "]"), k("bsl", "\\", "\\", 1.5)],
    [k("caps", "Caps", nil, 1.75)] + "asdfghjkl".map { k(String($0), String($0), String($0)) }
        + [k("semi", ";", "SEMICOLON"), k("quote", "'", "'"), k("ent", "Enter", "ENTER", 2.25)],
    [k("lsh", "Shift", "SHIFT", 2.25)] + "zxcvbnm".map { k(String($0), String($0), String($0)) }
        + [k("com", ",", ","), k("dot", ".", "."), k("sl", "/", "/"), k("rsh", "Shift", "SHIFT", 2.75)],
    [k("lct", "Ctrl", "CTRL", 1.5), k("lal", "Alt", "ALT", 1.5), k("spc", "Spacja", "SPACE", 9),
     k("ral", "Alt", "ALT", 1.5), k("rct", "Ctrl", "CTRL", 1.5)],
]

let SIDE_ROWS: [[KeyDef]] = [
    [k("ins", "Ins", "INS"), k("home", "Home", "HOME"), k("pgup", "PgUp", "PGUP")],
    [k("del", "Del", "DEL"), k("end", "End", "END"), k("pgdn", "PgDn", "PGDN")],
]

let ARROW_KEYS = (up: k("up", "▲", "UPARROW"), left: k("left", "◀", "LEFTARROW"),
                  down: k("down", "▼", "DOWNARROW"), right: k("right", "▶", "RIGHTARROW"))

let MOUSE_KEYS: [KeyDef] = [
    k("m1", "LPM", "MOUSE1", 1.8), k("m2", "PPM", "MOUSE2", 1.8), k("m3", "ŚPM", "MOUSE3", 1.8),
    k("mwu", "Kółko ▲", "MWHEELUP", 2.2), k("mwd", "Kółko ▼", "MWHEELDOWN", 2.2),
    k("m4", "M4", "MOUSE4", 1.2), k("m5", "M5", "MOUSE5", 1.2),
]

// MARK: - Typowe komendy

struct CommandDef {
    let cmd: String
    let label: String
}

let COMMAND_GROUPS: [(name: String, color: Color, commands: [CommandDef])] = [
    ("Ruch", .blue, [
        CommandDef(cmd: "+forward", label: "Naprzód"),
        CommandDef(cmd: "+back", label: "W tył"),
        CommandDef(cmd: "+moveleft", label: "W lewo (strafe)"),
        CommandDef(cmd: "+moveright", label: "W prawo (strafe)"),
        CommandDef(cmd: "+jump", label: "Skok / pływanie w górę"),
        CommandDef(cmd: "+moveup", label: "Pływanie w górę"),
        CommandDef(cmd: "+movedown", label: "Pływanie w dół"),
        CommandDef(cmd: "+speed", label: "Bieg (gdy wyłączone „zawsze biegaj”)"),
    ]),
    ("Broń", .red, [
        CommandDef(cmd: "impulse 1", label: "Siekiera"),
        CommandDef(cmd: "impulse 2", label: "Shotgun"),
        CommandDef(cmd: "impulse 3", label: "Super Shotgun"),
        CommandDef(cmd: "impulse 4", label: "Nailgun"),
        CommandDef(cmd: "impulse 5", label: "Super Nailgun"),
        CommandDef(cmd: "impulse 6", label: "Granatnik"),
        CommandDef(cmd: "impulse 7", label: "Wyrzutnia rakiet"),
        CommandDef(cmd: "impulse 8", label: "Thunderbolt"),
        CommandDef(cmd: "impulse 10", label: "Następna broń"),
        CommandDef(cmd: "impulse 12", label: "Poprzednia broń"),
    ]),
    ("Akcje", .orange, [
        CommandDef(cmd: "+attack", label: "Strzał"),
        CommandDef(cmd: "+showscores", label: "Tablica wyników"),
        CommandDef(cmd: "screenshot", label: "Zrzut ekranu"),
        CommandDef(cmd: "save quick", label: "Szybki zapis"),
        CommandDef(cmd: "load quick", label: "Szybkie wczytanie"),
        CommandDef(cmd: "messagemode", label: "Czat"),
        CommandDef(cmd: "messagemode2", label: "Czat drużynowy"),
        CommandDef(cmd: "pause", label: "Pauza"),
        CommandDef(cmd: "toggleconsole", label: "Konsola"),
    ]),
]

func categoryColor(for command: String) -> Color? {
    let trimmed = command.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    for group in COMMAND_GROUPS where group.commands.contains(where: { $0.cmd == trimmed }) {
        return group.color
    }
    if trimmed.hasPrefix("impulse") { return .red }
    return .purple // własna komenda spoza listy
}
