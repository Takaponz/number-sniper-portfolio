import SwiftUI
import NumberSniperCore

/// **タイトルとリザルト**の右上の歯車から開く設定シート（リザルト側は 2026-08-26 追加）。
/// BGM / 効果音 / 振動のオンオフだけを持つ。**プレイ中・練習モードからは開けない**
/// （ポーズボタンを置かない方針と整合）。歯車の見た目の正本は `SettingsGearOverlay.swift`。
/// 変更は即時反映（`SettingsViewModel` の `didSet` がサービスへ push する）。
struct SettingsView: View {
    @Bindable var settings: SettingsViewModel
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Toggle(AppStrings.settingsBGM, isOn: $settings.isBGMEnabled)
                Toggle(AppStrings.settingsSound, isOn: $settings.isSoundEnabled)
                Toggle(AppStrings.settingsHaptics, isOn: $settings.isHapticsEnabled)
            }
            .navigationTitle(AppStrings.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.settingsDone, action: onDone)
                }
            }
        }
    }
}

#Preview {
    // **`UserDefaults.standard` を渡さない。** プレビューでトグルを倒すと `didSet` 経由で
    // 実アプリの設定に書き込まれ、同じシミュレータで動かしている本体と混ざる
    SettingsView(
        settings: SettingsViewModel(
            store: SettingsStore(store: UserDefaults(suiteName: "preview.settings") ?? .standard)
        ),
        onDone: {}
    )
}
