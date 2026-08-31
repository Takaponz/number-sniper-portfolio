import AVFoundation

/// 効果音と BGM が共有する `AVAudioSession` の設定。
///
/// `.ambient` カテゴリなので、消音スイッチと他アプリの音楽再生を尊重する
/// （消音中は BGM も効果音も鳴らない。音が無くてもゲームは成立する）。
///
/// バックグラウンドへ行くとセッションは非アクティブになり、前景復帰でも自動では戻らないことがある。
/// 何度呼んでも副作用が無いので、鳴らし直す側から都度呼んでよい。
enum GameAudioSession {
    static func activate() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // 音が鳴らないだけでゲームは続行できる
        }
    }
}
