import CoreHaptics
import UIKit
import NumberSniperCore

/// 判定強度で使い分けるハプティクス。
/// ハプティクス非対応・無効な環境では何もしない（演出は視覚と効果音で成立させる）。
final class HapticsService {
    private let isAvailable = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)

    /// 設定シートの振動トグル。`SettingsViewModel` から push される。
    ///
    /// **`play(for:)` と `prepare()` の両方でガードする。** `prepare()` は
    /// `RootView.startGame()` から毎ゲーム呼ばれるので、片方だけだと OFF でも
    /// 触覚エンジンが起き続ける
    var isEnabled = true

    /// ラウンド開始時に呼ぶ。初回発火の遅延を避けるため。
    func prepare() {
        guard isAvailable, isEnabled else { return }
        for generator in [heavy, medium, light, rigid] {
            generator.prepare()
        }
    }

    func play(for judgement: Judgement) {
        guard isAvailable, isEnabled else { return }
        switch judgement {
        case .perfect: heavy.impactOccurred(intensity: 1.0)
        case .great: medium.impactOccurred(intensity: 0.8)
        case .good: light.impactOccurred(intensity: 0.6)
        case .miss: rigid.impactOccurred(intensity: 0.9)
        }
        prepare()
    }
}
