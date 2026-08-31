import Foundation

/// touchDown 1 回に対して何をするか。
public enum PracticeTouchAction: Sendable, Equatable {
    /// 消費済みタッチ ／ 連打ガード中
    case ignore
    case submit
    case advance
}

/// `.active` 復帰時に時計をどう扱うか。
public enum PracticeResumeAction: Sendable, Equatable {
    /// 未判定 → 原点リセット ＋ `lastDrawnTime` 破棄
    case resetCursor
    /// 判定表示中 → 時計に触れない
    case keepFrozen
}

/// 練習モードの入力・復帰の「判断」。純粋関数だけを持つ（`RoundLifecycle` と同じ形）。
///
/// この判断を `PracticeViewModel` に直接書くと、アプリ側にテストターゲットが無いこの
/// リポジトリでは連打ガード・入力ロック・時計リセットの分岐が自動テストで一切
/// 固定されない。判断だけを Core に置いて `swift test` の射程に入れる。
public enum PracticeInput {
    /// - Parameters:
    ///   - isTouchConsumed: このタッチで既に 1 アクション実行済みか。
    ///     `DragGesture(minimumDistance: 0)` の `onChanged` は 1 タッチの間に指のジッタで
    ///     繰り返し発火するため、時間条件だけで組むと「submit → 0.35 秒後に advance →
    ///     同じタッチの次の onChanged で即 submit」の連鎖になる
    ///   - hasResult: 判定表示中か
    ///   - secondsSinceResult: 判定表示が出てからの経過秒
    public static func onTouchDown(
        isTouchConsumed: Bool,
        hasResult: Bool,
        secondsSinceResult: TimeInterval
    ) -> PracticeTouchAction {
        if isTouchConsumed { return .ignore }
        guard hasResult else { return .submit }
        return secondsSinceResult >= GameConfig.practiceMinResultDisplaySeconds ? .advance : .ignore
    }

    /// `.active` 復帰時の時計の扱い。
    ///
    /// - Important: `isTouchConsumed` の解除はこの戻り値に**含めない**。呼び出し側が
    ///   全状態で無条件に行う。条件付きにすると、中断でタッチが失われて `touchUp()` が
    ///   来なかったときに `isTouchConsumed` が true のまま復帰し、以降のタップが全て
    ///   弾かれる入力ロックの再発経路になる
    public static func onResume(hasResult: Bool) -> PracticeResumeAction {
        hasResult ? .keepFrozen : .resetCursor
    }
}
