from scripts import generate_kori_voice as g


def test_sources_and_names(tmp_path, capsys):
    work = g.workout_lines(g.DART.read_text())
    assert len(work) == 28 and work["tracking_lost"].startswith("인식이")
    cal = g.calibration_lines(g.SWIFT.read_text())
    assert len(cal) == 27
    assert cal["calibration_captured_front"] == "정면 찍었어! 이제 왼쪽으로 천천히 돌아 줘"
    assert cal["calibration_captured_leftfront"] == "오른쪽 찍었어!"

    files = g.expand(work, max_n=3)
    assert "pushup_no_lockout" not in files and "pushup_no_lockout_3" in files
    shown, spoken = files["pushup_no_lockout_3"]
    assert "3번 있었어" in shown and "세 번 있었어" in spoken  # app shows digits, voice counts
    assert files["set_summary_1"][1] == "수고했어! 고칠 점 한 개 정리해 뒀어"

    # Dry run: no key needed, nothing written.
    assert g.main(["--dry-run", "--out", str(tmp_path), "--only", "tracking_lost,praise_clean_set", "--max-n", "2"]) == 0
    assert "3 files to generate" in capsys.readouterr().out
    assert not any(tmp_path.iterdir())


def test_native_count():
    assert [g.native_count(n) for n in (1, 4, 10, 11, 20, 21, 30)] == ["한", "네", "열", "열한", "스무", "스물한", "서른"]


def test_needs_key_from_env(tmp_path, monkeypatch):
    monkeypatch.delenv("ELEVENLABS_API_KEY", raising=False)
    assert g.main(["--out", str(tmp_path), "--only", "tracking_lost"]) == 2
    assert not tmp_path.exists() or not any(tmp_path.iterdir())


def test_manifest_and_generate(tmp_path, monkeypatch):
    monkeypatch.setenv("ELEVENLABS_API_KEY", "test")
    sent = []
    monkeypatch.setattr(g, "synthesize", lambda text, *a: sent.append(text) or b"mp3")
    assert g.main(["--out", str(tmp_path), "--only", "row_head_up", "--max-n", "2"]) == 0
    assert sent[1].startswith("고개를 든 렙이 두 번")
    import json
    manifest = json.loads((tmp_path / "manifest.json").read_text())
    assert manifest["고개를 든 렙이 2번 있었어. 목은 몸이랑 일자로, 시선은 바닥으로!"] == "row_head_up_2.mp3"
    sent.clear()
    assert g.main(["--out", str(tmp_path), "--only", "row_head_up", "--max-n", "2"]) == 0 and sent == []  # skips existing
