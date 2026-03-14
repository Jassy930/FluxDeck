import SwiftUI

@main
struct FluxDeckNativeApp: App {
    @AppStorage("fluxdeck.native.language_preference") private var persistedLanguagePreference = AppLanguage.system.storageValue

    private var resolvedLocale: Locale {
        AppLanguage.from(storageValue: persistedLanguagePreference).resolvedLocale
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, resolvedLocale)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}
