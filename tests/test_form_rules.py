"""pose_feedback/feedback/form_rules.py still gives the fixture that pins Swift judge() parity (FormRulePresetTests)."""
import json
from pathlib import Path

from pose_feedback.feedback.form_rules import judge, load_preset

ROOT = Path(__file__).resolve().parents[1]


def test_judge_matches_parity_fixture():
    cases = json.loads((ROOT / "tests/fixtures/form_rules_cases.json").read_text())
    assert len(cases) == 18
    for c in cases:
        assert judge(c["reps"], c["exercise"], c["values"], set(c["off"])) == c["fired"]


def test_presets_merge_over_app_default():
    values, off = load_preset("app_default")
    assert values["squat.valgusKneeAnkleGapRatio"] == 1.0 and off == set()
    assert not any(k.startswith("row.hinge") for k in values)  # rules-calib rules off by default
