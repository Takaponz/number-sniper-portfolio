import AVFoundation

/// 画面に応じた BGM のループ再生。
///
/// 本編（タイトル・プレイ・リザルト）は 1 曲を通しで鳴らし続け、練習モードの間だけ専用曲に差し替える。
/// **同じ曲が続く画面遷移では頭出しし直さない** — このゲームはリザルトとプレイを何度も往復するので、
/// 画面が変わるたびにイントロへ戻ると曲がまったく進まない。
///
/// 再生を抑える理由は 4 つあり（バックグラウンド・他アプリの音楽・広告表示中・ユーザー設定）、
/// **どれか一つでも立っていれば鳴らさない**。
/// 個別に `play()` / `pause()` を呼び合うとある理由の解除が別の理由を踏み越えるので、
/// 「鳴らしたい曲（`currentTrack`）」と「今鳴らしてよいか（`canPlay`）」を分けて持つ。
///
/// ⚠️ **抑止の理由を増やすときは専用のフラグを足して `canPlay` に AND する。**
/// `pause()` / `resume()` は `isSuspendedByScene` 専用で、流用すると理由が交差したときに壊れる
/// （例: 広告表示中に背面へ行って戻ると、`resume()` が広告用の抑止まで解除してしまう）。
final class BGMService {
    /// 流す曲。`rawValue` はバンドル内のファイル名（拡張子なし）
    enum Track: String {
        /// 本編。タイトル → プレイ → リザルトを通して流す
        case main = "bgm_main"
        /// 練習モード専用
        case practice = "bgm_practice"
    }

    /// 他アプリの音楽の開始・終了を伝える通知。View の `.onReceive` に渡して
    /// `handleOtherAudioHint(_:)` へ流す（View 側に AVFoundation の知識を出さないための入口）。
    ///
    /// `receive(on:)` は必須。`AVAudioSession` の通知はメインスレッド配送が保証されず、
    /// この型は MainActor 隔離なので、配送元スレッドのまま触ると隔離を跨いで状態を書き換えることになる
    static let otherAudioHintPublisher = NotificationCenter.default
        .publisher(for: AVAudioSession.silenceSecondaryAudioHintNotification)
        .receive(on: DispatchQueue.main)

    /// BGM の音量。素材の実測 RMS は BGM が -13.6dB 前後、収録済みの判定音が -15.6〜-17.9dB で、
    /// 等倍で重ねると BGM のほうが大きくなる。判定音を埋もれさせないため下げてある
    private static let volume: Float = 0.25
    /// 曲を切り替えるときのフェード秒数。本編 ↔ 練習モードの遷移でしか使わない
    private static let fadeDuration: TimeInterval = 0.4

    private var players: [Track: AVAudioPlayer] = [:]
    /// 「今の画面で鳴らしたい曲」。抑止中でも保持する（抑止が解けたらこれを鳴らす）
    private var currentTrack: Track?
    /// バックグラウンドにいる間 true
    private var isSuspendedByScene = false
    /// 他アプリが音楽を鳴らしている間 true
    private var isSilencedByOtherAudio = false
    /// 広告（インタースティシャル / リワード）を表示している間 true
    private var isSuspendedByAd = false
    /// 設定シートで BGM を OFF にしている間 true
    private var isDisabledBySetting = false

    private var canPlay: Bool {
        !isSuspendedByScene && !isSilencedByOtherAudio && !isSuspendedByAd && !isDisabledBySetting
    }

    init() {
        GameAudioSession.activate()
        // 通知は状態が変わったときにしか来ない。music アプリを鳴らしたまま起動する経路のため初期値を取る。
        // **`isOtherAudioPlaying` ではなく `secondaryAudioShouldBeSilencedHint` を読む。**
        // 前者は他アプリのミックス可能な音声でも true になるが、その手の音声では
        // 対になる `.end` 通知が来ないので、抑止したまま二度と解除されない
        isSilencedByOtherAudio = AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
    }

    /// 指定の曲へ切り替える。すでにその曲を選んでいれば頭出しし直さない。
    func play(_ track: Track) {
        guard currentTrack != track else {
            // 同じ曲が続く画面遷移。頭出しはせず、止まっていたときだけ鳴らし直す
            if players[track]?.isPlaying == false { startCurrentIfAllowed() }
            return
        }

        // **状態を触る前にプレイヤを取る。** 先に `currentTrack` を進めてしまうと、
        // 読み込みに失敗したとき「currentTrack は新しい曲／`players` は空」で固定され、
        // 前の曲はフェードアウトで止まり、`play` は上の guard で早期 return、
        // 抑止解除の経路も `players[currentTrack]` が nil で弾かれる ─ 無音のまま二度と戻れなくなる。
        // 取れなければ現状維持（鳴っている曲をそのまま鳴らし続ける）のほうが縮退として上
        guard let player = player(for: track) else { return }

        let previous = currentTrack
        // フェードアウトの後始末は「まだこの曲が現役か」で判断するので、先に更新しておく
        currentTrack = track
        if let previous, let outgoing = players[previous] {
            fadeOutThenPause(outgoing, track: previous)
        }

        player.currentTime = 0
        player.volume = 0
        // 抑止中は頭出しだけしておく。解除されたら `startCurrentIfAllowed()` がここから鳴らす
        guard canPlay else { return }
        player.play()
        player.setVolume(Self.volume, fadeDuration: Self.fadeDuration)
    }

    /// バックグラウンドへ行くときに呼ぶ。
    /// `.ambient` セッションは背面で無音になるので、止めておかないと復帰時に位置がずれる
    func pause() {
        isSuspendedByScene = true
        pauseCurrent()
    }

    /// 前景復帰で呼ぶ。中断された位置から続ける。
    ///
    /// **他アプリ音声の状態をここで読み直す。** 抑止通知は前景のアクティブなセッションにしか来ないので、
    /// バックグラウンド中の変化は取り逃す。キャッシュしたフラグだけで判定すると
    /// (a) 背面にいる間に音楽を鳴らし始められた → 復帰と同時に BGM がその上に重なる、
    /// (b) 背面にいる間に音楽を止められた → 抑止が解除されず BGM が無音のまま戻らない、の両方が起きる
    func resume() {
        isSuspendedByScene = false
        // セッションを先に戻す。非アクティブなセッションのヒントは当てにならない
        GameAudioSession.activate()
        isSilencedByOtherAudio = AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
        if isSilencedByOtherAudio {
            pauseCurrent()
        } else {
            startCurrentIfAllowed()
        }
    }

    /// 広告を出す直前に呼ぶ。**`pause()` とは別のフラグで抑える。**
    ///
    /// `.ambient` は他の音とミックスするカテゴリなので、止めないと広告の音声と BGM が重なる
    /// （リワードは 15〜30 秒鳴り続ける）。`pause()` / `resume()` を流用しないのは、
    /// **広告表示中に背面へ行って戻ると `resume()` が広告側の抑止まで解除してしまう**ため
    /// （この型の冒頭に書いてある「抑止の理由を増やすときは専用のフラグを足して `canPlay` に AND する」）。
    func suspendForAd() {
        isSuspendedByAd = true
        pauseCurrent()
    }

    /// 広告が閉じたときに呼ぶ。**同じ位置から続ける**（頭出しし直さない）。
    ///
    /// 背面にいる間に広告が閉じた場合は `canPlay` が false のままなので鳴り出さない。
    /// 再開の実務は `startCurrentIfAllowed()` が持ち、その中の `GameAudioSession.activate()` が
    /// **広告 SDK にオーディオセッションのカテゴリを書き換えられていても戻す**
    func resumeFromAd() {
        isSuspendedByAd = false
        startCurrentIfAllowed()
    }

    /// 設定シートの BGM トグル。起動時の初期反映にも使う。**これも専用フラグで抑える**
    /// （`suspendForAd()` / `resumeFromAd()` と同じ形）。
    ///
    /// **ON へ戻すときは中断位置から続ける**（頭出しし直さない）。本編曲は 61.9 秒あり、
    /// 設定を触るたびにイントロへ戻ると曲がまったく進まない。
    ///
    /// - Important: **`play(_ track:)` の冒頭に「OFF なら return」を書いてはいけない。**
    ///   OFF 中に画面遷移（タイトル → 練習など）が起きると `currentTrack` が更新されず、
    ///   ON へ戻しても `startCurrentIfAllowed()` の `guard let currentTrack` で弾かれて
    ///   無音のまま戻らない（`play` の中の「状態を触る前にプレイヤを取る」注記と同型の壊れ方）。
    ///   抑止は `canPlay` に任せる ─ `play` は `currentTrack` の更新とプレイヤ読み込みを
    ///   済ませてから `guard canPlay` で止まるので、頭出し済みの状態で待てる
    func setEnabled(_ isEnabled: Bool) {
        isDisabledBySetting = !isEnabled
        if isEnabled {
            startCurrentIfAllowed()
        } else {
            pauseCurrent()
        }
    }

    /// 他アプリの音楽が鳴り始めた／止まったときに呼ぶ。
    /// **BGM だけ止める**（判定音は従来どおり鳴らす ─ 効果音は一瞬なので重なっても邪魔にならない）
    func handleOtherAudioHint(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt,
              let hint = AVAudioSession.SilenceSecondaryAudioHintType(rawValue: raw) else { return }
        isSilencedByOtherAudio = (hint == .begin)
        if isSilencedByOtherAudio {
            pauseCurrent()
        } else {
            startCurrentIfAllowed()
        }
    }

    private func pauseCurrent() {
        guard let currentTrack, let player = players[currentTrack] else { return }
        player.pause()
    }

    private func startCurrentIfAllowed() {
        guard canPlay, let currentTrack, let player = players[currentTrack] else { return }
        GameAudioSession.activate()
        // フェードの途中で止められていると音量が 0 のままなので必ず戻す
        player.volume = Self.volume
        player.play()
    }

    /// 初回だけ読み込む。練習モードの曲は練習に入るまで載せない。
    ///
    /// `AVAudioPlayer` はファイル全体を展開せずストリーム再生するので、**この生成コストは
    /// ファイルサイズにほぼ依存しない** — Mac 実測で 1.3MB の本編曲 7.5ms / 2.7MB の練習曲 6.6ms /
    /// 41KB の効果音 6.7ms（`init` + `prepareToPlay()`、5 回の最小値）。
    /// 画面遷移フレームでの同期実行だが、init へ先読みしても同じコストが起動時に移るだけなので遅延のまま置く
    private func player(for track: Track) -> AVAudioPlayer? {
        if let existing = players[track] { return existing }
        guard let url = Bundle.main.url(forResource: track.rawValue, withExtension: "m4a"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.numberOfLoops = -1
        player.prepareToPlay()
        players[track] = player
        return player
    }

    private func fadeOutThenPause(_ player: AVAudioPlayer, track: Track) {
        player.setVolume(0, fadeDuration: Self.fadeDuration)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.fadeDuration))
            // フェードの最中に元の曲へ戻っていたら止めない
            if let self, self.currentTrack == track { return }
            player.pause()
            player.currentTime = 0
        }
    }
}
