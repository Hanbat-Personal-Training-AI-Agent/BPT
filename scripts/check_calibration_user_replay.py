"""체형 촬영 재생 회귀 검사 (docs/results/calib_fix.md).

사용자 영상 2개(~/bpt-data/user_tests/2026-10-22, git 밖)와 더미 6개를 calib-rca로 재생하고
명세(docs/results/calib_root_cause.md 7절)의 기대값을 확인한다. 없는 영상은 건너뛴다.

    lockf -k /tmp/bpt-heavy.lock nice -n 10 swift build -c release --package-path scripts/calib_rca
    lockf -k /tmp/bpt-heavy.lock nice -n 10 conda run -n bpt-eval python -I scripts/check_calibration_user_replay.py [출력 폴더]

실패가 하나라도 있으면 종료 코드 1.
"""
import csv
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
TOOL = REPO / "scripts/calib_rca/.build/release/calib-rca"
USER = Path.home() / "bpt-data/user_tests/2026-10-22"
DUMMY = REPO.parent.parent.parent / "outputs/calibration_dummy_videos"  # 워크트리면 본 체크아웃의 outputs
if not DUMMY.exists():
    DUMMY = REPO / "outputs/calibration_dummy_videos"
REC = ["--hflip", "--pad-aspect", "0.5625", "--step", "2"]


def replay(video: Path, out: Path, *opts: str) -> list[dict]:
    subprocess.run([str(TOOL), *opts, str(video), str(out)], check=True, stdout=subprocess.DEVNULL)
    with out.open() as f:
        return list(csv.DictReader(f))


def captures(rows: list[dict]) -> dict[str, float]:
    """방향 → 처음 찍힌 시각(초)."""
    seen: dict[str, float] = {}
    for r in rows:
        for view in filter(None, r["captured"].split("|")):
            seen.setdefault(view, float(r["t"]))
    return seen


def main() -> int:
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(tempfile.mkdtemp(prefix="calib_replay_"))
    out_dir.mkdir(parents=True, exist_ok=True)
    failures: list[str] = []

    def check(ok: bool, what: str) -> None:
        print(("  ok   " if ok else "  FAIL ") + what)
        if not ok:
            failures.append(what)

    img, rec = USER / "IMG_9900.MOV", USER / "screenrec_161547.mp4"
    cases = []
    if img.exists():
        cases += [("IMG_9900", img, [], True), ("IMG_9900 tilt+8 roll-8", img, ["--tilt-image", "8", "--roll", "-8"], False),
                  ("IMG_9900 tilt-8 roll+8", img, ["--tilt-image", "-8", "--roll", "8"], False)]
    if rec.exists():
        cases += [("screenrec", rec, REC, False), ("screenrec tilt+8 roll-8", rec, REC + ["--tilt-image", "8", "--roll", "-8"], False),
                  ("screenrec tilt-8 roll+8", rec, REC + ["--tilt-image", "-8", "--roll", "8"], False)]
    for name, video, opts, needs_back in cases:
        rows = replay(video, out_dir / (name.replace(" ", "_") + ".csv"), *opts)
        got = captures(rows)
        forward = sum(r["guidance"] == "stepForward" for r in rows)
        print(f"{name}: {len(rows)} frames, captured {got}, stepForward {forward}")
        limit = 3.5 if not opts or opts == REC else 10.0
        check(got.get("front", 99) <= limit, f"{name}: 정면 ≤ {limit} s")
        check(forward == 0, f"{name}: stepForward 0프레임")
        if needs_back:
            check("back" in got, f"{name}: 뒷면 촬영")

    for video in sorted(DUMMY.glob("*.mp4")) + sorted(DUMMY.glob("v2_continuous/*.mp4")):
        name = ("v2/" if video.parent.name == "v2_continuous" else "v1/") + video.stem
        got = captures(replay(video, out_dir / (name.replace("/", "__") + ".csv")))
        print(f"{name}: captured {got}")
        if name == "v1/dummy_03_male-4-sport":
            check(len(got) == 4, f"{name}: 4장 (F2+F3 명세값)")

    print(f"CSV: {out_dir}")
    print("FAILED: " + "; ".join(failures) if failures else "ALL PASSED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
