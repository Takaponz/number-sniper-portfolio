import Foundation

/// BGM・効果音・振動（ハプティクス）のオンオフ。**既定は 3 つとも ON**。
///
/// 永続化は `ScoreStore` と同じ `KeyValueStore`（`ScoreStore.swift:10-17`）を使う。
/// 既定値の判断を Core に置くのは、アプリターゲットにテストターゲットが無く、
/// あちらに書くと自動テストで固定できないため（`PracticeViewModel.swift:6-8` と同じ理由）。
///
/// - Important: **既定 ON は `object(forKey:) as? Bool ?? true` で書く。
///   `KeyValueStore` に `bool(forKey:)` を足してはいけない。**
///   `UserDefaults.bool(forKey:)` は未設定キーで `false` を返すので、空 extension
///   （`NumberSniperApp.swift:4`）で適合させた瞬間に「初回起動で 3 つとも OFF」になる。
///   しかも `InMemoryKeyValueStore`（`ScoreStoreTests.swift:5-16`）は手書きのスタブなので、
///   そこへ `values[key] as? Bool ?? true` と書くと**テストだけ通って実機で全 OFF** になる。
///   スタブと本物で既定が食い違う経路を作らないのが根本対処。`object(forKey:)` は
///   スタブも本物も未設定キーで nil を返すので食い違わない。
public final class SettingsStore {
    private enum Key {
        static let bgm = "number_sniper.bgm_enabled"
        static let sound = "number_sniper.sound_enabled"
        static let haptics = "number_sniper.haptics_enabled"
    }

    private let store: KeyValueStore

    public init(store: KeyValueStore) {
        self.store = store
    }

    public var isBGMEnabled: Bool {
        get { store.object(forKey: Key.bgm) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.bgm) }
    }

    public var isSoundEnabled: Bool {
        get { store.object(forKey: Key.sound) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.sound) }
    }

    public var isHapticsEnabled: Bool {
        get { store.object(forKey: Key.haptics) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.haptics) }
    }
}
