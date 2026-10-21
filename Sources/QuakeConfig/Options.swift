import SwiftUI

// MARK: - Definicje opcji

struct Choice: Identifiable, Hashable {
    let label: String
    let value: String
    var id: String { value }
}

struct CvarOption: Identifiable {
    enum Kind {
        case toggle(on: String, off: String)
        case slider(ClosedRange<Double>, step: Double)
        case choice([Choice])
        case text(placeholder: String)
    }

    let cvar: String
    let label: String
    let section: String
    let kind: Kind
    let defaultValue: String
    var help: String? = nil

    var id: String { cvar }
}

let ALL_OPTIONS: [CvarOption] = [
    // Mysz
    CvarOption(cvar: "sensitivity", label: "Czułość myszy", section: "Mysz", kind: .slider(1...15, step: 0.5), defaultValue: "3"),
    CvarOption(cvar: "m_pitch", label: "Odwrócona oś Y", section: "Mysz", kind: .toggle(on: "-0.022", off: "0.022"), defaultValue: "0.022"),
    CvarOption(cvar: "lookspring", label: "Powrót widoku do poziomu", section: "Mysz", kind: .toggle(on: "1", off: "0"), defaultValue: "0"),
    // Ruch
    CvarOption(cvar: "cl_alwaysrun", label: "Zawsze biegaj", section: "Ruch", kind: .toggle(on: "1", off: "0"), defaultValue: "1"),
    // Widok
    CvarOption(cvar: "fov", label: "Pole widzenia (FOV)", section: "Widok", kind: .slider(60...130, step: 1), defaultValue: "90"),
    CvarOption(cvar: "r_drawviewmodel", label: "Pokazuj broń", section: "Widok", kind: .toggle(on: "1", off: "0"), defaultValue: "1"),
    CvarOption(cvar: "cl_bob", label: "Kołysanie broni przy ruchu", section: "Widok", kind: .toggle(on: "0.02", off: "0"), defaultValue: "0.02"),
    CvarOption(cvar: "cl_rollangle", label: "Przechył ekranu w skrętach", section: "Widok", kind: .toggle(on: "2", off: "0"), defaultValue: "2"),
    CvarOption(cvar: "crosshair", label: "Celownik", section: "Widok", kind: .toggle(on: "1", off: "0"), defaultValue: "1"),
    CvarOption(cvar: "scr_crosshairscale", label: "Wielkość celownika", section: "Widok", kind: .slider(1...5, step: 0.5), defaultValue: "1"),
    // Tryb wideo
    CvarOption(cvar: "vid_fullscreen", label: "Pełny ekran", section: "Tryb wideo", kind: .toggle(on: "1", off: "0"), defaultValue: "1"),
    CvarOption(cvar: "vid_desktopfullscreen", label: "Natywna rozdzielczość pulpitu", section: "Tryb wideo", kind: .toggle(on: "1", off: "0"), defaultValue: "1",
               help: "Gdy włączone, pola szerokość/wysokość nie mają znaczenia w trybie pełnoekranowym."),
    CvarOption(cvar: "vid_width", label: "Szerokość", section: "Tryb wideo", kind: .text(placeholder: "puste = bez zmian"), defaultValue: ""),
    CvarOption(cvar: "vid_height", label: "Wysokość", section: "Tryb wideo", kind: .text(placeholder: "puste = bez zmian"), defaultValue: ""),
    CvarOption(cvar: "vid_vsync", label: "Synchronizacja pionowa (VSync)", section: "Tryb wideo", kind: .toggle(on: "1", off: "0"), defaultValue: "1"),
    CvarOption(cvar: "host_maxfps", label: "Limit FPS", section: "Tryb wideo",
               kind: .choice([Choice(label: "60", value: "60"), Choice(label: "72 (klasyczny)", value: "72"), Choice(label: "120", value: "120"),
                              Choice(label: "144", value: "144"), Choice(label: "165", value: "165"), Choice(label: "240", value: "240")]),
               defaultValue: "72"),
    CvarOption(cvar: "vid_fsaa", label: "Antyaliasing (MSAA)", section: "Tryb wideo",
               kind: .choice([Choice(label: "Wyłączony", value: "0"), Choice(label: "2×", value: "2"), Choice(label: "4×", value: "4"), Choice(label: "8×", value: "8")]),
               defaultValue: "0", help: "Zmiana wymaga restartu silnika."),
    // Grafika
    CvarOption(cvar: "gl_texturemode", label: "Tekstury", section: "Grafika",
               kind: .choice([Choice(label: "Pikselowe (klasyczne)", value: "GL_NEAREST_MIPMAP_LINEAR"),
                              Choice(label: "Filtrowane (wygładzone)", value: "GL_LINEAR_MIPMAP_LINEAR")]),
               defaultValue: "GL_LINEAR_MIPMAP_LINEAR"),
    CvarOption(cvar: "r_particles", label: "Cząsteczki", section: "Grafika",
               kind: .choice([Choice(label: "Okrągłe", value: "1"), Choice(label: "Klasyczne kwadraty", value: "2"), Choice(label: "Wyłączone", value: "0")]),
               defaultValue: "1"),
    CvarOption(cvar: "r_shadows", label: "Cienie pod obiektami", section: "Grafika", kind: .toggle(on: "1", off: "0"), defaultValue: "0"),
    CvarOption(cvar: "r_lerpmodels", label: "Płynna animacja modeli", section: "Grafika", kind: .toggle(on: "1", off: "0"), defaultValue: "1"),
    CvarOption(cvar: "r_lerpmove", label: "Płynny ruch potworów", section: "Grafika", kind: .toggle(on: "1", off: "0"), defaultValue: "1"),
    CvarOption(cvar: "r_scale", label: "Pikselizacja obrazu (retro)", section: "Grafika",
               kind: .choice([Choice(label: "Wyłączona", value: "1"), Choice(label: "2×", value: "2"), Choice(label: "3×", value: "3"), Choice(label: "4×", value: "4")]),
               defaultValue: "1", help: "Renderuje obraz w ułamku rozdzielczości — wygląd jak w 1996."),
    CvarOption(cvar: "r_wateralpha", label: "Przezroczystość wody", section: "Grafika", kind: .slider(0.3...1, step: 0.05), defaultValue: "1",
               help: "Na oryginalnych mapach wymaga silnika z obsługą przezroczystej wody (QuakeSpasm/vkQuake ją mają)."),
    CvarOption(cvar: "gamma", label: "Gamma (mniej = jaśniej)", section: "Grafika", kind: .slider(0.5...1.3, step: 0.05), defaultValue: "1"),
    CvarOption(cvar: "contrast", label: "Kontrast", section: "Grafika", kind: .slider(1...2, step: 0.1), defaultValue: "1"),
    // HUD
    CvarOption(cvar: "scr_sbarscale", label: "Skala paska statusu", section: "HUD",
               kind: .choice([Choice(label: "1×", value: "1"), Choice(label: "2×", value: "2"), Choice(label: "3×", value: "3"), Choice(label: "4×", value: "4")]),
               defaultValue: "2"),
    CvarOption(cvar: "scr_menuscale", label: "Skala menu", section: "HUD",
               kind: .choice([Choice(label: "1×", value: "1"), Choice(label: "2×", value: "2"), Choice(label: "3×", value: "3"), Choice(label: "4×", value: "4")]),
               defaultValue: "2"),
    CvarOption(cvar: "scr_conscale", label: "Skala konsoli", section: "HUD",
               kind: .choice([Choice(label: "1×", value: "1"), Choice(label: "2×", value: "2"), Choice(label: "3×", value: "3"), Choice(label: "4×", value: "4")]),
               defaultValue: "2"),
    CvarOption(cvar: "scr_sbaralpha", label: "Nieprzezroczystość paska statusu", section: "HUD", kind: .slider(0...1, step: 0.05), defaultValue: "0.75"),
    CvarOption(cvar: "scr_showfps", label: "Licznik FPS", section: "HUD", kind: .toggle(on: "1", off: "0"), defaultValue: "0"),
    // Dźwięk
    CvarOption(cvar: "volume", label: "Głośność efektów", section: "Dźwięk", kind: .slider(0...1, step: 0.05), defaultValue: "0.7"),
    CvarOption(cvar: "bgmvolume", label: "Głośność muzyki", section: "Dźwięk", kind: .slider(0...1, step: 0.05), defaultValue: "1"),
    // Multiplayer — sekcja ma własną zakładkę (PlayerTab), nie trafia do OptionsTab
    CvarOption(cvar: "name", label: "Imię gracza", section: "Multiplayer", kind: .text(placeholder: "player"), defaultValue: ""),
]

let DEFAULT_BINDS: [(String, String)] = [
    ("w", "+forward"), ("s", "+back"), ("a", "+moveleft"), ("d", "+moveright"),
    ("SPACE", "+jump"), ("MOUSE1", "+attack"),
    ("MWHEELUP", "impulse 12"), ("MWHEELDOWN", "impulse 10"),
    ("TAB", "+showscores"), ("F12", "screenshot"),
]

struct BindEntry: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var command: String
}
