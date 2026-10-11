import json

from scripts import compare_perf_logs as cp


def _log(path, fps, recording, battery0=0.8):
    rows = [{"t": i, "pose_fps": fps, "dropped_frames": 1 if i % 2 else 0,
             "thermal": "serious" if i >= 8 else "fair", "battery": battery0 - 0.01 * i, "recording": recording}
            for i in range(10)]
    path.write_text("\n".join(json.dumps(r) for r in rows) + "\n")
    return path


def test_report_flags_fps_drop(tmp_path):
    off = cp.load(_log(tmp_path / "off.jsonl", 30.0, False))
    on = cp.load(_log(tmp_path / "on.jsonl", 26.0, True))
    table, drop = cp.report(off, on)
    assert abs(drop - 4 / 30) < 1e-9
    assert "| 포즈 FPS 평균 | 30.0 | 26.0 |" in table
    assert "| 녹화 켜진 비율(%) | 0.0 | 100.0 |" in table
    assert "| 버린 프레임/초 | 0.50 | 0.50 |" in table
    assert "| 발열 serious 이상(%) | 20.0 | 20.0 |" in table
    assert "| 배터리 사용(%p) | 9.0 | 9.0 |" in table
    assert "녹화 기본 OFF 유지" in table

    _, small = cp.report(off, cp.load(_log(tmp_path / "on2.jsonl", 28.0, True)))
    assert small < cp.FPS_DROP_LIMIT
    assert len(cp.load(tmp_path / "off.jsonl", skip_seconds=3)) == 7
