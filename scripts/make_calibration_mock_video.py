"""Assemble the calibration mock video: rendered app frames + Kori's voice + a phone frame.

Inputs in outputs/app_mock/ (see tool/calibration_mock_video_test.dart):
  frames/####.png  real Flutter UI rendered per frame (scan screen, then the analysis screen)
  states.json      per-frame engine state the frames were rendered from
Output: outputs/app_mock/calibration_mock.mp4

Sound follows the app's rules (CalibrationVoice / CalibrationSession): a line is spoken when the
guidance changes or after its repeat interval, capture/finish/return lines cut in, the beep speeds
up as the user nears an oblique or the back, and each capture chimes. Speech is macOS `say`
with the Yuna voice, the same Korean voice iOS uses by default.
"""
import json
import math
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
MOCK = ROOT / "outputs/app_mock"
FPS = 25
RATE = 44_100
CANVAS = (1080, 1920)
BEZEL = 14
FONT = "/System/Library/Fonts/AppleSDGothicNeo.ttc"

# CalibrationConfig.voice / .view, mirrored for the simulation
REPEAT_MIN, REPEAT_MAX = 3.0, 4.5
BEEP_MAX, BEEP_MIN = 0.9, 0.15
OBLIQUE_CENTRE = (0.31 + 0.75) / 2


def interrupts(line):
    return "찍었어!" in line or line.startswith("잠깐! 처음") or line.startswith("천천히 해도 돼")


def speech_clip(line, cache={}):
    if line not in cache:
        with tempfile.TemporaryDirectory() as tmp:
            aiff, wav = Path(tmp) / "a.aiff", Path(tmp) / "a.wav"
            subprocess.run(["say", "-v", "Yuna", "-o", str(aiff), line], check=True)
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(aiff), "-ar", str(RATE), "-ac", "1",
                            "-sample_fmt", "s16", str(wav)], check=True)
            with wave.open(str(wav)) as w:
                cache[line] = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768
    return cache[line]


def tone(freq, seconds):
    n = int(RATE * seconds)
    fade = int(RATE * 0.005)
    env = np.minimum(1, np.minimum(np.arange(n), np.arange(n)[::-1]) / fade)
    return (np.sin(2 * math.pi * freq * np.arange(n) / RATE) * env * 0.5).astype(np.float32)


def soundtrack(states, total_frames):
    out = np.zeros(int(RATE * total_frames / FPS) + RATE, np.float32)
    clips = []                       # [start, end, samples]
    last_line, last_spoken = None, -1e9
    last_beep, captured = -1e9, 0
    tick, chime = tone(880, 0.06), tone(1320, 0.16)
    for s in states:
        t = s["t"]
        if len(s["captured"]) > captured:
            captured = len(s["captured"])
            i = int(t * RATE); out[i:i + len(chime)] += chime * 0.45
        line = s["guidance"]
        speaking = bool(clips) and clips[-1][1] > t
        repeat = REPEAT_MIN + (REPEAT_MAX - REPEAT_MIN) * min(1, len(line) / 30)
        if line != last_line or t - last_spoken >= repeat:
            if interrupts(line) and speaking:
                clips[-1][1] = t     # cut the current line off
                speaking = False
            if not speaking:
                audio = speech_clip(line)
                clips.append([t, t + len(audio) / RATE, audio])
                last_line, last_spoken = line, t
        target, r = s["target"], s["r"]
        if not s["pass"] and r is not None and target in ("rightfront", "leftfront", "back"):
            if target == "back":
                progress = 0.2 * r if s["faceDetected"] else r
            else:
                progress = max(0.0, 1 - abs(r - OBLIQUE_CENTRE) / OBLIQUE_CENTRE)
            interval = BEEP_MAX - (BEEP_MAX - BEEP_MIN) * min(max(progress, 0), 1)
            if t - last_beep >= interval:
                last_beep = t
                i = int(t * RATE); out[i:i + len(tick)] += tick * 0.25
    for start, end, audio in clips:
        i = int(start * RATE)
        n = min(len(audio), int((end - start) * RATE), len(out) - i)
        out[i:i + n] += audio[:n] * 0.9
    out = out[:int(RATE * total_frames / FPS)]
    return np.clip(out / max(1.0, np.abs(out).max()), -1, 1)


def phone_frame(screen, fonts):
    canvas = Image.new("RGB", CANVAS, (17, 17, 19))
    w, h = screen.size
    x, y = (CANVAS[0] - w) // 2, 46
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle([x - BEZEL, y - BEZEL, x + w + BEZEL, y + h + BEZEL], radius=112, fill=(4, 4, 6),
                           outline=(58, 58, 64), width=3)
    mask = Image.new("L", screen.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w, h], radius=98, fill=255)
    canvas.paste(screen, (x, y), mask)
    # iOS status bar and Dynamic Island, which Flutter does not draw
    draw.rounded_rectangle([x + w // 2 - 125, y + 22, x + w // 2 + 125, y + 92], radius=35, fill=(0, 0, 0))
    draw.text((x + 70, y + 36), "9:41", font=fonts["status"], fill="white")
    bx, by = x + w - 112, y + 44
    draw.rounded_rectangle([bx, by, bx + 52, by + 26], radius=7, outline="white", width=3)
    draw.rounded_rectangle([bx + 5, by + 5, bx + 40, by + 21], radius=4, fill="white")
    draw.rectangle([bx + 54, by + 8, bx + 58, by + 18], fill="white")
    for k, bar in enumerate((10, 15, 20, 26)):
        draw.rectangle([x + w - 196 + k * 11, by + 26 - bar, x + w - 189 + k * 11, by + 26], fill="white")
    caption_y = y + h + BEZEL + 26
    draw.text((CANVAS[0] // 2, caption_y), "BPT 체형 촬영 목업 · 실제 앱 UI + 판정 엔진 재생",
              font=fonts["caption"], fill=(235, 235, 240), anchor="ma")
    draw.text((CANVAS[0] // 2, caption_y + 46),
              "테스트 영상 People Snapshot · 자세 기준 완화 · 음성 macOS Yuna",
              font=fonts["small"], fill=(150, 150, 158), anchor="ma")
    return canvas


def main():
    states = json.loads((MOCK / "states.json").read_text())
    frames = sorted((MOCK / "frames").glob("*.png"))
    fonts = {"status": ImageFont.truetype(FONT, 30, index=6), "caption": ImageFont.truetype(FONT, 34, index=6),
             "small": ImageFont.truetype(FONT, 26)}

    composite = MOCK / "composite"
    composite.mkdir(exist_ok=True)
    for old in composite.glob("*.png"):
        old.unlink()
    for i, path in enumerate(frames):
        phone_frame(Image.open(path).convert("RGB"), fonts).save(composite / f"{i:04d}.png")

    audio = soundtrack(states, len(frames))
    wav_path = MOCK / "soundtrack.wav"
    with wave.open(str(wav_path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes((audio * 32767).astype(np.int16).tobytes())

    out = MOCK / "calibration_mock.mp4"
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", str(FPS), "-i", str(composite / "%04d.png"),
                    "-i", str(wav_path), "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18",
                    "-c:a", "aac", "-b:a", "160k", "-shortest", str(out)], check=True)
    print(f"output={out} frames={len(frames)} seconds={len(frames) / FPS:.1f}")


if __name__ == "__main__":
    main()
