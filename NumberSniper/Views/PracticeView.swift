import SwiftUI
import NumberSniperCore

/// 練習モード。目盛付き・制限時間なし・ライフなし・スコアなし。
///
/// 「目盛のない数直線で目測する」ための校正だけをさせる画面なので、
/// ズレを方向（←→）と実数値で見せる。カーソル速度は本編と同じ
/// （練習の感覚がそのまま本編に転移することが目的）。
struct PracticeView: View {
    let onRetry: () -> Void
    let onBackToTitle: () -> Void
    /// 判定演出の穴。**本編と同じ** `HapticsService` / `SoundService` を鳴らす
    let onJudged: (Judgement) -> Void

    /// ViewModel は View が所有する。呼び出し側で `.id(level)` を付ければ
    /// レベルが変わったときに View ごと（＝ ViewModel ごと）作り直される
    @State private var viewModel: PracticeViewModel

    @Environment(\.scenePhase) private var scenePhase

    init(
        level: Int,
        onRetry: @escaping () -> Void,
        onBackToTitle: @escaping () -> Void,
        onJudged: @escaping (Judgement) -> Void
    ) {
        self.onRetry = onRetry
        self.onBackToTitle = onBackToTitle
        self.onJudged = onJudged
        _viewModel = State(initialValue: PracticeViewModel(level: level))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 12)

            // 再生エリア。**タップジェスチャはこの subview にだけ貼る**
            // （ルートに貼ると下部のボタンがジェスチャに食われる）
            playArea
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in viewModel.touchDown() }
                        .onEnded { _ in viewModel.touchUp() }
                )

            buttons
                .padding(.horizontal, 40)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { viewModel.onJudged = onJudged }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { viewModel.resumeFromSceneChange() }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(AppStrings.practiceHeader(level: viewModel.level))
                .font(.headline.weight(.bold))
            Spacer()
            Text(AppStrings.practiceSolved(count: viewModel.solvedCount))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var playArea: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            ZStack {
                Text(viewModel.question.promptText)
                    .font(.system(size: 76, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .padding(.horizontal, 24)
                    // 目印は表示文字列ではなくラウンド番号にする（同じお題が 2 問続いても
                    // 確実に「変わった」と認識させるため）
                    .id(viewModel.roundIndex)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))

                if let result = viewModel.lastResult {
                    JudgementBadgeView(judgement: result.judgement)
                }
            }
            .frame(height: 130)
            .animation(.spring(duration: 0.25), value: viewModel.frozenCursorRatio)
            .animation(.spring(duration: 0.3), value: viewModel.roundIndex)

            offsetSlot

            Spacer(minLength: 0)

            NumberLineView(
                range: viewModel.question.range,
                cursorRatio: viewModel.cursorRatio(at:),
                targetRatio: viewModel.revealedTargetRatio,
                ticks: viewModel.ticks,
                // 判定表示中はカーソルが凍結して描画内容が変わらない。練習は制限時間が無く
                // この状態が数十秒続きうるので、描き続けさせない
                isPaused: viewModel.frozenCursorRatio != nil
            )
            .padding(.horizontal, 24)

            Spacer(minLength: 0)

            // 判定表示中だけ出す。高さは常に確保して画面が上下に動かないようにする
            ZStack {
                if viewModel.lastResult != nil {
                    Text(AppStrings.practiceNextHint)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 20)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// ズレの 2 段表示。判定バッジだけでは「どっちにどれだけ外したか」が分からず、
    /// 次のタップの補正量が決められない。高さは常に確保する
    private var offsetSlot: some View {
        ZStack {
            if let result = viewModel.lastResult {
                VStack(spacing: 2) {
                    Text(AppStrings.practiceOffset(result))
                        .font(.title.weight(.heavy).monospacedDigit())
                        .foregroundStyle(JudgementBadgeView.color(for: result.judgement))
                    // 副表示。実数値ズレが 0〜1 の小数になるお題でも量が掴めるよう、
                    // 全お題で共通の尺度として併記する。ぴったりのときは出さない
                    if result.direction != .exact {
                        Text(AppStrings.practiceOffsetPercent(result))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.scale(scale: 1.2).combined(with: .opacity))
            }
        }
        .frame(height: 56)
        // 2 本立てにする。`roundIndex` だけだと submit 時（`lastResult` が nil → 値）に
        // transaction が立たず、出現側の transition が一度も走らない
        .animation(.spring(duration: 0.25), value: viewModel.frozenCursorRatio)
        .animation(.spring(duration: 0.25), value: viewModel.roundIndex)
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            Button(action: onRetry) {
                Text(AppStrings.practiceRetry)
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)

            Button(action: onBackToTitle) {
                Text(AppStrings.backToTitle)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
        }
    }
}

// 目盛ラベルの可読性はプレビューで見る。DEBUG のレベルジャンプを廃止したので、
// 上級帯（Lv11-12 の 3 桁レンジ）はライフ 3 の通常プレイでは到達が現実的でなく、
// 実質ここでしか描画を確認できない
#Preview("Lv1（percent 単独帯）") {
    PracticeView(level: 1, onRetry: {}, onBackToTitle: {}, onJudged: { _ in })
}

#Preview("Lv9（変則レンジ）") {
    PracticeView(level: 9, onRetry: {}, onBackToTitle: {}, onJudged: { _ in })
}

#Preview("Lv11（3 桁レンジ）") {
    PracticeView(level: 11, onRetry: {}, onBackToTitle: {}, onJudged: { _ in })
}
