import SwiftUI
import NumberSniperCore

/// 目盛りのない数直線とカーソル。両端の値だけを表示する。
///
/// 0〜1 以外の変則レンジのときは、**線そのものの見た目を変えて明示する**
/// （レンジ表示のチップ・端の色・端の目印）。0〜1 だと思い込んだまま狙って
/// しまうのを防ぐのが目的で、値を小さく添えるだけでは足りない。
struct NumberLineView: View {
    let range: LineRange
    /// 描画時刻 → カーソル位置比率
    let cursorRatio: (TimeInterval) -> Double
    /// 判定確定後だけ渡す。プレイ中は nil
    let targetRatio: Double?
    /// カーソルを描くか。時間切れのときだけ false（詳細は `GameViewModel.showsCursor`）
    var showsCursor: Bool = true
    /// 練習モードの目盛。**本編では常に空**で、空なら描画は 1px も変わらない
    var ticks: [LineTick] = []
    /// 描画を止めるか。カーソルが凍結していて描画内容が毎フレーム同一になる区間で true にする。
    ///
    /// 本編は判定後 `GameConfig.interRoundPauseSeconds` で次ラウンドに進むので既定の false のままでよいが、
    /// 練習モードは制限時間も自動送りも無く、プレイヤーがズレを読んでいる間ずっと静止画面を
    /// リフレッシュレートで描き続けてしまう
    var isPaused: Bool = false

    private let markerWidth: CGFloat = 4
    private let lineHeight: CGFloat = 6
    private let endTickHeight: CGFloat = 22
    /// チップの有無で数直線が上下に動かないよう、常にこの高さを確保する
    private let captionSlotHeight: CGFloat = 30

    /// 変則レンジを表す色。0〜1 のときは本文色のまま
    private var accent: Color { range.isUnit ? .primary : .orange }

    var body: some View {
        VStack(spacing: 10) {
            captionSlot

            TimelineView(.animation(paused: isPaused)) { context in
                GeometryReader { geometry in
                    let width = geometry.size.width
                    let ratio = cursorRatio(context.date.timeIntervalSinceReferenceDate)

                    ZStack(alignment: .leading) {
                        // 目盛線はマーカーの背面に敷く。マーカーの Capsule は
                        // frame(width:) だけで高さ未指定なので ZStack の全高を占め、
                        // 後ろに置かないとカーソルが目盛に隠れる。
                        // `.background` 修飾子ではなく ZStack の先頭の子として入れること
                        // （既定 alignment が .center になり、leading 基準の offset が半幅ずれる）
                        ForEach(ticks, id: \.index) { tick in
                            tickLine()
                                .offset(x: width * tick.ratio - markerWidth / 2)
                        }

                        Capsule()
                            .fill(.secondary.opacity(0.25))
                            .frame(height: lineHeight)
                            .frame(maxHeight: .infinity, alignment: .center)

                        // 端の目印。線のどこからどこまでがレンジなのかを視覚的に閉じる
                        endTick()
                        endTick()
                            .offset(x: width - markerWidth)

                        if let targetRatio {
                            marker(color: .green)
                                .offset(x: width * targetRatio - markerWidth / 2)
                        }

                        if showsCursor {
                            marker(color: .primary)
                                .offset(x: width * ratio - markerWidth / 2)
                        }
                    }
                }
            }
            .frame(height: 80)

            // 目盛ラベル。空のときは行ごと消えるので VStack の spacing も発生しない
            if !ticks.isEmpty {
                tickLabels
            }

            HStack {
                RangeLabel(text: range.lowerLabel, color: accent)
                Spacer()
                RangeLabel(text: range.upperLabel, color: accent)
            }
        }
    }

    /// 目盛の実数値ラベル。3 桁レンジで `209.25` が 3 個並ぶので、
    /// 固定幅スロット ＋ 等幅数字 ＋ 縮小で吸収する
    private var tickLabels: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let slotWidth = width / CGFloat(max(1, ticks.count) + 1)
            ZStack(alignment: .leading) {
                ForEach(ticks, id: \.index) { tick in
                    Text(tick.value.trimmedText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: slotWidth)
                        .offset(x: width * tick.ratio - slotWidth / 2)
                }
            }
        }
        .frame(height: 16)
    }

    /// レンジ明示チップ。変則レンジのときだけ中身が入る（高さは常に確保する）
    private var captionSlot: some View {
        ZStack {
            if let caption = AppStrings.rangeCaption(range) {
                Text(caption)
                    .font(.subheadline.weight(.heavy).monospacedDigit())
                    .foregroundStyle(accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(accent.opacity(0.16)))
                    .overlay(Capsule().strokeBorder(accent.opacity(0.55), lineWidth: 1.5))
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .frame(height: captionSlotHeight)
        .animation(.spring(duration: 0.3), value: range)
    }

    /// 練習モードの目盛線。マーカーより細く薄くして、カーソル・目標と読み違えないようにする
    private func tickLine() -> some View {
        Capsule()
            .fill(.secondary.opacity(0.45))
            .frame(width: markerWidth, height: endTickHeight * 1.6)
    }

    private func endTick() -> some View {
        Capsule()
            .fill(accent.opacity(range.isUnit ? 0.35 : 0.9))
            .frame(width: markerWidth, height: endTickHeight)
    }

    private func marker(color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: markerWidth)
    }
}

/// 数直線の端の値。**変わったことに気づけること**が最優先なので、
/// 小さい灰色文字ではなく太字で出し、値が変わった瞬間だけ大きさで注意を引く。
private struct RangeLabel: View {
    let text: String
    let color: Color

    @State private var isHighlighted = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Text(text)
            .font(.title3.weight(.bold).monospacedDigit())
            .foregroundStyle(color)
            .scaleEffect(isHighlighted ? 1.3 : 1.0)
            .onChange(of: text) {
                resetTask?.cancel()
                isHighlighted = true
                resetTask = Task {
                    // `true` と `false` を同じ更新サイクルで書くと、SwiftUI は最終値
                    // （false）しか見ないのでアニメーションが一切走らない。
                    // 1 フレーム待って別サイクルにしてから戻す
                    try? await Task.sleep(for: .milliseconds(16))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.5)) { isHighlighted = false }
                }
            }
    }
}

#Preview("0〜1") {
    NumberLineView(
        range: .unit,
        cursorRatio: { time in CursorClock.ratio(elapsed: time, sweepDuration: 2.0) },
        targetRatio: 0.74
    )
    .padding()
}

#Preview("変則レンジ") {
    NumberLineView(
        range: .integers(lower: 13, upper: 63),
        cursorRatio: { time in CursorClock.ratio(elapsed: time, sweepDuration: 2.0) },
        targetRatio: 0.74
    )
    .padding()
}
