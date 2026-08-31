import Foundation
import Testing
@testable import NumberSniperCore

@Suite("練習モードの入力判断")
struct PracticeInputTests {
    private let guardSeconds = GameConfig.practiceMinResultDisplaySeconds

    @Test("消費済みタッチは他の条件によらず無視する")
    func consumedTouchAlwaysIgnored() {
        for hasResult in [true, false] {
            for seconds in [0.0, guardSeconds, 10.0] {
                #expect(PracticeInput.onTouchDown(
                    isTouchConsumed: true, hasResult: hasResult, secondsSinceResult: seconds
                ) == .ignore)
            }
        }
    }

    @Test("未判定のタップは判定する")
    func untouchedRoundSubmits() {
        #expect(PracticeInput.onTouchDown(
            isTouchConsumed: false, hasResult: false, secondsSinceResult: 0
        ) == .submit)
        // 未判定なら経過秒は見ない
        #expect(PracticeInput.onTouchDown(
            isTouchConsumed: false, hasResult: false, secondsSinceResult: 99
        ) == .submit)
    }

    @Test("連打ガード中のタップは無視する")
    func ignoresWithinGuardWindow() {
        #expect(PracticeInput.onTouchDown(
            isTouchConsumed: false, hasResult: true, secondsSinceResult: 0
        ) == .ignore)
        #expect(PracticeInput.onTouchDown(
            isTouchConsumed: false, hasResult: true, secondsSinceResult: guardSeconds - 0.01
        ) == .ignore)
    }

    @Test("ガード時間ちょうどで次の問題へ進む")
    func advancesAtGuardBoundary() {
        #expect(PracticeInput.onTouchDown(
            isTouchConsumed: false, hasResult: true, secondsSinceResult: guardSeconds
        ) == .advance)
        #expect(PracticeInput.onTouchDown(
            isTouchConsumed: false, hasResult: true, secondsSinceResult: guardSeconds + 0.01
        ) == .advance)
    }

    @Test("境界は 0.34 秒 → 無視 / 0.35 秒ちょうど → 前進（秒数をリテラルで固定）")
    func guardBoundaryIsFixedInSeconds() {
        // 上の 2 件は入力を practiceMinResultDisplaySeconds から導出しているので、
        // 定数を 0.10 秒に変えても追従して通る。確定済み要件の 0.35 秒はここで固定する
        #expect(PracticeInput.onTouchDown(
            isTouchConsumed: false, hasResult: true, secondsSinceResult: 0.34
        ) == .ignore)
        #expect(PracticeInput.onTouchDown(
            isTouchConsumed: false, hasResult: true, secondsSinceResult: 0.35
        ) == .advance)
    }

    @Test("復帰時、未判定ならカーソルを原点へ戻す")
    func resumeResetsCursorWhenUnjudged() {
        #expect(PracticeInput.onResume(hasResult: false) == .resetCursor)
    }

    @Test("復帰時、判定表示中は時計に触れない")
    func resumeKeepsFrozenWhileShowingResult() {
        #expect(PracticeInput.onResume(hasResult: true) == .keepFrozen)
    }
}
