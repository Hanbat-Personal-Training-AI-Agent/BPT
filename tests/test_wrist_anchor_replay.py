"""Offline wrist checks must activate from recorded reps, not label estimates."""
import csv
import importlib.util
from pathlib import Path

import numpy as np
import pytest


spec = importlib.util.spec_from_file_location(
    "eval_wrist_anchor", Path(__file__).resolve().parents[1] / "scripts/eval_wrist_anchor.py"
)
evaluation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evaluation)


def write_replay(path, joints, reps, frames=None):
    fields = ["frame", "time", "status", "rep"]
    fields += [f"j{j}_{axis}" for j in range(joints) for axis in ("x", "y", "c")]
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fields)
        writer.writeheader()
        for i, rep in enumerate(reps):
            row = dict(frame=frames[i] if frames is not None else i, time=i / 30, status="ready", rep=rep)
            row.update({f"j{j}_{axis}": j if axis != "c" else 0.9 for j in range(joints) for axis in ("x", "y", "c")})
            writer.writerow(row)


@pytest.mark.parametrize("joints", [17, 26])
def test_activation_uses_actual_rep_counter_with_sparse_frame_ids(tmp_path, joints):
    path = tmp_path / "replay.csv"
    write_replay(path, joints, [0, 0, 1, 1], frames=[21, 22, 24, 25])
    keypoints, frames, active_from = evaluation.read_replay_input(path)
    assert keypoints.shape == (4, 17, 3)
    np.testing.assert_array_equal(keypoints[0, :, 0], np.arange(17))
    np.testing.assert_array_equal(frames, [21, 22, 24, 25])
    assert active_from == 2


def test_no_counted_rep_never_initializes_anchor(tmp_path):
    path = tmp_path / "replay.csv"
    write_replay(path, 26, [0] * 30)
    keypoints, _, active_from = evaluation.read_replay_input(path)
    output, reports = evaluation.simulate(keypoints, active_from)
    np.testing.assert_array_equal(output, keypoints)
    assert all(r == {9: "none", 10: "none"} for r in reports)


def test_duplicate_frame_ids_are_rejected(tmp_path):
    path = tmp_path / "replay.csv"
    write_replay(path, 17, [0, 1], frames=[1, 1])
    with pytest.raises(ValueError, match="frame IDs must increase"):
        evaluation.read_replay_input(path)
