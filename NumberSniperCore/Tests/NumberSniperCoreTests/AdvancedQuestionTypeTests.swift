import Testing
import Foundation
@testable import NumberSniperCore

@Suite("新お題タイプの生成")
struct AdvancedQuestionTypeTests {
    let generator = QuestionGenerator()

    // MARK: - arithmetic

    @Test("四則演算お題は 0〜U レンジで、答えが目標比率と一致する", arguments: [10, 20, 50, 100])
    func arithmeticMatchesTarget(upper: Int) {
        for seed in UInt64(0)..<200 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            let question = generator.makeArithmetic(
                upper: upper,
                operations: ArithmeticOperation.allCases,
                using: &rng
            )
            #expect(question.type == .arithmetic)
            #expect(question.range == .integers(lower: 0, upper: upper))
            #expect(question.target >= GameConfig.minTarget)
            #expect(question.target <= GameConfig.maxTarget)

            let answer = Self.evaluate(question.promptText)
            #expect(answer != nil, "式として解釈できない: \(question.promptText)")
            if let answer {
                #expect(abs(Double(answer) / Double(upper) - question.target) < 1e-12)
            }
        }
    }

    @Test("四則演算お題は ASCII の * / - を使わない")
    func arithmeticUsesTypographicOperators() {
        for seed in UInt64(0)..<200 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            let question = generator.makeArithmetic(
                upper: 100,
                operations: ArithmeticOperation.allCases,
                using: &rng
            )
            #expect(!question.promptText.contains("*"))
            #expect(!question.promptText.contains("/"))
            #expect(!question.promptText.contains("-"))
        }
    }

    @Test("指定した演算子だけが出る")
    func arithmeticRespectsOperationSet() {
        var seen = Set<String>()
        for seed in UInt64(0)..<300 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            let question = generator.makeArithmetic(
                upper: 100,
                operations: [.add, .subtract],
                using: &rng
            )
            #expect(!question.promptText.contains("×"))
            #expect(!question.promptText.contains("÷"))
            if question.promptText.contains("+") { seen.insert("+") }
            if question.promptText.contains("−") { seen.insert("−") }
        }
        #expect(seen == ["+", "−"])
    }

    @Test("÷ は必ず割り切れ、被除数は U 以下", arguments: [10, 20, 50, 100])
    func divisionIsExact(upper: Int) {
        for candidate in QuestionGenerator.arithmeticCandidates(operation: .divide, upper: upper) {
            #expect(candidate.a % candidate.b == 0)
            #expect(candidate.a / candidate.b == candidate.answer)
            #expect(candidate.a <= upper)
        }
    }

    @Test("どの演算子・どの U でも候補が空にならない", arguments: [10, 20, 50, 100])
    func arithmeticCandidatesAreNeverEmpty(upper: Int) {
        for operation in ArithmeticOperation.allCases {
            let candidates = QuestionGenerator.arithmeticCandidates(operation: operation, upper: upper)
            #expect(!candidates.isEmpty, "\(operation) / U=\(upper) の候補が空")
        }
    }

    /// `3 × 20 = 60` はLv6の出題範囲で生成できる必要がある掛け算の例。
    /// 1桁 × 1桁だけに絞った実装ではこの組み合わせが生成できない
    /// （20 が 2...9 の範囲外のため）ので、具体的な組を狙い撃ちで検証する。
    @Test("掛け算の候補に 3 × 20 = 60（U=100）が含まれる")
    func multiplyCandidatesIncludeThreeByTwenty() {
        let candidates = QuestionGenerator.arithmeticCandidates(operation: .multiply, upper: 100)
        let hasThreeByTwenty = candidates.contains {
            $0.a == 3 && $0.b == 20 && $0.answer == 60
        }
        #expect(hasThreeByTwenty, "3 × 20 = 60 が候補に含まれていない: \(candidates)")
    }

    /// `3 × 20` 形式の式を評価する。テスト側で独立に計算して、生成側の target を検算する
    static func evaluate(_ text: String) -> Int? {
        let parts = text.split(separator: " ").map(String.init)
        guard parts.count == 3, let a = Int(parts[0]), let b = Int(parts[2]) else { return nil }
        switch parts[1] {
        case "+": return a + b
        case "−": return a - b
        case "×": return a * b
        case "÷": return b == 0 ? nil : a / b
        default: return nil
        }
    }

    // MARK: - fractionSum

    @Test("分数の和は既約 2 項・分母が異なる・和が目標比率と一致する")
    func fractionSumIsValid() {
        for seed in UInt64(0)..<500 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            let question = generator.makeFractionSum(denominators: 2...6, using: &rng)
            #expect(question.type == .fractionSum)
            #expect(question.range == .unit)

            let terms = question.promptText.components(separatedBy: " + ")
            #expect(terms.count == 2)
            guard terms.count == 2 else { return }

            var fractions: [(Int, Int)] = []
            for term in terms {
                let parts = term.split(separator: "/").compactMap { Int($0) }
                #expect(parts.count == 2)
                guard parts.count == 2 else { return }
                #expect(parts[0] > 0 && parts[0] < parts[1])
                #expect((2...6).contains(parts[1]))
                #expect(QuestionGenerator.greatestCommonDivisor(parts[0], parts[1]) == 1)
                fractions.append((parts[0], parts[1]))
            }
            // 2 つの分母は必ず異なる（1/4 + 1/4 は 1/2 と一目で分かってしまう）
            #expect(fractions[0].1 != fractions[1].1)

            let expected = Double(fractions[0].0) / Double(fractions[0].1)
                + Double(fractions[1].0) / Double(fractions[1].1)
            #expect(abs(question.target - expected) < 1e-12)
            #expect(question.target >= GameConfig.minTarget)
            #expect(question.target <= GameConfig.maxTarget)
        }
    }

    // MARK: - customRangeDecimal

    @Test("変則レンジの小数お題は小数第 1 位までで、整数にならない")
    func customRangeDecimalIsNeverInteger() {
        for seed in UInt64(0)..<500 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            let question = generator.makeCustomRangeDecimal(lower: 13, upper: 63, using: &rng)
            #expect(question.type == .customRangeDecimal)
            #expect(question.range == .integers(lower: 13, upper: 63))

            let parts = question.promptText.split(separator: ".")
            #expect(parts.count == 2, "小数第 1 位までの表記でない: \(question.promptText)")
            guard parts.count == 2 else { return }
            #expect(parts[1].count == 1)
            #expect(parts[1] != "0", "整数と区別がつかない: \(question.promptText)")

            guard let value = Double(question.promptText) else {
                Issue.record("小数として解釈できない: \(question.promptText)")
                return
            }
            let expected = (value - 13) / 50
            #expect(abs(question.target - expected) < 1e-9)
            #expect(question.target >= GameConfig.minTarget)
            #expect(question.target <= GameConfig.maxTarget)
        }
    }

    @Test("3 桁レンジでも成立する")
    func customRangeDecimalWorksOnThreeDigitRange() {
        for seed in UInt64(0)..<300 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            let question = generator.makeCustomRangeDecimal(lower: 137, upper: 482, using: &rng)
            #expect(question.target >= GameConfig.minTarget)
            #expect(question.target <= GameConfig.maxTarget)
            guard let value = Double(question.promptText) else {
                Issue.record("小数として解釈できない: \(question.promptText)")
                return
            }
            #expect(value > 137)
            #expect(value < 482)
        }
    }

    // MARK: - squareRoot

    @Test("平方根お題は根号の中が完全平方で、目標比率が k/10 ちょうど")
    func squareRootIsExact() {
        for seed in UInt64(0)..<300 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            let question = generator.makeSquareRoot(using: &rng)
            #expect(question.type == .squareRoot)
            #expect(question.range == .unit)
            #expect(question.promptText.hasPrefix("√"))

            let digits = question.promptText.dropFirst()
            guard let inside = Double(digits) else {
                Issue.record("根号の中を小数として読めない: \(question.promptText)")
                return
            }
            // 目標比率は k/10 の形（浮動小数の丸めが混ざらない）
            let k = Int((question.target * 10).rounded())
            #expect((1...9).contains(k))
            #expect(abs(question.target - Double(k) / 10) < 1e-12)
            // 根号の中は k² / 100
            #expect(abs(inside - Double(k * k) / 100) < 1e-12)
        }
    }
}
