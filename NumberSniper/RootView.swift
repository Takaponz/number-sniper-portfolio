import SwiftUI
import NumberSniperCore

struct RootView: View {
    enum Route: Equatable {
        case title
        case play
        case result
        /// 練習モード。**レベルを Route に焼き込む**（`viewModel.engine.level` を都度読むと、
        /// 練習中に `restart` が走った場合に表示レベルが化ける）
        case practice(level: Int)
    }

    @State private var viewModel: GameViewModel
    @State private var settings: SettingsViewModel
    @State private var route: Route = .title
    @State private var isGameCenterReady = false
    /// 設定シートの提示。**`Route` は増やさない** — シートはモーダルであって画面遷移ではなく、
    /// `route` に混ぜると BGM の曲選び（`track(for:)`）まで巻き込む
    @State private var isShowingSettings = false
    @Environment(\.scenePhase) private var scenePhase

    private let scoreStore: ScoreStore
    private let haptics = HapticsService()
    private let sound = SoundService()
    private let bgm = BGMService()
    private let gameCenter: GameCenterService
    /// Public portfolio buildはネットワーク通信を行わないstubを既定にする。
    /// `AdMobService`は統合例として残すが、同意管理を実装して明示的に差し替えるまで起動しない。
    private let ads: any AdServing = StubAdService()

    init(scoreStore: ScoreStore, settingsStore: SettingsStore) {
        self.scoreStore = scoreStore
        self.gameCenter = GameCenterService(scoreStore: scoreStore)
        _viewModel = State(initialValue: GameViewModel(scoreStore: scoreStore))
        _settings = State(initialValue: SettingsViewModel(store: settingsStore))

        // 永続値のサービスへの初期反映は **`.onAppear` ではなくここで**行う。
        // `.onChange(of: route, initial: true)`（下）の初回 `bgm.play` より確実に前になり、
        // 「BGM を OFF にして終了 → 再起動で一瞬鳴ってから消える」を構造的に避けられる
        // （`.onAppear` と `.onChange(initial:)` の発火順に依存させない）
        haptics.isEnabled = settingsStore.isHapticsEnabled
        sound.isEnabled = settingsStore.isSoundEnabled
        bgm.setEnabled(settingsStore.isBGMEnabled)
    }

    var body: some View {
        Group {
            switch route {
            case .title:
                TitleView(
                    highScore: scoreStore.highScore,
                    onStart: startGame,
                    onShowRanking: isGameCenterReady ? { gameCenter.showLeaderboard() } : nil,
                    onShowSettings: { isShowingSettings = true }
                )
            case .play:
                PlayView(viewModel: viewModel)
            case .result:
                ResultView(
                    score: viewModel.engine.score,
                    highScore: scoreStore.highScore,
                    isNewBest: viewModel.outcome?.isNewBest ?? false,
                    onRetry: startGame,
                    onBackToTitle: { route = .title },
                    onShowRanking: isGameCenterReady ? { gameCenter.showLeaderboard() } : nil,
                    // 「今 Lv9 で死んだ」という文脈があるときだけ出す導線。
                    // `GameEngine.finish` は MISS で correctCount を増やさないので、
                    // ゲームオーバー時の level は最後にプレイしていたレベルのまま
                    onStartPractice: { route = .practice(level: viewModel.engine.level) },
                    onShowSettings: { isShowingSettings = true }
                )
            case .practice(let level):
                PracticeView(
                    level: level,
                    onRetry: startGame,
                    onBackToTitle: { route = .title },
                    onJudged: { [haptics, sound] judgement in
                        haptics.play(for: judgement)
                        sound.play(for: judgement)
                    }
                )
                // レベルが変われば View ごと（＝ ViewModel ごと）作り直す
                .id(level)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: route)
        // ~~タイトルからだけ開く~~ → **2026-08-26 にリザルトの歯車を追加**（タイトルとリザルトの 2 経路）。
        // 廃止理由: ゲームオーバー直後は「うるさいから切りたい」と思う場面そのもので、
        // そこから音を切るのにタイトルまで戻らせるのは遠い。**プレイ中には置かない**方針は不変
        // （ポーズボタンを置かない方針と整合）。
        //
        // ⚠ **広告と設定シートが干渉しないことの担保は、「シートはタイトルからのみ」ではない**
        // （リザルトに歯車を足したので前者の根拠はもう使えない）。実際の保証は次の 2 点:
        //
        // (a) `AdMobService.showInterstitialIfNeeded` の `defer { onPresentationChanged?(false) }` は
        //     **関数リターンの一部として走る**ので、こちらの `await` が再開して `route = .result` を
        //     代入する時点で `isSuspendedByAd` は既にクリアされている
        // (b) 広告はフルスクリーン VC なので、出ている間はリザルトの歯車にタッチが届かない
        //
        // ❌ **「リザルトが出た時点で広告は必ず閉じている」とは書けない。**
        // `AdMobService.presentationTimeout` のウォッチドッグが打ち切った場合、
        // `presentingAd` を nil 化して継続を resume するため、その後 SDK が遅れて出画すると
        // delegate が `=== presentingAd` で全て無視され、**広告が画面に出たまま `route = .result` が走る**。
        // それでも (a)(b) によりどちらの不変条件も壊れない。
        // リワード広告（復活）は `.continueOffer` フェーズ経由で `route` は `.play` のまま＝リザルトに来ていない。
        //
        // 3 つ目の抑止理由（広告）を触る変更を入れるときは、(a)(b) を測り直すこと
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(settings: settings, onDone: { isShowingSettings = false })
        }
        .onChange(of: viewModel.phase) { _, newPhase in
            if newPhase == .gameOver { presentInterstitialThenShowResult() }
        }
        .onAppear {
            viewModel.onRoundJudged = { [haptics, sound] result in
                haptics.play(for: result.judgement)
                sound.play(for: result.judgement)
            }
            // 設定シートのトグル → サービスへ push する穴。**呼び出し側で
            // `if settings.isSoundEnabled { ... }` と書く形にはしない** — 鳴らす口が
            // 本編・練習の 2 経路あり、片方を書き忘れても静かに鳴り続けるだけで気付けない。
            // ガードはサービス内に 1 箇所ずつ置いてある
            settings.onBGMEnabledChanged = { [bgm] isEnabled in bgm.setEnabled(isEnabled) }
            settings.onSoundEnabledChanged = { [sound] isEnabled in sound.isEnabled = isEnabled }
            settings.onHapticsEnabledChanged = { [haptics] isEnabled in haptics.isEnabled = isEnabled }
            gameCenter.onAuthenticationChanged = { isAuthenticated in
                isGameCenterReady = isAuthenticated
            }
            gameCenter.onPresentationChanged = { [viewModel] isPresenting in
                viewModel.isSuspendedByExternalUI = isPresenting
            }
            // 広告は音付きで、`.ambient` は他の音とミックスするので BGM も一緒に畳む。
            // `bgm.pause()` ではなく専用 API を使う（BGMService の注記参照）
            ads.onPresentationChanged = { [viewModel, bgm] isPresenting in
                viewModel.isSuspendedByExternalUI = isPresenting
                if isPresenting { bgm.suspendForAd() } else { bgm.resumeFromAd() }
            }
            // 復活オファーの穴 2 つ。ViewModel はサービスを知らないまま広告に繋がる
            viewModel.isRewardedAdReady = { [ads] in ads.isRewardedReady }
            viewModel.presentRewardedAd = { [ads] in await ads.showRewardedForContinue() }
            viewModel.onGameOver = { [gameCenter] outcome in
                // インタースティシャルはここでは出さない。表示は phase の変化を見ている
                // `presentInterstitialThenShowResult` の側（スコア送信と広告表示を絡めない）
                Task { await gameCenter.submitIfNeeded(outcome) }
            }
        }
        .task {
            // ATT ダイアログの処理が終わってから Game Center の認証を始める。
            // （authenticateHandler は代入時点で認証が走るため、システムアラートが競合する）
            await ads.start()
            gameCenter.startAuthentication()
            await gameCenter.flushPendingScores()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // 前景かどうかは**どの画面でも**伝える（route ガードの外に置く）。
            // 広告を待っている間の離席は、リザルト（インタースティシャル）でもプレイ画面
            // （リワード）でも起こりうる。ViewModel はこれを見て「戻ってきてから再開する」判断をする
            viewModel.setSceneActive(newPhase == .active)

            // BGM もどの画面でも要る（route ガードの外に置く）。
            // `.inactive` では止めない ─ コントロールセンターを引き下ろした程度で
            // 曲が切れるほうが不自然で、`.ambient` セッションが実際に無音になるのは背面へ行ってから
            switch newPhase {
            case .background: bgm.pause()
            case .active: bgm.resume()
            case .inactive: break
            @unknown default: break
            }

            if newPhase == .active {
                // 前景化の再試行はどの画面でも必要（route ガードの外に置く）。
                // バックグラウンド中に受け取った Game Center のサインイン UI は
                // 提示先が無く保留されているので、ここで出し直す
                gameCenter.didBecomeActive()
                // 起動時に出せなかった ATT ダイアログの出し直し
                Task { await ads.didBecomeActive() }
            }
            // 一時停止・復帰はプレイ画面でラウンド進行中のときだけ効く
            // （ViewModel 側でも二重にガードしている）
            guard route == .play else { return }
            switch newPhase {
            case .inactive, .background:
                viewModel.pauseForSceneChange()
            case .active:
                viewModel.resumeFromSceneChange()
            @unknown default:
                break
            }
        }
        // 他アプリが音楽を鳴らし始めたら BGM だけ止め、止まったら再開する
        // （判定音は鳴らし続ける。`.ambient` は他アプリ音声とミックスするカテゴリで、
        // 61.9 秒の曲を無限ループで重ね続けるのはユーザーの音楽の邪魔になる）
        .onReceive(BGMService.otherAudioHintPublisher) { bgm.handleOtherAudioHint($0) }
        .onChange(of: route, initial: true) { _, newRoute in
            bgm.play(track(for: newRoute))
            gameCenter.canPresentSignInUI = (newRoute == .title)
            // フェイルセーフ: プレイ画面に入る時点で外部UIは出ていないはずなので、
            // フラグが立ち残っていたら必ず落とす（立ちっぱなしになると
            // バックグラウンド復帰のカウントダウンが出なくなる）
            if newRoute == .play {
                viewModel.isSuspendedByExternalUI = false
            }
        }
    }

    /// 画面に対応する BGM。**本編の 3 画面は同じ曲**なので、タイトル ↔ プレイ ↔ リザルトの
    /// 往復では曲が切れずに鳴り続ける（`BGMService.play` が同じ曲を無視する）
    private func track(for route: Route) -> BGMService.Track {
        switch route {
        case .title, .play, .result: .main
        case .practice: .practice
        }
    }

    /// ゲームオーバー確定（復活オファーの決着後）の瞬間に**広告 → リザルト**の順で流す。
    /// 死んだ切れ目に出すほうが自然という実機の体感で、リザルト後（離脱ボタン）から移した
    /// （2026-08-23。経緯は ads spec の「なぜ『リザルトの後』なのか」節）。
    ///
    /// 出すかどうかの判断は Core が決めた `outcome.shouldShowInterstitial` に従う
    /// （復活したプレイは免除される）。`viewModel.outcome` は Optional なので、
    /// nil なら広告を出さずそのまま遷移する。
    ///
    /// 待っている間の二重発火は考えなくてよい — `phase` の `.gameOver` 遷移は 1 プレイに
    /// 1 回で、その間 `PlayView` のジェスチャは `.none`、リザルトのボタンはまだ画面に無い。
    /// 広告 API が返らないケースは `AdMobService.presentationTimeout` が打ち切って必ず返す
    private func presentInterstitialThenShowResult() {
        guard let outcome = viewModel.outcome else {
            route = .result
            return
        }
        Task {
            await ads.showInterstitialIfNeeded(outcome)
            route = .result
        }
    }

    /// タイトルの「はじめる」／リザルトの「もう一度」／練習モードの「はじめから挑戦」。
    /// `restart()` は常に Lv1 から始めるので、どの導線からでも同じ入口でよい
    private func startGame() {
        haptics.prepare()
        viewModel.restart()
        route = .play
        // 広告を待っている間に離席され、背面のまま遷移してきた場合。
        // `restart()` が張った制限時間が誰も見ていない画面で進むので、即座に一時停止側へ倒す
        // （復帰時に通常の 3 秒カウントダウンで再開される）。
        // **`scenePhase` ではなく ViewModel 側の値を見る** — この関数は広告待ちの Task から
        // 呼ばれることがあり、その Task が捕まえている View の `scenePhase` はタップ時点の古い値
        if !viewModel.isSceneActive {
            viewModel.pauseForSceneChange()
        }
    }
}
