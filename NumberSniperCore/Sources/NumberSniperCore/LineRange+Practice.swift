import Foundation

/// 練習モードで数直線に描く目盛 1 本。
public struct LineTick: Sendable, Equatable {
    /// 左から数えた位置。`1...divisions-1`
    public let index: Int
    /// この目盛が属する分割数
    public let divisions: Int
    /// 目盛が指す実値
    public let value: LineValue

    public init(index: Int, divisions: Int, value: LineValue) {
        self.index = index
        self.divisions = divisions
        self.value = value
    }

    /// 描画位置（数直線の左端 = 0、右端 = 1）。**判定には入れない**。
    ///
    /// `divisions` を自蔵するのは、この計算が `GameConfig` へのグローバル参照を
    /// 持たないようにするため（描画用の値が設定へ暗黙依存すると、テストから
    /// 別の分割数を渡せなくなる）。
    public var ratio: Double { Double(index) / Double(divisions) }
}

extension LineRange {
    /// 練習モードの計算で扱える両端の絶対値の上限。
    ///
    /// 目盛・ズレの計算で両端に掛かる最大の係数は、固定小数点のスケール
    /// `10^practiceMaxDecimals` と d の値域 10000 の積。両端をこれで割った値に
    /// 収めておけば、途中式が `Int` からはみ出さない。
    /// 出荷カーブが作るレンジ（上端 999 まで）はこの上限の遥か内側にある。
    static var practiceBoundLimit: Int {
        Int.max / (power10(GameConfig.practiceMaxDecimals) * 10_000)
    }

    /// レンジ幅。`.unit` は 1、`.integers` は `upper - lower`。
    ///
    /// - Important: 逆転レンジ（`upper <= lower`）は `precondition` で拒否する。
    ///   クランプすると端ラベルが「5 〜 3」のまま目盛が「5.25 / 5.5 / 5.75」という
    ///   矛盾した表示になる。`QuestionGenerator` は逆転レンジを生成しないので、
    ///   これは「到達不能な不正値」であり、`LevelStage.init` / `LevelCurve.init` と
    ///   同じ流儀で止める
    /// - Important: 両端の大きさも同時に閉じる。`upper > lower` だけ見ると
    ///   `.integers(lower: .min, upper: .max)` が受理されて `upper - lower` 自体が
    ///   オーバーフローし、`practiceTicks` / `offsetValue` の途中式も溢れる
    ///   （`offsetValue` の値域だけ閉じても経路が残る）
    public var width: Int {
        switch self {
        case .unit:
            return 1
        case .integers(let lower, let upper):
            precondition(upper > lower, "逆転レンジ(\(lower)〜\(upper))には幅が無い")
            let limit = Self.practiceBoundLimit
            precondition(
                lower.magnitude <= UInt(limit) && upper.magnitude <= UInt(limit),
                "レンジ(\(lower)〜\(upper)) の両端は ±\(limit) に収めること（目盛計算が Int に収まらない）"
            )
            return upper - lower
        }
    }

    /// 下端の値。`.unit` は 0。
    public var lowerBound: Int {
        switch self {
        case .unit:
            return 0
        case .integers(let lower, _):
            return lower
        }
    }

    /// 25/50/75% 位置の目盛（既定の分割数 4 のとき）。
    ///
    /// 目盛値は完全整数計算で、丸めが一切入らない。`scale = 10^practiceMaxDecimals`、
    /// `D = divisions`、`W = width` として
    /// ```
    /// scaled(k) = (D · lower + k · W) × (scale / D)      k = 1 ..< D
    /// ```
    /// `scale % D == 0` なので `scale / D` は整数になる。丸め表記は禁止
    /// （`209.25` を `209.3` と出すと、線の位置と表示値が食い違って目測の指標として嘘になる）。
    ///
    /// - Parameter divisions: 分割数。引数に取るのは、テストから出荷値と別の分割数を
    ///   渡して式の弁別ができるようにするため
    /// - Precondition: `divisions > 1`（D=0 は `scale / D` が除算不能、D=1 は目盛ゼロ本）
    ///   かつ `10^practiceMaxDecimals % divisions == 0`（D=3 では整数除算が切り捨てられ、
    ///   目盛値が黙って狂う）
    public func practiceTicks(divisions: Int = GameConfig.practiceTickDivisions) -> [LineTick] {
        let scale = power10(GameConfig.practiceMaxDecimals)
        precondition(divisions > 1, "divisions(\(divisions)) は 2 以上にすること")
        precondition(
            scale % divisions == 0,
            "divisions(\(divisions)) は \(scale) を割り切ること（割り切れないと目盛値が有限小数で表せない）"
        )
        let step = scale / divisions
        let lower = lowerBound
        let w = width
        return (1..<divisions).map { index in
            LineTick(
                index: index,
                divisions: divisions,
                value: LineValue(
                    scaled: (divisions * lower + index * w) * step,
                    decimals: GameConfig.practiceMaxDecimals
                )
            )
        }
    }

    /// 符号付きズレ d を実数値に直す。**絶対値**を返す
    /// （方向は `PracticeResult.direction` だけが持つ）。
    ///
    /// 丸めは整数演算の half-away-from-zero:
    /// ```
    /// scaled = (|d| · W · 10^n + 5000) / 10000
    /// ```
    /// 絶対値に対して丸めるので、負側だけ丸めが片寄ることがない。
    ///
    /// - Precondition: `|signedDeviation| <= 10000`（`deviation()` の値域）。`practiceTicks` と
    ///   同じく公開 API なので入力契約を閉じる。無検査だと `Int.max` で UInt 乗算が
    ///   オーバーフローして trap し、`1_000_000_000` のような値では無警告で
    ///   桁外れの `LineValue` を返す
    public func offsetValue(signedDeviation: Int) -> LineValue {
        precondition(
            signedDeviation.magnitude <= 10_000,
            "signedDeviation(\(signedDeviation)) は ±10000（レンジ幅 100%）の範囲にすること"
        )
        let n = offsetDecimals
        // `abs(_:)` は `Int.min` でトラップするので `magnitude` のまま UInt で計算する
        let magnitude = signedDeviation.magnitude
        let scaled = (magnitude * UInt(width) * UInt(power10(n)) + 5_000) / 10_000
        return LineValue(scaled: Int(scaled), decimals: n)
    }

    /// ズレの表示桁数。「PERFECT 窓が 0 に潰れない最小桁」。
    ///
    /// PERFECT は `d <= GameConfig.perfectThreshold`（d の単位はレンジ幅の 0.01%）なので、
    /// 実数値では `W · perfectThreshold / 10000`。これが最小表示単位 `10^-n` 以上であればよい:
    /// ```
    /// W · GameConfig.perfectThreshold · 10^n >= 10000  を満たす最小の n
    /// ```
    ///
    /// - Important: `perfectThreshold` の現在値（100）を式に焼き込まない。代入すると
    ///   `W · 10^n >= 100` になって出荷値では一致するが、判定窓をチューニングしたときに
    ///   判定窓と表示精度が黙って乖離する
    /// - Note: 上限 `practiceMaxDecimals` での打ち切りは、逆転レンジを `width` の
    ///   precondition で閉じたうえの二重防御
    var offsetDecimals: Int {
        let w = width
        var n = 0
        while n < GameConfig.practiceMaxDecimals {
            if w * GameConfig.perfectThreshold * power10(n) >= 10_000 { break }
            n += 1
        }
        return n
    }
}
