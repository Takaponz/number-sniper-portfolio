import Foundation

/// 出荷する唯一のレベルカーブ。
///
/// 片道スイープ秒（短いほど速い）:
/// ```
/// Lv   1     2     3     4     5     6     7     8     9    10    11    12
///    2.60  2.44  2.30  2.16  2.03  1.91  1.79  1.69  1.58  1.49  1.40  1.35
/// ```
///
/// **「難しさ」は 2 軸ある**というのがこの表の背骨。
/// - **暗算軸**（四則演算・分数・分数の和・平方根）＝ 対象年齢を広げる軸。
///   答えさえ出れば位置は簡単なので、上級者を殺す軸には使わない
/// - **目測軸**（変則レンジ・3 桁レンジ・速度）＝ 難易度を上げる軸
///
/// 目測軸に難しいラインが 2 本ある。
/// - **第1ライン = Lv9**: 固定レンジ（0〜1 と 0〜100）の補助輪が外れて変則レンジになる。
///   ~~制限時間は 3.5 本のままにして時間の崖は Lv10 へ分離する~~ → **2026-08-26 に撤回**。
///   廃止理由: 実機で遊んだ所感が「制限時間は今のままで気持ちよかった」だったため、
///   本数の切れ目は Lv5 → Lv6 に据え置く（**段差はここ 1 箇所だけ**）。
///   つまり第1ライン（Lv9）と時間の崖（Lv6）は別の位置にあるが、それは分離を狙った
///   結果ではなく「秒のリズムを触らない」ことを優先した結果
/// - **第2ライン = Lv11**: 3 桁レンジ。目測が本気になる
///
/// Lv1-6 が「小学生が遊べる」帯。四則演算と分数（分母 2〜4）＝小学校の範囲を、
/// 目測はやさしいまま（0〜1 と 0〜100 の固定レンジ。位置感覚は同一）出す。
enum LevelCurveTable {
    // MARK: - 帯ごとの生成パラメータ

    /// 固定レンジ帯の生成パラメータ。実際に使うのは Lv1-3（割合の 3 表現）と
    /// Lv5-6（四則演算）で、0 始まりレンジが効くのは後者だけ。そのレンジは
    /// 0〜100 の 1 種に固定（2026-08-25 第2弾）。
    /// 0〜100 は 0〜1 と位置が同一（ラベルが ×100 なだけ）なので、
    /// Lv1-6 全体を同じ位置感覚で通せる。
    /// `promptStep`（5 刻み）はキリ番お題（customRange）の出す値専用で、
    /// 四則演算の答えには効かない — 2026-08-25 の並び替えでキリ番帯が消えたため
    /// 出荷カーブでは未使用だが、将来の再登場に備えて設定ごと残している
    static func beginner(
        denominators: ClosedRange<Int> = 2...4,
        operations: [ArithmeticOperation] = [],
        percentStep: Int = 10
    ) -> QuestionParameters {
        QuestionParameters(
            fractionDenominators: denominators,
            customRangeStyle: .roundFromZero(options: [
                RoundRangeOption(upper: 100, promptStep: 5),
            ]),
            arithmeticOperations: operations,
            percentStep: percentStep
        )
    }

    /// 2 桁の任意レンジ ＋ 細かい刻み。`customRangeStyle` が実際に効くのは
    /// 変則レンジを出す Lv9-10 だけで、Lv4・7・8 は 1% 刻みや分母 2〜9 を得るために
    /// これを使う（この 3 帯の types は 0〜1 レンジのタイプだけなのでレンジ様式は出番がない）
    static func standard(denominators: ClosedRange<Int> = 2...9) -> QuestionParameters {
        QuestionParameters(
            fractionDenominators: denominators,
            customRangeStyle: .arbitrary(widths: 20...50),
            percentStep: 1
        )
    }

    /// 上級帯（Lv11-12）。3 桁レンジ
    static let advanced = QuestionParameters(
        fractionDenominators: 2...6,
        customRangeStyle: .threeDigit(lowerBounds: 100...400, widths: 200...400),
        percentStep: 1
    )

    // MARK: - 本数

    /// Lv1-5。**入口の 5 レベルに与える猶予**で、カーソルの速さを変えずに考える時間だけを足す。
    ///
    /// - Note: 元は「四則演算と分数は『答えを出す』段階があるぶん」という論拠だったが、
    ///   2026-08-25 の並び替えで**帯とお題タイプの対応が崩れた**ので取らない
    ///   （3.5 本の Lv1/3/4 に暗算の段階はなく、暗算が一番重い分数 2〜9 は 2.5 本の Lv7）。
    ///   現在の切れ目 Lv5/Lv6 は「秒のリズムを触らない」ことを優先した据え置きで、
    ///   お題の重さから導出した位置ではない（2026-08-26 変更 (4)）
    static let beginnerSweeps = 3.5
    /// Lv6-12
    static let standardSweeps = 2.5
}

extension LevelCurve {
    /// 出荷カーブ。r = 0.94 は 2026-08-01 に実機で確定させた値をそのまま伸ばしたもので、
    /// base 2.6 から始めると Lv12 でちょうど下限 1.35 に届く（Lv11 = 1.400 > 1.35 >
    /// 2.6·0.94¹¹ = 1.316）。序盤が緩やかなまま上限も確保できる。
    public static let standard = LevelCurve(
        minSweepSeconds: 1.35,
        sweepDecayRate: 0.94,
        stages: [
            // MARK: 入口（Lv1-4）
            // 基準ライン（数直線の両端）を 0〜1 に固定したまま、同じ「割合」を
            // パーセント → 分数 → 小数と表現だけ変えて出す。レンジを読む段階がなく、
            // ライン自体も Lv4 まで一切変化しない（2026-08-25 実機所感
            // 「基準ラインが Lv2 から毎問変わるのが体験的に悪い」で並び替え）
            LevelStage(
                levels: 1...1,
                types: [.percent],
                parameters: LevelCurveTable.beginner(),
                roundTimeLimitSweeps: LevelCurveTable.beginnerSweeps
            ),
            // 分母 2〜4 = 1/2・1/3・2/3・1/4・3/4 だけ
            LevelStage(
                levels: 2...2,
                types: [.fraction],
                parameters: LevelCurveTable.beginner(denominators: 2...4),
                roundTimeLimitSweeps: LevelCurveTable.beginnerSweeps
            ),
            LevelStage(
                levels: 3...3,
                types: [.decimalValue],
                parameters: LevelCurveTable.beginner(),
                roundTimeLimitSweeps: LevelCurveTable.beginnerSweeps
            ),
            // Lv1-3 で 1 つずつ出した表現のうち、小数とパーセントの総復習ミックス。
            // レンジは 0〜1 のままなので新しい読み方は要らない（percent は 1% 刻み ＝
            // Lv1 の 10% 刻みより細かい。それがこの帯の上げ幅）
            LevelStage(
                levels: 4...4,
                types: [.decimalValue, .percent],
                parameters: LevelCurveTable.standard(),
                roundTimeLimitSweeps: LevelCurveTable.beginnerSweeps
            ),

            // MARK: 算数（Lv5-6）★時間の崖: Lv6 で 3.5 本 → 2.5 本
            // ここで初めてラベルが 0〜100 になり、レンジ明示チップが登場する。
            // レンジは 0〜100 の 1 種に固定（2026-08-25 第2弾）— 位置は 0〜1 と同一なので、
            // 基準ラインを変えずに四則演算の暗算だけを足す帯。レンジ読みは
            // 変則レンジ（Lv9 第1ライン）まで登場しない。
            // Lv5 は足し算・引き算だけ。掛け算と割り算は Lv6 から。
            //
            // 崖が帯の途中（＋− と ×÷ の間）に来るのは、本数の切れ目を Lv5 → Lv6 に
            // 据え置くと決めたため（2026-08-26。実機所感「制限時間は今のままで気持ちよかった」）。
            // 半奇数の制約で 3.0 本が作れない以上、段差はどこかに必ず 1 回生まれる
            LevelStage(
                levels: 5...5,
                types: [.arithmetic],
                parameters: LevelCurveTable.beginner(operations: [.add, .subtract]),
                roundTimeLimitSweeps: LevelCurveTable.beginnerSweeps
            ),
            LevelStage(
                levels: 6...6,
                types: [.arithmetic],
                parameters: LevelCurveTable.beginner(operations: ArithmeticOperation.allCases),
                roundTimeLimitSweeps: LevelCurveTable.standardSweeps
            ),

            // MARK: 標準（Lv7-9）★第1ライン: Lv9 で変則レンジ
            // Lv7-8 はレンジが 0〜1 に戻り、暗算（分母 2〜9 の分数）と表現の混合で難度を上げる。
            // 目測が変わるのは Lv9 だけ ＝ 新しい読み方は 1 箇所で 1 つ。
            // 本数は Lv6 の崖以降 2.5 本のまま（第1ラインで本数は動かない）
            LevelStage(
                levels: 7...7,
                types: [.fraction],
                parameters: LevelCurveTable.standard(denominators: 2...9),
                roundTimeLimitSweeps: LevelCurveTable.standardSweeps
            ),
            // 3 種混合。変則レンジは入れない（第1ラインは Lv9 に一本化する）
            LevelStage(
                levels: 8...8,
                types: [.decimalValue, .percent, .fraction],
                parameters: LevelCurveTable.standard(),
                roundTimeLimitSweeps: LevelCurveTable.standardSweeps
            ),
            // ★第1ライン: 固定レンジの補助輪が外れる
            LevelStage(
                levels: 9...9,
                types: [.customRange],
                parameters: LevelCurveTable.standard(),
                roundTimeLimitSweeps: LevelCurveTable.standardSweeps
            ),

            // MARK: 上級（Lv10-12）
            //
            // スパイス（暗算の重いタイプ）は 1 帯 1 種だけ。主軸にすると
            // 「目測のズレを楽しむ」背骨から外れる。
            //
            // **型の数はスパイス比率から逆算しない。** 帯の型は「その帯で目測が本気になるか」で
            // 選び、比率は結果を測るだけ（20〜35% に収まる）。比率を 20〜25% に固定しようとして
            // Lv11 に percent のような易しい型を員数合わせで足すと、最高帯の 3 分の 1 が
            // Lv4 と同じ難度のお題で埋まる
            //
            // Lv10 の分母 2〜6 は fractionSum 専用（この帯に .fraction は入れない。
            // 入れると Lv7-8 の 2〜9 から易しくなる逆転が起きる）
            LevelStage(
                levels: 10...10,
                types: [.customRangeDecimal, .customRange, .decimalValue, .percent, .fractionSum],
                parameters: LevelCurveTable.standard(denominators: 2...6),
                roundTimeLimitSweeps: LevelCurveTable.standardSweeps
            ),
            // ★第2ライン: 3 桁レンジ。ここから目測が本気になるので、
            // 0〜1 レンジの易しい型（percent / decimalValue）は入れない
            LevelStage(
                levels: 11...11,
                types: [.customRange, .customRangeDecimal, .irrational],
                parameters: LevelCurveTable.advanced,
                roundTimeLimitSweeps: LevelCurveTable.standardSweeps
            ),
            // Lv12 はレベルアップが止まるエンドレス帯。
            // decimalValue を戻すのは「3 桁レンジばかりが延々続く」単調さを崩すため
            LevelStage(
                levels: 12...GameConfig.maxLevel,
                types: [.customRange, .customRangeDecimal, .decimalValue, .squareRoot],
                parameters: LevelCurveTable.advanced,
                roundTimeLimitSweeps: LevelCurveTable.standardSweeps
            ),
        ]
    )
}
