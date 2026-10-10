"""Generate Kori's Korean voice lines as mp3 with ElevenLabs.

Sources (single source of truth, parsed, never copied):
  - workout: lib/features/workout/data/kori_feedback_lines.dart (`key`, `ko`)
  - calibration: ios/Runner/NativePose/Calibration/CalibrationTypes.swift (CalibrationGuidance.message)

Output names (what WorkoutVoice / CalibrationVoice look up, see docs/handoff/kori_voice.md):
  assets/kori_voice/<key>.mp3                 workout line without a placeholder
  assets/kori_voice/<key>_<n>.mp3             line with {n}/{reps}/{k}, n = 1..--max-n
  assets/kori_voice/calibration_<case>.mp3    calibration guidance (e.g. calibration_holdPhoneUpright)
  assets/kori_voice/calibration_captured_<view>.mp3

Key: env ELEVENLABS_API_KEY only (never an argument, never printed). Voice: --voice-id or env
ELEVENLABS_VOICE_ID. --dry-run lists files and character count without touching the network.

  conda run -n bpt-eval python scripts/generate_kori_voice.py --dry-run
  ELEVENLABS_API_KEY=... conda run -n bpt-eval python scripts/generate_kori_voice.py --voice-id <id>
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DART = ROOT / "lib/features/workout/data/kori_feedback_lines.dart"
SWIFT = ROOT / "ios/Runner/NativePose/Calibration/CalibrationTypes.swift"
PLACEHOLDER = re.compile(r"\{(n|reps|k)\}")

_UNITS = ["", "한", "두", "세", "네", "다섯", "여섯", "일곱", "여덟", "아홉"]
_TENS = ["", "열", "스물", "서른", "마흔", "쉰", "예순", "일흔", "여든", "아흔"]


def native_count(n: int) -> str:
    """Counting form before 번/개: 3 → 세, 20 → 스무, 21 → 스물한. 1..99."""
    if not 1 <= n <= 99:
        raise ValueError(n)
    if n == 20:
        return "스무"
    return _TENS[n // 10] + _UNITS[n % 10]


def workout_lines(text: str) -> dict[str, str]:
    pairs = re.findall(r"key:\s*'([^']+)',.*?ko:\s*'([^']*)'", text, re.S)
    return dict(pairs)


def calibration_lines(text: str) -> dict[str, str]:
    lines = {f"calibration_{case}": msg
             for case, msg in re.findall(r'case \.(\w+): return "([^"]*)"', text)}
    names = dict(re.findall(r'case \.(\w+): return "([^"]*)"',
                            _block(text, "var koreanName")))
    nexts = dict(re.findall(r'case \.(\w+): return "([^"]*)"',
                            _block(text, "var nextStepInstruction")))
    for view, name in names.items():
        # Mirrors CalibrationGuidance.captured: "<name> 찍었어!" + " <next>" when there is one.
        nxt = nexts.get(view, "")
        lines[f"calibration_captured_{view}"] = f"{name} 찍었어! {nxt}".strip()
        lines.pop(f"calibration_{view}", None)
    for view in nexts:
        lines.pop(f"calibration_{view}", None)
    return lines


def _block(text: str, header: str) -> str:
    start = text.index(header)
    return text[start:text.index("\n    }\n", start)]


def expand(lines: dict[str, str], max_n: int) -> dict[str, str]:
    """File stem → spoken text. Placeholder lines become <key>_1..<key>_<max_n>."""
    out = {}
    for key, ko in lines.items():
        if PLACEHOLDER.search(ko):
            for n in range(1, max_n + 1):
                # Every placeholder is followed by a counter (번/개): "{n}번" → "세 번".
                out[f"{key}_{n}"] = PLACEHOLDER.sub(native_count(n) + " ", ko)
        else:
            out[key] = ko
    return out


def synthesize(text: str, voice_id: str, model_id: str, api_key: str) -> bytes:
    req = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}?output_format=mp3_44100_128",
        data=json.dumps({"text": text, "model_id": model_id}).encode(),
        headers={"xi-api-key": api_key, "Content-Type": "application/json", "Accept": "audio/mpeg"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--out", type=Path, default=ROOT / "assets/kori_voice")
    p.add_argument("--voice-id", default=os.environ.get("ELEVENLABS_VOICE_ID"))
    p.add_argument("--model-id", default="eleven_multilingual_v2")
    p.add_argument("--max-n", type=int, default=20, help="numbered files 1..N for {n}/{reps}/{k} lines")
    p.add_argument("--only", help="comma-separated file stems or key prefixes to generate")
    p.add_argument("--set", choices=["all", "workout", "calibration"], default="all")
    p.add_argument("--overwrite", action="store_true", help="regenerate files that already exist")
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args(argv)

    lines: dict[str, str] = {}
    if a.set in ("all", "workout"):
        lines |= expand(workout_lines(DART.read_text()), a.max_n)
    if a.set in ("all", "calibration"):
        lines |= calibration_lines(SWIFT.read_text())
    if a.only:
        wanted = a.only.split(",")
        lines = {k: v for k, v in lines.items() if any(k == w or k.startswith(w + "_") for w in wanted)}
    todo = {k: v for k, v in lines.items() if a.overwrite or not (a.out / f"{k}.mp3").exists()}

    print(f"{len(todo)} files to generate ({len(lines) - len(todo)} already exist), "
          f"{sum(len(v) for v in todo.values())} characters")
    if a.dry_run:
        for k, v in todo.items():
            print(f"  {k}.mp3\t{v}")
        return 0

    api_key = os.environ.get("ELEVENLABS_API_KEY")
    if not api_key or not a.voice_id:
        print("ELEVENLABS_API_KEY (env) and --voice-id / ELEVENLABS_VOICE_ID are required", file=sys.stderr)
        return 2
    a.out.mkdir(parents=True, exist_ok=True)
    for i, (k, v) in enumerate(todo.items(), 1):
        (a.out / f"{k}.mp3").write_bytes(synthesize(v, a.voice_id, a.model_id, api_key))
        print(f"[{i}/{len(todo)}] {k}.mp3")
    return 0


if __name__ == "__main__":
    sys.exit(main())
