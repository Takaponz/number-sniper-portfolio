#!/usr/bin/env python3
"""判定用の効果音WAVを生成する。

標準ライブラリ（math / os / struct / wave）だけで動作する。

使い方:
    python3 tools/generate_sfx.py

出力先:
    NumberSniper/Resources/sfx/{perfect,great,good,miss}.wav

パラメータを含むこのスクリプトが、公開版に同梱する4ファイルの再現可能な正本。
"""

import math
import os
import struct
import wave


SAMPLE_RATE = 44100
OUTPUT_DIR = os.path.join("NumberSniper", "Resources", "sfx")

# (ファイル名, [(周波数Hz, 振幅), ...], 長さ秒)
SOUNDS = [
    ("perfect", [(1046.5, 0.50), (1568.0, 0.32), (2093.0, 0.18)], 0.36),
    ("great", [(880.0, 0.55), (1318.5, 0.28)], 0.28),
    ("good", [(659.3, 0.60)], 0.22),
    ("miss", [(174.6, 0.60), (233.1, 0.28)], 0.30),
]


def amplitude_envelope(index, total_frames, attack_seconds=0.005):
    """立ち上がり直線と指数減衰を組み合わせたエンベロープを返す。"""
    t = index / SAMPLE_RATE
    duration = total_frames / SAMPLE_RATE
    if t < attack_seconds:
        return t / attack_seconds
    decayed = (t - attack_seconds) / max(1e-6, duration - attack_seconds)
    return math.exp(-decayed * 4.0)


def render(name, partials, duration):
    total_frames = int(SAMPLE_RATE * duration)
    frames = bytearray()
    for index in range(total_frames):
        t = index / SAMPLE_RATE
        sample = sum(
            amplitude * math.sin(2 * math.pi * frequency * t)
            for frequency, amplitude in partials
        )
        sample *= amplitude_envelope(index, total_frames) * 0.6
        clamped = max(-1.0, min(1.0, sample))
        frames += struct.pack("<h", int(clamped * 32767))

    path = os.path.join(OUTPUT_DIR, f"{name}.wav")
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(bytes(frames))
    print(f"wrote {path} ({total_frames} frames)")


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for name, partials, duration in SOUNDS:
        render(name, partials, duration)


if __name__ == "__main__":
    main()
