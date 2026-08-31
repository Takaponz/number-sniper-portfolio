import Foundation

/// 10^exponent。`practiceMaxDecimals` 程度の小さな指数しか渡さない前提の素朴な累乗。
///
/// `pow(10, n)` を使わないのは、Double 経由で 10^2 が 99.999… になる経路を
/// 固定小数点の計算に入れないため。
func power10(_ exponent: Int) -> Int {
    precondition(exponent >= 0, "power10 の指数(\(exponent)) は 0 以上にすること")
    var result = 1
    for _ in 0..<exponent { result *= 10 }
    return result
}

/// 数直線上の値を **実値 × 10^decimals の整数**で持つ固定小数点。
///
/// `String(format:)` を使わないのは、Core に Double 経由の表示を再導入しないため
/// （判定・スコアと同じく、表示も整数演算だけで閉じる）。
public struct LineValue: Sendable, Equatable {
    /// 実値 × 10^decimals
    public let scaled: Int
    /// 小数桁数。`0...GameConfig.practiceMaxDecimals`
    public let decimals: Int

    /// - Important: `scaled == .min` を弾くのは、絶対値を取る経路でのトラップを
    ///   構造的に閉じるため。本設計の生成経路では到達しないが、この `init` は public で
    ///   任意の `Int` を受ける
    public init(scaled: Int, decimals: Int) {
        precondition(
            decimals >= 0 && decimals <= GameConfig.practiceMaxDecimals,
            "decimals(\(decimals)) は 0...\(GameConfig.practiceMaxDecimals) にすること"
        )
        precondition(scaled != .min, "scaled(\(scaled)) は Int.min にできない（絶対値が表せない）")
        self.scaled = scaled
        self.decimals = decimals
    }

    /// 末尾ゼロを落とした表示（目盛ラベル用）。2550/2 → `"25.5"`、3800/2 → `"38"`、5/2 → `"0.05"`。
    ///
    /// ゼロ埋め形（`"25.50"`）は使途が無いので作らない。
    public var trimmedText: String {
        scaled < 0 ? "-" + magnitudeText : magnitudeText
    }

    /// 符号を落とした `trimmedText`（ズレ表示用）。
    ///
    /// 練習モードが生成する値はすべて非負だが、副表示に符号が漏れる表示事故
    /// （「レンジの -6%」）を型の側で塞いでおくための二重防御。
    public var magnitudeText: String {
        // `abs(_:)` は `Int.min` でトラップするので `magnitude` を使う
        // （`init` の precondition と合わせた二重防御）
        let divisor = UInt(power10(decimals))
        let magnitude = scaled.magnitude
        let integerPart = magnitude / divisor
        let fractionPart = magnitude % divisor
        guard fractionPart > 0 else { return "\(integerPart)" }

        var digits = "\(fractionPart)"
        if digits.count < decimals {
            digits = String(repeating: "0", count: decimals - digits.count) + digits
        }
        while digits.hasSuffix("0") { digits.removeLast() }
        return "\(integerPart).\(digits)"
    }
}
