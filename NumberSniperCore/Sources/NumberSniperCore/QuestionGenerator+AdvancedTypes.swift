import Foundation

/// 上級帯のお題タイプの生成（四則演算・分数の和・変則レンジの小数・平方根）。
///
/// 4 種とも「条件を満たす組み合わせを全列挙してから 1 つ選ぶ」形にしている。
/// リトライ（作ってみて範囲外なら引き直す）だと、U や分母の範囲を変えたときに
/// 条件を満たす組み合わせが 0 個になっても気づけず、無限ループになる。
/// 列挙なら「候補が空でない」ことをテストで固定できる。
extension QuestionGenerator {
    // MARK: - arithmetic

    /// 四則演算の式お題。レンジは 0〜upper の整数。
    public func makeArithmetic(
        upper: Int,
        operations: [ArithmeticOperation],
        using rng: inout some RandomNumberGenerator
    ) -> Question {
        let requested = operations.randomElement(using: &rng) ?? .add
        let requestedCandidates = Self.arithmeticCandidates(operation: requested, upper: upper)

        // 候補が空になる (operation, upper) の組は出荷カーブに存在しない
        // （AdvancedQuestionTypeTests / LevelCurveTests で固定）。
        // それでも空になったときは**演算子ごと `+` に落とす**。演算子だけ残して
        // 適当な組を当てると「1 × 1」の答えを 2 として採点する、クラッシュしないぶん
        // 気づけないお題ができる
        let operation = requestedCandidates.isEmpty ? .add : requested
        let candidates = requestedCandidates.isEmpty
            ? Self.arithmeticCandidates(operation: .add, upper: upper)
            : requestedCandidates
        // `.add` に落としてもなお候補が空なら、プロファイル設定そのものが破綻している
        // （例: upper が小さすぎて 0.05·upper 〜 0.95·upper に整数が 1 つも入らない）。
        // 黙ってダミーの式を返すと `2 / upper` が目標比率の下限を割り込んで
        // 答えられないお題を出しかねないので、ここで止めて設定側の不備として気づかせる。
        guard let picked = candidates.randomElement(using: &rng) else {
            preconditionFailure(
                "arithmeticCandidates(operation: \(operation), upper: \(upper)) is empty "
                    + "even after falling back to .add; this (operation, upper) configuration "
                    + "cannot produce a valid question"
            )
        }

        return Question(
            type: .arithmetic,
            promptText: "\(picked.a) \(operation.symbol) \(picked.b)",
            range: .integers(lower: 0, upper: upper),
            target: Double(picked.answer) / Double(upper)
        )
    }

    /// `operation` で作れる (被演算数 a, 被演算数 b, 答え) の全組み合わせ。
    /// 答えは必ず 0.05·upper 〜 0.95·upper の内側に入る。
    ///
    /// - Note: 答えを先に決めて分解しようとすると、`×` で答えが素数のときに
    ///   1×n しか作れずデッドロックする。被演算数側から作って答えを絞る。
    static func arithmeticCandidates(
        operation: ArithmeticOperation,
        upper: Int
    ) -> [(a: Int, b: Int, answer: Int)] {
        let lowerBound = Int((GameConfig.minTarget * Double(upper)).rounded(.up))
        let upperBound = Int((GameConfig.maxTarget * Double(upper)).rounded(.down))
        guard lowerBound <= upperBound, upper >= 2 else { return [] }

        var result: [(a: Int, b: Int, answer: Int)] = []
        func appendIfInBounds(_ a: Int, _ b: Int, _ answer: Int) {
            guard answer >= lowerBound, answer <= upperBound else { return }
            result.append((a: a, b: b, answer: answer))
        }

        switch operation {
        case .add:
            for a in 1..<upper {
                for b in 1...(upper - a) {
                    appendIfInBounds(a, b, a + b)
                }
            }
        case .subtract:
            for a in 2...upper {
                for b in 1..<a {
                    appendIfInBounds(a, b, a - b)
                }
            }
        case .multiply:
            // 片方は 1 桁（九九）、もう片方は「1 桁」か「キリ番（10, 20, …）」のどちらか。
            // `3 × 20` は九九に 0 を 1 つ足すだけなので、九九の延長として「かんたん」の範囲。
            // 一方 `7 × 13` のような二桁 × 二桁は暗算から外れるので作らない
            // （= b 側だけキリ番を許し、a 側は 1 桁に固定する非対称なルール）。
            // キリ番の上限は upper / 2 まで（それより大きい b は a=2 でも upper を超え、
            // どの a でも候補を作れない）。upper が小さいときに空レンジにならないよう
            // 下限の 10 は max で必ず確保する
            let multiples = stride(from: 10, through: max(10, upper / 2), by: 10)
            let multipliers = Array(2...9) + Array(multiples)
            for a in 2...9 {
                for b in multipliers where a * b <= upper {
                    appendIfInBounds(a, b, a * b)
                }
            }
        case .divide:
            // a ÷ b = answer。a = answer × b が upper 以下になる組だけ作れば必ず割り切れる
            for b in 2...9 {
                let maxAnswer = upper / b
                guard maxAnswer >= 1 else { continue }
                for answer in 1...maxAnswer {
                    appendIfInBounds(answer * b, b, answer)
                }
            }
        }
        return result
    }

    // MARK: - fractionSum

    /// 既約真分数 2 つの和。分母は必ず異なるものを選ぶ。
    public func makeFractionSum(
        denominators: ClosedRange<Int>,
        using rng: inout some RandomNumberGenerator
    ) -> Question {
        let candidates = Self.fractionSumCandidates(denominators: denominators)
        // `makeArithmetic` と違い、ここは固定のフォールバック値へ静かに落ちてよい。
        // 1/3 + 1/4 = 7/12 ≈ 0.583 は denominators の値に関係なく常に目標比率
        // 0.05〜0.95 の内側に入るので、候補が空でも「答えられないお題」にはならない
        // （`makeArithmetic` の旧フォールバックは upper に依存する式だったため、
        // upper 次第で範囲外に落ちうる、という理由で `preconditionFailure` に変えた）
        let picked = candidates.randomElement(using: &rng) ?? (n1: 1, d1: 3, n2: 1, d2: 4)
        return Question(
            type: .fractionSum,
            promptText: "\(picked.n1)/\(picked.d1) + \(picked.n2)/\(picked.d2)",
            range: .unit,
            // 通分は整数のまま行う（先に Double へ落とすと丸めが目標比率に乗る）
            target: Double(picked.n1 * picked.d2 + picked.n2 * picked.d1)
                / Double(picked.d1 * picked.d2)
        )
    }

    /// 和が目標比率の範囲に収まる (n1/d1, n2/d2) の全組み合わせ。
    /// 両項とも既約真分数で、**2 つの分母は異なる**（`1/4 + 1/4` は `1/2` と一目で分かる）。
    static func fractionSumCandidates(
        denominators: ClosedRange<Int>
    ) -> [(n1: Int, d1: Int, n2: Int, d2: Int)] {
        var result: [(n1: Int, d1: Int, n2: Int, d2: Int)] = []
        for d1 in denominators {
            for n1 in 1..<d1 where greatestCommonDivisor(n1, d1) == 1 {
                for d2 in denominators where d2 != d1 {
                    for n2 in 1..<d2 where greatestCommonDivisor(n2, d2) == 1 {
                        let numerator = n1 * d2 + n2 * d1
                        let denominator = d1 * d2
                        let sum = Double(numerator) / Double(denominator)
                        guard sum >= GameConfig.minTarget, sum <= GameConfig.maxTarget else { continue }
                        result.append((n1: n1, d1: d1, n2: n2, d2: d2))
                    }
                }
            }
        }
        return result
    }

    // MARK: - customRangeDecimal

    /// 変則レンジ上の小数お題（13〜63 で `41.5`）。
    ///
    /// 内部は 10 倍した整数で扱う。`lower + 0.1 * k` を Double で積むと
    /// `41.499999…` のような値になり、表示と目標比率がズレる。
    public func makeCustomRangeDecimal(
        lower: Int,
        upper: Int,
        using rng: inout some RandomNumberGenerator
    ) -> Question {
        let width = upper - lower
        let spanTenths = width * 10
        let minTenths = Int((Double(lower * 10) + GameConfig.minTarget * Double(spanTenths)).rounded(.up))
        let maxTenths = Int((Double(lower * 10) + GameConfig.maxTarget * Double(spanTenths)).rounded(.down))
        var tenths = Int.random(in: minTenths...maxTenths, using: &rng)
        // 小数第 1 位が 0 だと整数に見えて customRange と区別がつかない。
        // 出荷カーブの幅（20 以上 = 200 tenths 以上）なら必ずどちらかにずらせるが、
        // **両側とも範囲を確認する**。片側だけ見ると、幅の狭いスタイルを足したときに
        // 目標比率が 0.05〜0.95 を静かに外れる
        if tenths % 10 == 0 {
            if tenths + 1 <= maxTenths {
                tenths += 1
            } else if tenths - 1 >= minTenths {
                tenths -= 1
            }
        }
        return Question(
            type: .customRangeDecimal,
            promptText: String(format: "%.1f", Double(tenths) / 10),
            range: .integers(lower: lower, upper: upper),
            target: Double(tenths - lower * 10) / Double(spanTenths)
        )
    }

    // MARK: - squareRoot

    /// 平方根お題（`√0.49` → 0.7）。
    ///
    /// 根号の中は完全平方になる小数だけを使い、答えを厳密に出せるようにする。
    /// `0.7 × 0.7` を浮動小数で計算して中身を作ると `0.48999…` になるので、
    /// **整数 k² から作って表示だけ小数にする**。
    public func makeSquareRoot(using rng: inout some RandomNumberGenerator) -> Question {
        let k = Int.random(in: 1...9, using: &rng)
        return Question(
            type: .squareRoot,
            promptText: String(format: "√%.2f", Double(k * k) / 100),
            range: .unit,
            target: Double(k) / 10
        )
    }
}
