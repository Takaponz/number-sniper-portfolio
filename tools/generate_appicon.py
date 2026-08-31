#!/usr/bin/env python3
"""仮のアプリアイコン（1024x1024 PNG）を生成する。

使い方:
    python3 tools/generate_appicon.py

正式なアートワークが決まるまでのプレースホルダ。
「目盛りのない数直線 ＋ 1 本のマーカー」というゲームの見た目をそのまま図案にしている。
"""
import os

from PIL import Image, ImageDraw

SIZE = 1024
OUTPUT_PATH = os.path.join(
    "NumberSniper", "Resources", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png"
)

BACKGROUND = (18, 20, 28)
LINE_COLOR = (78, 84, 104)
MARKER_COLOR = (255, 214, 64)
TARGET_COLOR = (64, 214, 138)


def main():
    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    image = Image.new("RGB", (SIZE, SIZE), BACKGROUND)
    draw = ImageDraw.Draw(image)

    # 数直線（目盛りなし）
    line_y = SIZE // 2
    line_height = 26
    draw.rounded_rectangle(
        [(140, line_y - line_height // 2), (SIZE - 140, line_y + line_height // 2)],
        radius=line_height // 2,
        fill=LINE_COLOR,
    )

    # 目標位置（薄く）
    target_x = int(140 + (SIZE - 280) * 0.62)
    draw.rounded_rectangle(
        [(target_x - 9, line_y - 150), (target_x + 9, line_y + 150)],
        radius=9,
        fill=TARGET_COLOR,
    )

    # カーソル（主役）
    cursor_x = int(140 + (SIZE - 280) * 0.62)
    draw.rounded_rectangle(
        [(cursor_x - 16, line_y - 250), (cursor_x + 16, line_y + 250)],
        radius=16,
        fill=MARKER_COLOR,
    )

    image.save(OUTPUT_PATH, "PNG")
    print(f"wrote {OUTPUT_PATH} ({SIZE}x{SIZE})")


if __name__ == "__main__":
    main()
