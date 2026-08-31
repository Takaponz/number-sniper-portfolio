import Foundation
import NumberSniperCore

/// ユーザーに見える文字列の集約点。
/// ~~正式アプリ名が未定のため、名前確定時にこのファイルだけを変更すれば済むようにしている。~~
/// → **2026-08-27 に「数直線スナイパー」で確定**。集約自体は文字列の単一出所として維持する。
enum AppStrings {
    /// 画面上に出すアプリ名。**2026-08-27 に「数直線スナイパー」で確定**。
    /// 単一の出所を保つため Info.plist の `CFBundleDisplayName`（ビルド設定の
    /// `INFOPLIST_KEY_CFBundleDisplayName`）から読む。変えるときは
    /// **ビルド設定の 2 箇所**（Debug / Release）を直せばアプリ名とホーム画面の表示が揃う
    static let displayName: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "数直線スナイパー"
    }()

    static let start = "スタート"
    static let retry = "もう一度"
    /// リザルトからタイトルへ戻る
    static let backToTitle = "タイトルへ"
    static let ranking = "ランキング"
    static let share = "シェア"
    static let best = "ベスト"
    static let newBest = "ベスト更新！"
    static let score = "スコア"
    static let gameOver = "ゲームオーバー"

    static let resumeCountdownSuffix = "秒後に再開"

    // MARK: - 復活オファー

    /// ライフ 0 のあとに出す復活オファーの見出し
    static let continueTitle = "復活しますか？"
    /// リワード広告を見て復活する導線
    static let continueWatchAd = "広告を見て復活"
    /// 復活を辞退してリザルトへ進む導線
    static let continueDecline = "あきらめる"

    /// オファーの残り秒数。0 になったら自動で辞退扱いになることが伝わる文言にする
    static func continueCountdown(remaining: Int) -> String { "あと \(remaining) 秒" }

    /// プレイ画面のステータス表示
    static let levelPrefix = "Lv"
    static let comboSuffix = "COMBO"

    static func level(_ level: Int) -> String { "\(levelPrefix)\(level)" }

    static func combo(_ combo: Int) -> String { "\(combo) \(comboSuffix)" }

    /// 判定バッジの表示ラベル。
    static func judgementLabel(_ judgement: Judgement) -> String {
        switch judgement {
        case .perfect: "PERFECT"
        case .great: "GREAT"
        case .good: "GOOD"
        case .miss: "MISS"
        }
    }

    static let timeUp = "TIME UP"

    /// 数直線の上に出すレンジの明示ラベル。
    /// 0〜1 のときは nil（既定なので出す必要がなく、毎問出すと逆に注意が薄れる）。
    static func rangeCaption(_ range: LineRange) -> String? {
        range.isUnit ? nil : "\(range.lowerLabel) 〜 \(range.upperLabel)"
    }

    /// 判定バッジの表示ラベル。時間切れはスコア上 MISS と同じ扱いだが、
    /// 「押し損ねた」のか「時間切れ」なのかがプレイヤーに伝わるよう表示だけ分ける。
    static func judgementLabel(_ result: RoundResult) -> String {
        result.isTimeUp ? timeUp : judgementLabel(result.judgement)
    }

    static func shareMessage(score: Int) -> String {
        "\(displayName) で \(score) 点。数字の位置、どこまで当てられる？"
    }

    // MARK: - 練習モード

    /// リザルトから練習モードに入る導線
    static let practice = "練習する"
    /// 練習モードから本編へ戻る導線。**Lv1 から始まる**ことが伝わる文言にする
    static let practiceRetry = "はじめから挑戦"
    static let practiceNextHint = "タップで次の問題"
    /// ズレ 0 のときの表示。「ぴったり」の文字列の出所はここ 1 箇所だけにする
    static let practiceExact = "ぴったり"

    // 内部名を分けるのは、`level` が同名の静的メソッドを隠してしまうため
    static func practiceHeader(level value: Int) -> String { "\(level(value)) の練習" }

    static func practiceSolved(count: Int) -> String { "\(count) 問" }

    /// ズレの主表示。方向の矢印 ＋ 実数値（例: `← 3` / `→ 0.25`）。
    /// ぴったりのときは矢印を出さず `practiceExact` を返す。
    static func practiceOffset(_ result: PracticeResult) -> String {
        switch result.direction {
        case .exact: practiceExact
        case .left: "← \(result.offset.magnitudeText)"
        case .right: "→ \(result.offset.magnitudeText)"
        }
    }

    /// ズレの副表示。実数値ズレが 0〜1 の小数になるお題（パーセント・分数・√）でも
    /// 量の感覚が掴めるよう、全お題で共通の尺度として併記する
    static func practiceOffsetPercent(_ result: PracticeResult) -> String {
        "レンジの \(result.offsetPercent)%"
    }

    // MARK: - 設定

    static let settings = "設定"
    static let settingsDone = "完了"
    static let settingsBGM = "BGM"
    static let settingsSound = "効果音"
    static let settingsHaptics = "振動"
}
