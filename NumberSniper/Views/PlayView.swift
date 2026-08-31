import SwiftUI
import NumberSniperCore
#if DEBUG
import UIKit  // ProMotion 計器で UIScreen.maximumFramesPerSecond を読むためだけ（DEBUG 限定）

/// プレイ画面のリフレッシュレート計器（黄色の `… Hz  min … / max …  上限 …`）を出すか。**既定は false**。
///
/// もともとは ProMotion のオプトインが効いているかを実機で見るための常設計器だったが、
/// **ProMotion は 2026-08-05 に打ち切り済み**（実機は 60Hz 張り付きで決着）なので、
/// 常設しておく理由はもう無く、実機の目視確認では画面を塞ぐ側の存在になった。
///
/// **計測ロジック（`GameViewModel` の `recentFrameIntervals` / `measuredRefresh`）は残してある。**
/// `GameConfig.inputLatencyCompensationSeconds` の較正が未着手で、Lv12 の PERFECT 窓は
/// 全幅 27ms しかない。「見えていた位置で止まらない」が出たときにコマ落ちかどうかを
/// 切り分ける手段はこの計器だけなので、疑うときはここを `true` にして Debug ビルドを入れ直す。
private let showsRefreshInstrument = false
#endif

struct PlayView: View {
    let viewModel: GameViewModel

    var body: some View {
        VStack(spacing: 0) {
            TimeLimitBarView(remainingRatio: viewModel.remainingRatio(at:))

            statusBar
                .padding(.horizontal, 24)
                .padding(.top, 12)

            Spacer(minLength: 0)

            ZStack {
                Text(viewModel.displayedQuestion.promptText)
                    .font(.system(size: 76, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .padding(.horizontal, 24)
                    // お題が切り替わったことに気づけるよう、毎回入れ直す。
                    // 目印は表示文字列ではなくラウンド番号にする（`1/2` が 2 問続いても、
                    // 同じ数字が別レンジで出ても、確実に「変わった」と認識させるため）
                    .id(viewModel.roundIndex)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))

                if let result = viewModel.lastResult, viewModel.frozenCursorRatio != nil {
                    JudgementBadgeView(result: result)
                }
            }
            .frame(height: 130)
            .animation(.spring(duration: 0.25), value: viewModel.frozenCursorRatio)
            .animation(.spring(duration: 0.3), value: viewModel.roundIndex)

            Spacer(minLength: 0)

            NumberLineView(
                range: viewModel.displayedQuestion.range,
                cursorRatio: viewModel.cursorRatio(at:),
                targetRatio: viewModel.revealedTargetRatio,
                showsCursor: viewModel.showsCursor
            )
            .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .overlay {
            if case .countdown(let remaining) = viewModel.phase {
                CountdownOverlayView(remaining: remaining)
            }
            if case .continueOffer(let remaining) = viewModel.phase {
                ContinueOfferOverlayView(
                    remaining: remaining,
                    score: viewModel.engine.score,
                    isPresentingAd: viewModel.isPresentingRewardedAd,
                    onAccept: { Task { await viewModel.acceptContinue() } },
                    onDecline: { viewModel.declineContinue() }
                )
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in viewModel.touchDown() }
                .onEnded { _ in viewModel.touchUp() },
            including: viewModel.phase == .playing ? .all : .none
        )
    }

    private var statusBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                ForEach(0..<GameConfig.initialLives, id: \.self) { index in
                    Image(systemName: index < viewModel.engine.lives ? "heart.fill" : "heart")
                        .foregroundStyle(.pink)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(viewModel.engine.score)")
                    .font(.title2.weight(.bold).monospacedDigit())
                HStack(spacing: 8) {
                    Text(AppStrings.level(viewModel.engine.level))
                    if viewModel.engine.combo > 0 {
                        Text(AppStrings.combo(viewModel.engine.combo))
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)

                #if DEBUG
                // ProMotion が効いているかを実機で見るための計器（DEBUG かつ
                // `showsRefreshInstrument` が true のときだけ）。
                // 中央値だけでなく最遅も出す。中央値 120 でも最遅が 60 ならコマ落ちしている。
                //
                // 自前の 0.5 秒周期で引きに行く。`measuredRefresh` は毎フレーム書き換わるので
                // 観測対象にはできない（`GameViewModel` 側の注記）。プレイしながら目視で読む
                // 計器なので 2 回/秒で足りるし、数字が暴れず逆に読みやすい。
                // 位相の起点は View の外（`instrumentEpoch`）から渡す。ここで `.now` を作ると
                // body 再評価のたびに位相がリセットされて周期が成立しない。
                //
                // 出さないときは `TimelineView` ごと作らない（= 0.5 秒周期の再評価も走らない）。
                if showsRefreshInstrument {
                    TimelineView(.periodic(from: viewModel.instrumentEpoch, by: 0.5)) { _ in
                        if let hz = viewModel.measuredRefresh {
                            // 「上限」は `UIScreen.main.maximumFramesPerSecond` ＝ システムが報告するディスプレイ上限。
                            // API のセマンティクス上は plist のオプトインの成否と無関係に返る値で、
                            // ProMotion 機なら 120 になる（＝ 120 と出ても「キーが効いた証拠」にはならない。
                            // ただし下記のとおり上限側が下がる場合がある）。
                            // ※これは API の理解であって実測ではない — キー未投入での実測はこのリポに無い。
                            //
                            // 2026-08-05 の実機実測（iPhone 16 Pro / iOS 26.5.2、フレームレート制限・低電力モードとも OFF）:
                            //   `CADisableMinimumFrameDuration` / `…OnPhone` のどちらでも 実測 60Hz 張り付き
                            //   `maximumFramesPerSecond` は 120
                            // **OS がキャップしているのか、描画が 8.33ms のフレーム予算に間に合っていないのかは
                            // 切り分けていない**（キー名の Apple 一次情報での照合も未了。60Hz 前提の設計に倒して深追いを打ち切った）。
                            // 潰していない仮説が 2 つ残っている状態なので、ここを見て「描画が重い」と決めて
                            // チューニングに走らないこと。
                            //
                            // つまり ProMotion 機で「上限 120・中央値 60」は既知の状態であって異常ではない。
                            // 読む値は「中央値が 60 付近で**安定**しているか」「min が 60 を割っていないか」だけでよい。
                            // 上限が 60 と出るのは ProMotion 非搭載機（iPhone SE 等）か、端末のフレームレート制限・
                            // 低電力モードが ON のとき（描画の遅さではなく上限側の値が下がっている）**と考えられる
                            // — いずれも未実測**。低電力モード ON での Hz 実測は**未実施**
                            // 低電力モード ON での Hz 実測は未実施なので、推測を実測値として扱わない。
                            Text(String(
                                format: "%.0f Hz  min %.0f / max %.0f  上限 %d",
                                hz.median, hz.slowest, hz.fastest,
                                UIScreen.main.maximumFramesPerSecond
                            ))
                                .font(.footnote.weight(.bold).monospacedDigit())
                                .foregroundStyle(.yellow)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                #endif
            }
        }
    }
}
