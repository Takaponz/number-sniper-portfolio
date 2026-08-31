import Testing
import Foundation
@testable import NumberSniperCore

@Suite("お題のモデル")
struct QuestionModelTests {
    @Test("0〜1 レンジの端ラベルは 0 と 1")
    func unitRangeLabels() {
        #expect(LineRange.unit.lowerLabel == "0")
        #expect(LineRange.unit.upperLabel == "1")
    }

    @Test("変則レンジの端ラベルは整数そのもの")
    func integerRangeLabels() {
        let range = LineRange.integers(lower: 13, upper: 63)
        #expect(range.lowerLabel == "13")
        #expect(range.upperLabel == "63")
    }

    @Test("整数お題を許すのは変則レンジだけ")
    func onlyIntegerRangeAllowsIntegerPrompts() {
        #expect(!LineRange.unit.allowsIntegerPrompts)
        #expect(LineRange.integers(lower: 1, upper: 2).allowsIntegerPrompts)
    }

    @Test("0〜1 かどうかを isUnit で判別できる（画面での明示表示の分岐に使う）")
    func isUnitDistinguishesRanges() {
        #expect(LineRange.unit.isUnit)
        #expect(!LineRange.integers(lower: 13, upper: 63).isUnit)
        // 0〜1 と同じ値の変則レンジは作られない想定だが、case が違えば別物として扱う
        #expect(!LineRange.integers(lower: 0, upper: 1).isUnit)
    }

    @Test("変則レンジを要求するのは customRange / arithmetic / customRangeDecimal")
    func onlyCustomRangeUsesIntegerRange() {
        let nonUnitTypes: Set<QuestionType> = [.customRange, .arithmetic, .customRangeDecimal]
        for type in QuestionType.allCases {
            #expect(type.requiredRangeIsUnit == !nonUnitTypes.contains(type))
        }
    }

    @Test("無理数テーブルの値はすべて 0.05〜0.95 に収まる")
    func irrationalConstantsAreInsideTargetBounds() {
        #expect(!IrrationalConstants.all.isEmpty)
        for constant in IrrationalConstants.all {
            #expect(constant.value >= GameConfig.minTarget)
            #expect(constant.value <= GameConfig.maxTarget)
        }
    }

    @Test("無理数テーブルの表示文字列は重複しない")
    func irrationalConstantTextsAreUnique() {
        let texts = IrrationalConstants.all.map(\.text)
        #expect(Set(texts).count == texts.count)
    }

    @Test("同じ seed の RNG は同じ列を返す")
    func seededGeneratorIsDeterministic() {
        var a = SeededRandomNumberGenerator(seed: 42)
        var b = SeededRandomNumberGenerator(seed: 42)
        var c = SeededRandomNumberGenerator(seed: 43)
        let fromA = (0..<8).map { _ in a.next() }
        let fromB = (0..<8).map { _ in b.next() }
        let fromC = (0..<8).map { _ in c.next() }
        #expect(fromA == fromB)
        #expect(fromA != fromC)
    }
}
