"""Synthetic analysis checks; no Fit3D or Exercise3D records."""
import gzip
import json
from types import SimpleNamespace

import pytest

from scripts import eval_rules_calib  # installs the scripts import path
import rules_calib_analysis as analysis
from pose_feedback.feedback.form_rules import judge, load_preset


def test_c1_trunk_hold_disables_default_fallback_and_praise(tmp_path, monkeypatch):
    def sample(src, group, width):
        return dict(
            src=src, group=group, model="c1", set_id=f"{src}/{group}",
            exercise="barbell_row", subj="synthetic", pose2d="halpe26",
            up="grav" if src == "fit3d" else "cam", impl="python",
            reps=[dict(rep=i, judged=True, side_view=True,
                       m=dict(torso_min=0.0, torso_max=width, torso_mean=60.0))
                  for i in range(20)],
        )

    source = tmp_path / "sets.json.gz"
    # C1 trained on Fit3D tuning subjects, so these must not influence its threshold.
    held = sample("ex3d", "heldout", 40.0)
    with gzip.open(source, "wt") as f:
        json.dump([sample("fit3d", "tuning", 1000.0),
                   sample("ex3d", "tuning", 70.0), held], f)
    monkeypatch.setattr(analysis, "write_manifest", lambda *args: None)
    analysis.run_analyze(SimpleNamespace(sets=str(source), pose2d="halpe26", run_dir=str(tmp_path)))
    result = json.loads((tmp_path / "analysis.json").read_text())
    preset = json.loads((tmp_path / "presets/xs_c1_rc1.json").read_text())

    assert result["thresholds"]["c1/row_torso_swing/upper"]["threshold"] == pytest.approx(70.0)
    assert result["verdict"]["c1/row_torso_swing/upper"]["hold"]
    actual_rules = {r[0] for r in analysis.RULES}
    assert analysis.TRUNK_RULES & actual_rules <= set(preset["off"])
    assert "row.torsoSwingRangeDegrees" not in preset["values"]
    values = {**load_preset("app_default")[0], **preset["values"]}
    assert all("row_torso_swing" in fired for fired in judge(
        [r["m"] for r in held["reps"]], "barbell_row", values, side_view=[True] * 20))
    assert all(not fired for fired in judge(
        [r["m"] for r in held["reps"]], "barbell_row", values, preset["off"], side_view=[True] * 20))
    assert result["praise"]["c1/barbell_row/ex3d"] == dict(n=20, current=0.0, rc1=1.0)
