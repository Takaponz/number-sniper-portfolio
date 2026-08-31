import Testing
import Foundation
@testable import NumberSniperCore

@Suite("音・振動の設定")
struct SettingsStoreTests {
    /// **既定 ON の唯一の検出器。**
    /// 既定値を `store.bool(forKey:)` 型に書き換えた瞬間にここが落ちる
    /// （`UserDefaults.bool(forKey:)` は未設定キーで false を返すため）。
    @Test("空ストアでは 3 つとも ON")
    func defaultsAreAllOn() {
        let settings = SettingsStore(store: InMemoryKeyValueStore())
        #expect(settings.isBGMEnabled)
        #expect(settings.isSoundEnabled)
        #expect(settings.isHapticsEnabled)
    }

    @Test("false を書いて読み戻せる")
    func writesAndReadsBackFalse() {
        let settings = SettingsStore(store: InMemoryKeyValueStore())
        settings.isBGMEnabled = false
        settings.isSoundEnabled = false
        settings.isHapticsEnabled = false
        #expect(settings.isBGMEnabled == false)
        #expect(settings.isSoundEnabled == false)
        #expect(settings.isHapticsEnabled == false)
    }

    /// キーの取り違え（コピペで `Key.bgm` が 3 つ並ぶ）を弁別する。
    /// 「false を書いて読み戻せる」だけだと 3 つが同じキーを指していても素通りする。
    @Test("1 つを OFF にしても他の 2 つは ON のまま")
    func togglesAreIndependent() {
        for target in 0..<3 {
            let settings = SettingsStore(store: InMemoryKeyValueStore())
            switch target {
            case 0: settings.isBGMEnabled = false
            case 1: settings.isSoundEnabled = false
            default: settings.isHapticsEnabled = false
            }
            #expect(settings.isBGMEnabled == (target != 0))
            #expect(settings.isSoundEnabled == (target != 1))
            #expect(settings.isHapticsEnabled == (target != 2))
        }
    }

    @Test("OFF から ON へ戻せる")
    func togglesBackOn() {
        let settings = SettingsStore(store: InMemoryKeyValueStore())
        settings.isBGMEnabled = false
        settings.isBGMEnabled = true
        #expect(settings.isBGMEnabled)

        settings.isSoundEnabled = false
        settings.isSoundEnabled = true
        #expect(settings.isSoundEnabled)

        settings.isHapticsEnabled = false
        settings.isHapticsEnabled = true
        #expect(settings.isHapticsEnabled)
    }

    /// **このストアが存在する理由そのものの検出器。**
    /// 同一インスタンス内で書き→読みするテストだけだと、`SettingsStore` にメモリキャッシュ
    /// （`private var cachedBGM: Bool?` 等）を足しても全部通ったまま、実機だけ
    /// 「再起動で設定が既定に戻る」形で壊れる。`ScoreStore` 側の
    /// `gameOverCountSurvivesRestart`（`ScoreStoreTests.swift:104-108`）と同じ形。
    @Test("設定は永続化され、再起動で復元される")
    func settingsSurviveRestart() {
        let backing = InMemoryKeyValueStore()
        SettingsStore(store: backing).isBGMEnabled = false
        SettingsStore(store: backing).isSoundEnabled = false
        // 別インスタンス = 再起動相当
        let restarted = SettingsStore(store: backing)
        #expect(restarted.isBGMEnabled == false)
        #expect(restarted.isSoundEnabled == false)
        #expect(restarted.isHapticsEnabled)  // 触っていないものは既定 ON のまま
    }

    /// 書いて読み戻すテストだけではキー文字列の回帰を弁別できない
    /// （3 キーを対称にリネームしても全部通る）。そのままアップデートすると
    /// 既存ユーザーの設定が黙って既定 ON に戻るので、キーを直接固定する。
    /// 公開済みアプリとの互換性のため、次の3キーを永続化契約として固定する。
    @Test("永続化キーは互換性契約の文字列と一致する")
    func usesSpecifiedKeys() {
        let backing = InMemoryKeyValueStore()
        backing.set(false, forKey: "number_sniper.bgm_enabled")
        backing.set(false, forKey: "number_sniper.sound_enabled")
        backing.set(false, forKey: "number_sniper.haptics_enabled")
        let settings = SettingsStore(store: backing)
        #expect(settings.isBGMEnabled == false)
        #expect(settings.isSoundEnabled == false)
        #expect(settings.isHapticsEnabled == false)
    }
}
