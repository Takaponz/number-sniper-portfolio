import SwiftUI
import NumberSniperCore

extension UserDefaults: @retroactive KeyValueStore {}

@main
struct NumberSniperApp: App {
    private let scoreStore = ScoreStore(store: UserDefaults.standard)
    private let settingsStore = SettingsStore(store: UserDefaults.standard)

    var body: some Scene {
        WindowGroup {
            RootView(scoreStore: scoreStore, settingsStore: settingsStore)
        }
    }
}
