import Foundation

/// コンボ数からコンボ倍率（整数のパーセント値）を求める。
/// min(300, 100 + 10 × コンボ数)。
public func comboMultiplierPercent(combo: Int) -> Int {
    let raw = GameConfig.comboMultiplierBasePercent
        + GameConfig.comboMultiplierStepPercent * max(0, combo)
    return min(GameConfig.comboMultiplierCapPercent, raw)
}

/// 判定を受けた後のコンボ数。PERFECT で +2（コンボ加速）、GREAT で +1、GOOD/MISS で 0 リセット。
public func nextCombo(current: Int, judgement: Judgement) -> Int {
    switch judgement {
    case .perfect: max(0, current) + GameConfig.perfectComboGain
    case .great: max(0, current) + GameConfig.greatComboGain
    case .good, .miss: 0
    }
}

/// 1 問の獲得点。**整数演算のみ**で計算する。
///
/// - Important: `level` と `combo` にはいずれも「**その問の開始時点**」の値を渡す。
///   コンボ更新後・レベルアップ後の値を渡すとスコアが仕様とずれる。
/// - Note: 精度点が 100 の倍数なので `÷ 100` は常に割り切れる（`GameConfigTests` で固定）。
public func roundPoints(judgement: Judgement, level: Int, combo: Int) -> Int {
    judgement.accuracyPoints * max(1, level) * comboMultiplierPercent(combo: combo) / 100
}
