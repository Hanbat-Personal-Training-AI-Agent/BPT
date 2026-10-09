from scripts import eval_side_videos as ev


def test_truth_and_ratio_and_report(tmp_path):
    truth = tmp_path / "truth.csv"
    truth.write_text("file,exercise,angle_deg,form,wrong_key,reps\n"
                     "a.mp4,row,0,normal,,3\nb.mp4,row,front,wrong,row_torso_swing,2\n,squat,0,normal,,\n")
    rows = ev.read_truth(truth)
    assert len(rows) == 2  # unfilled template row skipped
    assert rows[1]["reps"] == 2 and rows[1]["angle_deg"] == "front"

    # Shoulders 20 px apart, torso 100 px → 0.2; a low-confidence frame is skipped.
    head = "frame,time,status,rep," + ",".join(f"j{j}_x,j{j}_y,j{j}_c" for j in range(17))
    def line(c):
        p = {5: (10, 0), 6: (30, 0), 11: (10, 100), 12: (30, 100)}
        return "0,0,x,0," + ",".join(f"{p.get(j, (0, 0))[0]},{p.get(j, (0, 0))[1]},{c}" for j in range(17))
    kp = tmp_path / "k.csv"
    kp.write_text("\n".join([head, line(0.9), line(0.1)]) + "\n")
    assert ev.shoulder_ratios(kp) == [0.2]

    j = {"reps": [{"start_frame": 10, "end_frame": 20}],
         "events": [{"key": "tracking_lost", "frame": 15}, {"key": "tracking_lost", "frame": 30}, {"key": "setup_side_view", "frame": 1}]}
    assert ev.setup_key_counts(j) == {"setup_full_body": (0, 0), "tracking_lost": (2, 1)}

    results = [{**rows[0], "model": "coco17", "ready": "off", "setup_keys": ev.setup_key_counts(j), "counted": 3, "warnings": [[], [], []], "side_view_event": False, "ratios": [0.2]},
               {**rows[1], "model": "coco17", "ready": "preset", "counted": 0, "warnings": [], "side_view_event": True, "ratios": [0.8]}]
    report = ev.summarize(results)
    assert "| a.mp4 | row | 0 | normal | coco17 | off | 3 | 3 | +0 |  | 0 (0) | 2 (1) |" in report
    assert "| b.mp4 | row | front | wrong | coco17 | preset | 2 | 0 | -2 | 예 | - | - |" in report
    assert "| 0 | coco17 | 1 | 1 | 0.200 | 0.200 | 0.200 | 100% |" in report  # pose stats: ready=off rows only
