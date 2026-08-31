import Foundation

/// レベルとカーブからカーソルの片道スイープ時間を決める。
public enum SweepSchedule {
    /// S(lv) = max(S_min, S0 × r^(lv−1))。往復周期は 2 × S。
    ///
    /// S0（初速）は `GameConfig.baseSweepSeconds`。カーブが持つのは減衰率 r と下限 S_min だけで、
    /// 初速は意図的にカーブの外に置いてある（速さそのものを難易度差にしないため）。
    ///
    /// S_min は判定窓がフレーム格子に埋もれないためにある。採点は `GameViewModel.lastDrawnTime`
    /// （TimelineView が最後に描いたフレーム時刻）基準なので、止められる位置はフレーム間隔の
    /// 格子になる。±1% の PERFECT 窓（全幅 2%）は S_min = 1.35 秒のとき 27ms で、
    /// **120Hz（8.33ms 間隔）なら格子 3 点、60Hz（16.67ms 間隔）なら 1 点**が入る。
    /// ただし実機（iPhone 16 Pro / iOS 26.5.2）は `CADisableMinimumFrameDuration` を
    /// `Config/Info.plist` に入れても 60Hz 張り付きで、**120Hz の経路は現状使われていない**
    /// （60Hz でも 1 点は必ず入ることを含め、両方を `LevelCurveTests` で固定している）。
    public static func duration(level: Int, curve: LevelCurve = .standard) -> TimeInterval {
        // 上限側も丸める（`stage(for:)` と同じクランプ）。出荷カーブは Lv12 で下限に
        // 張り付くので丸めなくても同じ値になるが、張り付かないカーブでは
        // 「最高レベルを超えても最高レベルとして扱う」が破れる
        let clampedLevel = min(max(1, level), GameConfig.maxLevel)
        let raw = GameConfig.baseSweepSeconds * pow(curve.sweepDecayRate, Double(clampedLevel - 1))
        return max(curve.minSweepSeconds, raw)
    }

    /// 1 問の制限時間。片道 S の `LevelStage.roundTimeLimitSweeps` 本ぶん。
    ///
    /// 秒の直値ではなく片道 S の倍数で持つ理由: S はレベルで変わるため、秒で固定すると
    /// 高レベルほど通過回数が増えて易しくなる逆転が起きる。S の倍数なら難度カーブが
    /// 全レベルで揃う。
    ///
    /// 本数は**レベル帯ごと**（Lv1-5 = 3.5 本 / Lv6-12 = 2.5 本）。**必ず半奇数にすること。**
    /// 半奇数なら締め切りの瞬間の位相が 2S 周期の 0.5S か 1.5S になり、どちらも三角波では
    /// 比率 0.5 ＝ 数直線の中央に来る。この「時間切れ時のカーソル位置が何の情報も持たない」
    /// 性質が、時間切れでカーソルを消す表示判断（`GameViewModel.showsCursor`）の根拠になっている。
    /// 整数本にすると端で止まり、あたかも狙って止めたように見えてしまう。
    ///
    /// 下限は 2.5 本（往復 1 周＋半分）。ここなら目標比率 t の通過時刻 t·S / (2−t)·S は
    /// レベルにも t にもよらず必ず締め切りより手前に来て、復路には半周ぶん以上の
    /// 余裕が残る。t < 0.5 なら 3 本目の (2+t)·S も間に合う。1.5 本まで落とすと
    /// 復路の余裕も 3 回目のチャンスも消えるので、半奇数のうち 2.5 が最小になる。
    /// 半奇数と 2.5 本下限は `LevelStage.init` の precondition で構造的に閉じている。
    public static func roundTimeLimit(level: Int, curve: LevelCurve = .standard) -> TimeInterval {
        duration(level: level, curve: curve) * curve.stage(for: level).roundTimeLimitSweeps
    }
}
