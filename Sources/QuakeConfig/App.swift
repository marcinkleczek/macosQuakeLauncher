import SwiftUI

@main
struct QuakeConfigApp: App {
    init() {
        // wyłącz "inteligentne" podmiany macOS w polach tekstowych — komendy Quake'a
        // wymagają prostych cudzysłowów i myślników (zapis do domeny aplikacji
        // wygrywa z ustawieniem systemowym)
        UserDefaults.standard.set(false, forKey: "NSAutomaticQuoteSubstitutionEnabled")
        UserDefaults.standard.set(false, forKey: "NSAutomaticDashSubstitutionEnabled")
    }

    var body: some Scene {
        WindowGroup("Quake Config Editor") {
            ConfigView()
        }
    }
}
