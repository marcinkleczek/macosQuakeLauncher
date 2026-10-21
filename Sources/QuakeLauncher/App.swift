import SwiftUI

@main
struct QuakeLauncherApp: App {
    @StateObject private var model = LauncherModel()
    @StateObject private var browser = BrowserModel()
    @StateObject private var moddb = ModDBModel()
    @StateObject private var slipseer = SlipSeerModel()
    @StateObject private var registry = InstallRegistry()

    init() {
        // proste cudzysłowy/myślniki w polu parametrów (jak w QuakeConfig)
        UserDefaults.standard.set(false, forKey: "NSAutomaticQuoteSubstitutionEnabled")
        UserDefaults.standard.set(false, forKey: "NSAutomaticDashSubstitutionEnabled")
    }

    var body: some Scene {
        WindowGroup("Quake Launcher") {
            ContentView(model: model, registry: registry)
                .task { registry.migrateIfNeeded(base: model.baseDir) }
        }
        .windowResizability(.contentSize)

        Window("Maps — Quaddicted", id: "maps") {
            MapBrowserView(launcher: model, browser: browser, registry: registry)
        }

        Window("ModDB", id: "moddb") {
            ModDBBrowserView(launcher: model, browser: moddb, registry: registry)
        }

        Window("SlipSeer", id: "slipseer") {
            SlipSeerView(launcher: model, browser: slipseer, registry: registry)
        }

        Window("Downloaded", id: "library") {
            LibraryView(launcher: model, registry: registry)
        }
    }
}
