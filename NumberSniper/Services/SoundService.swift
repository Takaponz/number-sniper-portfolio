import AVFoundation
import NumberSniperCore

/// 判定別の効果音。
/// セッション設定は `GameAudioSession`（BGM と共有）。
final class SoundService {
    /// 探す拡張子。**この順で最初に見つかったものを使う。**
    /// 収録済みの素材は m4a、まだプレースホルダのままの判定は wav で混在している
    private static let extensions = ["m4a", "wav"]

    private var players: [Judgement: AVAudioPlayer] = [:]

    /// 設定シートの効果音トグル。`SettingsViewModel` から push される。
    ///
    /// **ガードは鳴らす側（`play(for:)`）に 1 箇所だけ置く。** 呼び出し口は
    /// `RootView` の本編・練習の 2 経路あり、呼び出し側で `if isSoundEnabled` と書く形だと
    /// 片方を書き忘れても静かに鳴り続けるだけでテストにも掛からない
    var isEnabled = true

    init() {
        GameAudioSession.activate()
        // **OFF でもここで読み込んでおく。** 遅延ロードにすると ON へ戻した最初の 1 発が鳴らない
        for judgement in Judgement.allCases {
            players[judgement] = makePlayer(named: judgement.rawValue)
        }
    }

    func play(for judgement: Judgement) {
        guard isEnabled else { return }
        guard let player = players[judgement] else { return }
        player.currentTime = 0
        player.play()
    }

    private func makePlayer(named name: String) -> AVAudioPlayer? {
        let url = Self.extensions.lazy
            .compactMap { Bundle.main.url(forResource: name, withExtension: $0) }
            .first
        guard let url else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        return player
    }
}
