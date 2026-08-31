import SwiftUI

extension View {
    /// 設定シートを開く歯車を右上に重ねる。**タイトルとリザルトで同じ見た目**にするための単一正本。
    ///
    /// タイトルとリザルトで同じ位置・同じシートを使う。**コピペで 2 箇所に置かない** ─ 片方の
    /// `padding` / `font` / SF Symbol を触ると無言でドリフトし、検出手段が実機の目視項目 2 つしか
    /// 無くなる（`AppStrings` に文言を集約する規約・チューニング定数を 2 箇所に閉じる規約と同じ理由）。
    ///
    /// `overlay` で重ねるのは、置き先の 2 画面がどちらも `Spacer()` で縦配分している `VStack` だから。
    /// `VStack` の子として足すと上下のバランスが変わる。
    ///
    /// - Important: **プレイ中・練習モードには付けない**（ポーズボタンを置かない方針と整合）。
    func settingsGearOverlay(action: @escaping () -> Void) -> some View {
        overlay(alignment: .topTrailing) {
            Button(action: action) {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
            .accessibilityLabel(AppStrings.settings)
            .padding(.trailing, 8)
        }
    }
}
