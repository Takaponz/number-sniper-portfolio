import Foundation

/// 停止位置比率と目標比率のズレを、レンジ幅の 0.01% 単位の整数 d に丸める。
///
/// 判定・スコアの計算はすべてこの整数 d を使う。浮動小数の境界誤差で
/// 判定が反転しないようにするための、唯一の「浮動小数 → 整数」変換点。
/// 丸めは Swift 既定の half-away-from-zero。
public func deviation(stopRatio: Double, target: Double) -> Int {
    let raw = (abs(stopRatio - target) * 10_000).rounded()
    guard raw.isFinite else { return 10_000 }
    return min(10_000, max(0, Int(raw)))
}

/// `deviation` に符号だけを積んだもの。負 = 止めた位置が目標より**左**。
///
/// 判定は既存の `deviation()` → `judge(deviation:)` の 1 本のままで、こちらは
/// 練習モードの「どちらに外したか」の表示にだけ使う（`deviation()` は無改変）。
///
/// - Important: 非有限が混じったら符号を正に倒す。既存 `deviation()` は非有限に 10000 を
///   返すが、比較 `stopRatio < target` の倒れ方は値によって違う。nan は常に false なので
///   +10000 になる一方、`stopRatio = 0, target = .infinity` では `0 < ∞` が true になって
///   **−10000** が返る。判定はどちらでも MISS だが、方向表示が「左にズレた」と嘘をつく。
public func signedDeviation(stopRatio: Double, target: Double) -> Int {
    let magnitude = deviation(stopRatio: stopRatio, target: target)
    guard stopRatio.isFinite, target.isFinite else { return magnitude }
    return stopRatio < target ? -magnitude : magnitude
}
