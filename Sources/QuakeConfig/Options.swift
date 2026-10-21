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
    CvarOption(cvar: "sensitivity", label: "Mouse sensitivity", section: "Mouse", kind: .slider(1...15, step: 0.5), defaultValue: "3"),
    CvarOption(cvar: "m_pitch", label: "Invert mouse", section: "Mouse", kind: .toggle(on: "-0.022", off: "0.022"), defaultValue: "0.022"),
    CvarOption(cvar: "lookspring", label: "Auto-center view (lookspring)", section: "Mouse", kind: .toggle(on: "1", off: "0"), defaultValue: "0"),
    // Ruch
    CvarOption(cvar: "cl_alwaysrun", label: "Always run", section: "Movement", kind: .toggle(on: "1", off: "0"), defaultValue: "1"),
    // Widok
    CvarOption(cvar: "fov", label: "Field of view (FOV)", section: "View", kind: .slider(60...130, step: 1), defaultValue: "90"),
    CvarOption(cvar: "r_drawviewmodel", label: "Show weapon", section: "View", kind: .toggle(on: "1", off: "0"), defaultValue: "1"),
    CvarOption(cvar: "cl_bob", label: "Weapon bob while moving", section: "View", kind: .toggle(on: "0.02", off: "0"), defaultValue: "0.02"),
    CvarOption(cvar: "cl_rollangle", label: "View roll when strafing", section: "View", kind: .toggle(on: "2", off: "0"), defaultValue: "2"),
    CvarOption(cvar: "crosshair", label: "Crosshair", section: "View", kind: .toggle(on: "1", off: "0"), defaultValue: "1"),
    CvarOption(cvar: "scr_crosshairscale", label: "Crosshair size", section: "View", kind: .slider(1...5, step: 0.5), defaultValue: "1"),
    // Tryb wideo
    CvarOption(cvar: "vid_fullscreen", label: "Fullscreen", section: "Video mode", kind: .toggle(on: "1", off: "0"), defaultValue: "1"),
    CvarOption(cvar: "vid_desktopfullscreen", label: "Native desktop resolution", section: "Video mode", kind: .toggle(on: "1", off: "0"), defaultValue: "1",
               help: "When enabled, width and height are ignored in fullscreen mode."),
    CvarOption(cvar: "vid_width", label: "Width", section: "Video mode", kind: .text(placeholder: "empty = unchanged"), defaultValue: ""),
    CvarOption(cvar: "vid_height", label: "Height", section: "Video mode", kind: .text(placeholder: "empty = unchanged"), defaultValue: ""),
    CvarOption(cvar: "vid_vsync", label: "Vertical sync (VSync)", section: "Video mode", kind: .toggle(on: "1", off: "0"), defaultValue: "1"),
    CvarOption(cvar: "host_maxfps", label: "FPS limit", section: "Video mode",
               kind: .choice([Choice(label: "60", value: "60"), Choice(label: "72 (classic)", value: "72"), Choice(label: "120", value: "120"),
                              Choice(label: "144", value: "144"), Choice(label: "165", value: "165"), Choice(label: "240", value: "240")]),
               defaultValue: "72"),
    CvarOption(cvar: "vid_fsaa", label: "Anti-aliasing (MSAA)", section: "Video mode",
               kind: .choice([Choice(label: "Off", value: "0"), Choice(label: "2×", value: "2"), Choice(label: "4×", value: "4"), Choice(label: "8×", value: "8")]),
               defaultValue: "0", help: "Changing this requires an engine restart."),
    // Grafika
    CvarOption(cvar: "gl_texturemode", label: "Textures", section: "Graphics",
               kind: .choice([Choice(label: "Pixelated (classic)", value: "GL_NEAREST_MIPMAP_LINEAR"),
                              Choice(label: "Filtered (smooth)", value: "GL_LINEAR_MIPMAP_LINEAR")]),
               defaultValue: "GL_LINEAR_MIPMAP_LINEAR"),
    CvarOption(cvar: "r_particles", label: "Particles", section: "Graphics",
               kind: .choice([Choice(label: "Round", value: "1"), Choice(label: "Classic squares", value: "2"), Choice(label: "Off", value: "0")]),
               defaultValue: "1"),
    CvarOption(cvar: "r_shadows", label: "Shadows under objects", section: "Graphics", kind: .toggle(on: "1", off: "0"), defaultValue: "0"),
    CvarOption(cvar: "r_lerpmodels", label: "Smooth model animation", section: "Graphics", kind: .toggle(on: "1", off: "0"), defaultValue: "1"),
    CvarOption(cvar: "r_lerpmove", label: "Smooth monster movement", section: "Graphics", kind: .toggle(on: "1", off: "0"), defaultValue: "1"),
    CvarOption(cvar: "r_scale", label: "Pixelation (retro)", section: "Graphics",
               kind: .choice([Choice(label: "Off", value: "1"), Choice(label: "2×", value: "2"), Choice(label: "3×", value: "3"), Choice(label: "4×", value: "4")]),
               defaultValue: "1", help: "Renders the image at a fraction of the resolution — the 1996 look."),
    CvarOption(cvar: "r_wateralpha", label: "Water transparency", section: "Graphics", kind: .slider(0.3...1, step: 0.05), defaultValue: "1",
               help: "On the original maps this requires an engine with transparent water support (QuakeSpasm/vkQuake have it)."),
    CvarOption(cvar: "gamma", label: "Brightness (gamma, lower = brighter)", section: "Graphics", kind: .slider(0.5...1.3, step: 0.05), defaultValue: "1"),
    CvarOption(cvar: "contrast", label: "Contrast", section: "Graphics", kind: .slider(1...2, step: 0.1), defaultValue: "1"),
    // HUD
    CvarOption(cvar: "scr_sbarscale", label: "Status bar scale", section: "HUD",
               kind: .choice([Choice(label: "1×", value: "1"), Choice(label: "2×", value: "2"), Choice(label: "3×", value: "3"), Choice(label: "4×", value: "4")]),
               defaultValue: "2"),
    CvarOption(cvar: "scr_menuscale", label: "Menu scale", section: "HUD",
               kind: .choice([Choice(label: "1×", value: "1"), Choice(label: "2×", value: "2"), Choice(label: "3×", value: "3"), Choice(label: "4×", value: "4")]),
               defaultValue: "2"),
    CvarOption(cvar: "scr_conscale", label: "Console scale", section: "HUD",
               kind: .choice([Choice(label: "1×", value: "1"), Choice(label: "2×", value: "2"), Choice(label: "3×", value: "3"), Choice(label: "4×", value: "4")]),
               defaultValue: "2"),
    CvarOption(cvar: "scr_sbaralpha", label: "Status bar opacity", section: "HUD", kind: .slider(0...1, step: 0.05), defaultValue: "0.75"),
    CvarOption(cvar: "scr_showfps", label: "FPS counter", section: "HUD", kind: .toggle(on: "1", off: "0"), defaultValue: "0"),
    // Dźwięk
    CvarOption(cvar: "volume", label: "Sound effects volume", section: "Sound", kind: .slider(0...1, step: 0.05), defaultValue: "0.7"),
    CvarOption(cvar: "bgmvolume", label: "Music volume", section: "Sound", kind: .slider(0...1, step: 0.05), defaultValue: "1"),
    // Multiplayer — sekcja ma własną zakładkę (PlayerTab), nie trafia do OptionsTab
    CvarOption(cvar: "name", label: "Player name", section: "Multiplayer", kind: .text(placeholder: "player"), defaultValue: ""),
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
