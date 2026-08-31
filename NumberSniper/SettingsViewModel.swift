import Foundation
import NumberSniperCore

/// 設定シートのトグル 3 つと `SettingsStore` の橋渡し。
/// 既定値と永続化の判断は持たず（Core の `SettingsStore` にある）、
/// 「トグルが倒れたら書き戻してサービスへ push する」だけを持つ。
///
/// - Important: **格納プロパティ ＋ `didSet` で書き戻す。`store` の値を返す
///   computed property にしてはいけない。** `@Observable` は格納プロパティしか追跡しないので、
///   computed だとトグルを倒しても View が再描画されない（値は永続化されるため
///   「再起動すると反映されている」という分かりにくい形で出る）。
@Observable
final class SettingsViewModel {
    /// サービスへ反映するための穴。`GameViewModel.onRoundJudged` と同じ形で、
    /// この型はサービスを直接知らないまま `RootView` が埋める
    @ObservationIgnored var onBGMEnabledChanged: ((Bool) -> Void)?
    @ObservationIgnored var onSoundEnabledChanged: ((Bool) -> Void)?
    @ObservationIgnored var onHapticsEnabledChanged: ((Bool) -> Void)?

    @ObservationIgnored private let store: SettingsStore

    var isBGMEnabled: Bool {
        didSet {
            store.isBGMEnabled = isBGMEnabled
            onBGMEnabledChanged?(isBGMEnabled)
        }
    }

    var isSoundEnabled: Bool {
        didSet {
            store.isSoundEnabled = isSoundEnabled
            onSoundEnabledChanged?(isSoundEnabled)
        }
    }

    var isHapticsEnabled: Bool {
        didSet {
            store.isHapticsEnabled = isHapticsEnabled
            onHapticsEnabledChanged?(isHapticsEnabled)
        }
    }

    init(store: SettingsStore) {
        self.store = store
        self.isBGMEnabled = store.isBGMEnabled
        self.isSoundEnabled = store.isSoundEnabled
        self.isHapticsEnabled = store.isHapticsEnabled
    }
}
