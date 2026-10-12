import csv

from scripts.data_collect import eval_public_sets as ev
from scripts.data_collect import make_split, merge_labels


def test_split_is_fixed_and_balanced(tmp_path):
    p = tmp_path / "split.csv"
    rows = make_split.add(p, "src", [f"s{i}" for i in range(6)])
    assert sorted(r["split"] for r in rows).count("heldout") == 3
    again = make_split.add(p, "src", ["s0", "s9"])  # old rows never move
    assert again[:6] == rows and again[6]["person_id"] == "s9"


def test_merge_two_passes():
    t = {"reps": "8", "partial": "1", "rep_conf": "high", "form": "wrong", "view_check": "side", "people": "1", "notes": ""}
    meta = merge_labels.mendeley_meta("subject_003_push_up_bad_side")
    assert meta["exercise"] == "pushup" and meta["person_id"] == "s003"
    r = merge_labels.merge({**t, "wrong_keys": "pushup_hip_sag:all:high"},
                           {**t, "reps": "9", "wrong_keys": "pushup_hip_sag:2,3:medium;pushup_head_drop:all:low"},
                           meta, {("mendeley_mv7", "s003"): "heldout"})
    assert r["rep_status"] == "uncertain" and r["form"] == "wrong" and r["wrong_key"] == "pushup_hip_sag"
    assert r["uncertain_keys"] == "pushup_head_drop" and r["split"] == "heldout"


def test_scores_and_tracking_quality():
    s = ev.score([{"truth": 10, "counted": 8, "partial": 0}, {"truth": 5, "counted": 6, "partial": 1}])
    assert (s["missed"], s["extra"], s["exact"]) == (2, 1, 0)
    assert ev.score([{"truth": 5, "counted": 6, "partial": 1}], lenient=True)["exact"] == 1
    assert ev.unknown_frac({"transitions": ["0:top", "2:unknown", "6:bottom"], "frames": 10}) == 0.4
    j = {"reps": [{"warnings": ["row_torso_swing"]}, {"warnings": []}], "events": []}
    assert ev.fired(j, "row_torso_swing") == ([True, False], True)


def test_committed_labels_are_consistent():
    split = {(r["source"], r["person_id"]): r["split"] for r in csv.DictReader(open("data/eval_sources/split.csv"))}
    for name in ("mendeley_mv7", "youtube_cc"):
        for r in csv.DictReader(open(f"data/eval_sources/{name}_labels.csv")):
            assert r["split"] == split[(r["source"], r["person_id"])]
            if r["rep_status"] == "ok":
                assert r["reps"].isdigit()
            if r["form"] == "wrong":
                assert r["wrong_key"] and r["form_status"] == "ok"
