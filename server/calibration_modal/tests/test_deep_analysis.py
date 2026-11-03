"""외부 저장소·모델·영상 없이 계약 및 합성 H36M 시퀀스를 검증한다."""
import copy
import json
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from types import SimpleNamespace

import numpy as np
import pytest
from fastapi.testclient import TestClient

import deep_analysis as deep
import deep_metrics
import deep_worker
import service
from checks import Rejected
from conftest import SECRET, bundle, token


class State:
    def __init__(self):
        self.data, self.lock = {}, threading.Lock()

    def get(self, key, default=None):
        with self.lock:
            return copy.deepcopy(self.data.get(key, default))

    def put(self, key, value, skip_if_exists=False):
        with self.lock:
            if skip_if_exists and key in self.data:
                return False
            self.data[key] = copy.deepcopy(value)
            return True

    def pop(self, key, default=None):
        with self.lock:
            return self.data.pop(key, default)


class Bucket:
    def __init__(self):
        self.objects, self.gets = {}, []

    def presign_put(self, key, content_type, size):
        return "https://storage.example/" + key

    def presign_get(self, key, ttl):
        self.gets.append((key, ttl))
        return f"https://storage.example/{key}?signature={len(self.gets)}"

    def head(self, key):
        value = self.objects.get(key)
        return (len(value[0]), value[1]) if value else None

    def get(self, key):
        return self.objects[key][0]

    def latest(self, prefix):
        return ([k for k in self.objects if k.startswith(prefix)] or [None])[-1]

    def put_bytes(self, key, data, content_type):
        self.objects[key] = (data, content_type)

    def put_json(self, key, data):
        self.put_bytes(key, json.dumps(data).encode(), "application/json")


def manifest(count=4):
    return {"schemaVersion": 1, "sessionId": "set-1", "exerciseId": "squat", "timebase": "video_ms",
            "reps": [{"repIndex": i + 1, "startMs": i * 1000, "endMs": (i + 1) * 1000,
                      "side": "left", "onDeviceWarnings": []} for i in range(count)]}


def skeleton():
    joints = np.zeros((120, 17, 3))
    for leg, x in ((1, -.2), (4, .2)):
        joints[:, leg] = [x, 1, 0]
        joints[:, leg + 1] = [x, .5, 0]
        for rep in range(4):
            peak = 90 if rep < 3 else 60
            flexion = np.radians(np.r_[np.linspace(10, peak, 16), np.linspace(peak, 10, 15)[1:]])
            joints[rep * 30:(rep + 1) * 30, leg + 2] = np.column_stack(
                (np.full(30, x), .5 - .5 * np.cos(flexion), .5 * np.sin(flexion)))
    joints[:, 0] = [0, 1, 0]
    for arm, x in ((11, .2), (14, -.2)):
        joints[:, arm] = [x, 1.5, 0]
        joints[:, arm + 1] = [x, 1.25, .1]
        joints[:, arm + 2] = [x, 1, .2]
    return joints


def supported_metrics(joints, fps, m, **kwargs):
    """Synthetic fixtures explicitly provide every observed joint and tracking frame."""
    kwargs.setdefault("joint_confidence", np.full((len(joints), 17), .8))
    kwargs.setdefault("tracked_mask", np.ones(len(joints), dtype=bool))
    return deep.metrics(joints, fps, m, **kwargs)


def test_metrics_known_angles_boundaries_and_comparison():
    report = supported_metrics(skeleton(), 30, manifest(), confidence=np.full(120, .8))
    first, last = report["reps"][0], report["reps"][-1]
    assert first["depthAngleDeg"] == pytest.approx(90)
    assert first["romDeg"] == pytest.approx(80)
    assert first["anglesDeg"]["torso"] == {"min": 0, "max": 0, "rom": 0, "top": 0, "bottom": 0}
    assert first["anglesDeg"]["knee"]["bottom"] == 90
    assert first["anglesDeg"]["knee"]["top"] == 170
    assert first["anglesDeg"]["shoulder"]["bottom"] >= 0
    assert first["tempoSeconds"] == {"eccentric": .5, "pause": 0, "concentric": .5, "total": 1}
    assert first["comparison"] == "not_comparable"
    assert last["serverWarnings"] == ["squat_shallow"] and last["comparison"] == "not_comparable"
    m = manifest()
    m["reps"][-1]["onDeviceWarnings"] = ["squat_shallow", "squat_knee_valgus"]
    last = supported_metrics(skeleton(), 30, m, confidence=np.full(120, .8))["reps"][-1]
    assert last["comparison"] == "not_comparable"
    assert last["unassessedDeviceWarnings"] == ["squat_knee_valgus", "squat_shallow"]
    json.dumps(report, allow_nan=False)


def test_timeline_and_fault_evidence_stay_inside_their_rep():
    report = supported_metrics(skeleton(), 30, manifest(), confidence=np.full(120, .8))
    assert report["timeline"][0]["title"] == "총평"
    assert report["timeline"][0]["rep"] is None
    assert len([x for x in report["timeline"] if "움직임 살펴보기" in x["title"]]) == 4
    assert [x["t"] for x in report["timeline"]] == sorted(x["t"] for x in report["timeline"])
    assert report["rules"]["placeholder"]
    for fault in report["faults"]:
        rep = report["reps"][fault["rep"] - 1]
        assert fault["value"] > fault["threshold"]
        assert fault["confidence"] == .8
        for evidence in fault["evidence"]:
            assert rep["startMs"] <= evidence["t"] * 1000 < rep["endMs"]
            assert evidence["frame"] == round(evidence["t"] * 30)
    low = supported_metrics(skeleton(), 30, manifest(), confidence=np.full(120, .2))
    assert low["faults"] == [] and low["reps"][-1]["comparison"] == "not_comparable"


def test_path_symmetry_trunk_stability_and_fatigue():
    joints = skeleton()
    baseline = supported_metrics(joints, 30, manifest())
    assert baseline["reps"][0]["handPath"]["length"] == 0
    assert baseline["reps"][0]["symmetryDeg"]["knee"]["max"] == 0
    assert baseline["reps"][-1]["fatigueDrift"]["romDropDeg"] == 30
    joints[:, 13, 0] += np.linspace(0, .3, 120)
    joints[:, [11, 14], 2] += np.sin(np.linspace(0, 8 * np.pi, 120))[:, None] * .3
    changed = supported_metrics(joints, 30, manifest())
    assert changed["reps"][0]["handPath"]["length"] > 0
    assert changed["reps"][0]["symmetryDeg"]["elbow"]["max"] > 0
    assert changed["reps"][0]["trunkStability"]["stdDeg"] > 8


@pytest.mark.parametrize("exercise, order", [("squat", "eccentric_pause_concentric"),
    ("benchpress", "eccentric_pause_concentric"), ("pushup", "eccentric_pause_concentric"),
    ("barbell-row", "concentric_pause_eccentric"), ("deadlift", "concentric_pause_eccentric")])
def test_exercise_tempo_order_and_duration(exercise, order):
    m = manifest()
    m["exerciseId"] = exercise
    rep = supported_metrics(skeleton(), 30, m)["reps"][0]
    assert rep["tempoOrder"] == order
    tempo = rep["tempoSeconds"]
    assert tempo["eccentric"] + tempo["pause"] + tempo["concentric"] == pytest.approx(tempo["total"], abs=.002)


def test_pause_is_measured_as_contiguous_turnaround():
    joints = skeleton()
    joints[10:20] = joints[15]
    rep = supported_metrics(joints, 30, manifest())["reps"][0]
    assert rep["tempoSeconds"]["pause"] >= .3


def test_world_metrics_ignore_translation_and_reject_degenerate_input():
    assert supported_metrics(skeleton() + [10, 3, -5], 30, manifest()) == supported_metrics(skeleton(), 30, manifest())
    for bad in (np.zeros((120, 17, 3)), np.full((120, 17, 3), np.nan)):
        with pytest.raises(Rejected, match="invalid_skeleton"):
            supported_metrics(bad, 30, manifest())
    with pytest.raises(Rejected, match="rep_out_of_video"):
        supported_metrics(skeleton()[:110], 30, manifest())


@pytest.mark.parametrize("change", [
    lambda m: m.update(timebase="frame_index"),
    lambda m: m["reps"][0].update(startMs=-1),
    lambda m: m["reps"][0].update(endMs=float("nan")),
    lambda m: m["reps"][0].update(endMs=60_001),
    lambda m: m["reps"][1].update(startMs=500),
    lambda m: m["reps"][0].update(side="both"),
    lambda m: m["reps"][0].update(onDeviceWarnings="warning"),
    lambda m: m.update(exerciseId="unknown"),
])
def test_invalid_rep_manifest(change):
    m = manifest()
    change(m)
    with pytest.raises(Rejected):
        deep.manifest(json.dumps(m).encode(), "set-1")


@pytest.fixture
def env():
    state, bucket, jobs = State(), Bucket(), []

    def spawn(job):
        jobs.append(job)
        return SimpleNamespace(object_id="call-1")

    app = service.create_app(bucket, state, lambda job: None, SECRET, deep_spawn=spawn)
    return TestClient(app), bucket, state, jobs


def headers(user="42"):
    return {"Authorization": f"Bearer {token(user)}", "Idempotency-Key": "set-1"}


def prepare(env):
    client, bucket, _, _ = env
    # 파일 바이트는 디코딩하지 않는 계약 테스트용 자리표시자다.
    files = {"video.mp4": b"synthetic-video-placeholder", "reps.json": json.dumps(manifest()).encode()}
    response = client.post("/v1/deep-analysis/uploads", headers=headers(), json={
        "schemaVersion": 1, "clientSessionId": "set-1", "files": [
            {"name": n, "sizeBytes": len(data), "contentType": deep.FILES[n][0]} for n, data in files.items()]})
    assert response.status_code == 200
    for target in response.json()["files"]:
        bucket.put_bytes(target["url"].removeprefix("https://storage.example/"),
                         files[target["name"]], deep.FILES[target["name"]][0])
    return response.json()["uploadId"]


def complete(client, upload, user="42"):
    return client.post(f"/v1/deep-analysis/uploads/{upload}/complete", headers=headers(user),
                       json={"clientSessionId": "set-1"})


def test_job_contract_worker_storage_and_fresh_urls(env):
    client, bucket, state, jobs = env
    upload = prepare(env)
    response = complete(client, upload)
    assert response.status_code == 202
    job_id = response.json()["jobId"]
    assert jobs[0]["type"] == "deep_analysis"
    assert complete(client, upload).json() == response.json() and len(jobs) == 1
    url = f"/v1/deep-analysis/jobs/{job_id}"
    assert client.get(url, headers=headers()).json() == {"status": "queued", "progressRate": 0}

    def fake_analyze(source, directory, m, progress, beta):
        assert beta is None  # 체형 스캔 없음 → GVHMR 자체 β
        progress(75)
        output = directory / "overlay.mp4"
        output.write_bytes(b"synthetic-overlay-placeholder")
        return supported_metrics(skeleton(), 30, m), output

    deep_worker.run(jobs[0], bucket, state, fake_analyze)
    result = client.get(url, headers=headers()).json()
    assert result["status"] == "done" and result["progressRate"] == 100
    assert len(result["result"]["report"]["reps"]) == 4
    assert result["result"]["report"]["bodyShape"] == {"source": "gvhmr_fallback"}
    saved = state.get(f"deep-job:{job_id}")
    assert json.loads(bucket.get(saved["reportKey"])) == result["result"]["report"]
    assert set(result["result"]["workerTiming"]["seconds"]) == {"validateInput", "downloadInput", "analyzeVideo", "uploadArtifacts", "total"}
    assert all(v >= 0 for v in result["result"]["workerTiming"]["seconds"].values())
    runtime = result["result"]["report"]["runtime"]
    assert runtime["modelLoadPolicy"] == "per_job" and len(runtime["instanceId"]) == 32
    assert runtime["firstJobInProcess"] == (runtime["jobOrdinal"] == 1)
    assert all(ttl == 3600 for _, ttl in bucket.gets)
    assert client.get(url, headers=headers()).json()["result"]["videoUrl"] != result["result"]["videoUrl"]
    assert client.get(url, headers=headers("7")).status_code == 404
    assert client.get(url).status_code == 401
    assert complete(client, upload, "7").status_code == 404
    assert client.get(f"/v1/calibrations/jobs/{job_id}", headers=headers()).status_code == 404


def test_job_carries_the_users_latest_calibrated_beta(env):
    client, bucket, state, jobs = env
    beta = [0.1 * i for i in range(10)]
    bucket.put_json("results/42/old/job-old.json", {"smplBeta": [0.0] * 10})
    bucket.put_json("results/42/s/job-new.json", {"smplBeta": beta})
    bucket.put_json("results/7/s/job-other.json", {"smplBeta": [9.0] * 10})
    complete(client, prepare(env))
    assert jobs[0]["shape"] == {"calibrationJobId": "job-new", "smplBeta": beta}
    seen = []

    def fake_analyze(source, directory, m, progress, beta):
        seen.append(beta)
        output = directory / "overlay.mp4"
        output.write_bytes(b"synthetic-overlay-placeholder")
        return supported_metrics(skeleton(), 30, m), output

    deep_worker.run(jobs[0], bucket, state, fake_analyze)
    assert seen == [beta]
    report = state.get(f"deep-job:{jobs[0]['jobId']}")["report"]
    assert report["bodyShape"] == {"source": "calibration", "calibrationJobId": "job-new"}


def test_concurrent_completion_is_idempotent(env):
    client, _, _, jobs = env
    upload = prepare(env)
    with ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(lambda _: complete(client, upload).json(), range(6)))
    assert len({r["jobId"] for r in results}) == 1 and len(jobs) == 1


def test_size_validation_and_timeout(env):
    client, bucket, state, jobs = env
    upload = prepare(env)
    key = state.get(f"deep-upload:{upload}")["prefix"] + "video.mp4"
    original = bucket.objects.pop(key)
    assert complete(client, upload).json()["error"] == "file_missing"
    bucket.objects[key] = (b"bad", original[1])
    assert complete(client, upload).json()["error"] == "invalid_file_size"
    assert not jobs
    bucket.objects[key] = original
    job_id = complete(client, upload).json()["jobId"]
    job = state.get(f"deep-job:{job_id}")
    state.put(f"deep-job:{job_id}", job | {"queuedAt": time.time() - 1801})
    assert client.get(f"/v1/deep-analysis/jobs/{job_id}", headers=headers()).json()["error"] == "timeout"


def test_worker_revalidates_inputs_and_records_failure(env):
    client, bucket, state, jobs = env
    complete(client, prepare(env))
    job = jobs[0]
    key = job["prefix"] + "reps.json"
    bucket.put_bytes(key, b"{}", "application/json")
    deep_worker.run(job, bucket, state, lambda *args: pytest.fail("GPU must not run"))
    assert state.get(f"deep-job:{job['jobId']}")["status"] == "failed"


def test_spawn_failure_releases_session_claim(env):
    _, bucket, state, _ = env
    def fail(job):
        raise RuntimeError("spawn failed")
    client = TestClient(service.create_app(bucket, state, fail, SECRET, deep_spawn=fail), raise_server_exceptions=False)
    upload = prepare((client, bucket, state, []))
    assert complete(client, upload).status_code == 500
    assert state.get("deep-session:42:set-1") is None


def test_retry_is_owned_bounded_and_idempotent(env):
    client, _, state, jobs = env
    job_id = complete(client, prepare(env)).json()["jobId"]
    url = f"/v1/deep-analysis/jobs/{job_id}/retry"
    assert client.post(url).status_code == 401
    assert client.post(url, headers=headers("7")).status_code == 404
    assert client.post(url, headers=headers()).status_code == 409
    state.put(f"deep-job:{job_id}", jobs[0] | {"status": "failed", "error": "timeout"})
    with ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(lambda _: client.post(url, headers=headers()).json(), range(6)))
    assert len({r["jobId"] for r in results}) == 1 and len(jobs) == 2
    retry_id = results[0]["jobId"]
    state.put(f"deep-job:{retry_id}", jobs[1] | {"status": "failed"})
    assert client.post(f"/v1/deep-analysis/jobs/{retry_id}/retry", headers=headers()).status_code == 409
    assert not client.get(f"/v1/deep-analysis/jobs/{retry_id}", headers=headers()).json()["retryable"]


def test_calibration_contract_still_works_with_deep_routes(env):
    client, bucket, _, jobs = env
    files = bundle("set-1")
    response = client.post("/v1/calibrations/uploads", headers=headers(), json={
        "schemaVersion": 1, "clientSessionId": "set-1", "files": [
            {"name": name, "sizeBytes": len(data), "contentType": service.FILES[name][0]}
            for name, data in files.items()]})
    assert response.status_code == 200
    for item in response.json()["files"]:
        bucket.put_bytes(item["url"].removeprefix("https://storage.example/"), files[item["name"]],
                         service.FILES[item["name"]][0])
    upload_id = response.json()["uploadId"]
    completed = client.post(f"/v1/calibrations/uploads/{upload_id}/complete", headers=headers(),
                            json={"clientSessionId": "set-1"})
    assert completed.status_code == 202
    job_id = completed.json()["jobId"]
    assert client.get(f"/v1/calibrations/jobs/{job_id}", headers=headers()).json()["status"] == "queued"
    assert client.get(f"/v1/deep-analysis/jobs/{job_id}", headers=headers()).status_code == 404
    complete(client, prepare(env))
    assert len(jobs) == 1


def test_catalog_precedence_and_schema_validation(tmp_path, monkeypatch):
    catalog = tmp_path / "fault_catalog.csv"
    monkeypatch.setattr(deep_metrics, "CATALOG_PATH", catalog)
    catalog.write_text("wrong,columns\na,b\n")
    with pytest.raises(Rejected, match="invalid_fault_catalog"):
        deep_metrics.load_rules()
    catalog.write_text(",".join(deep_metrics.RULE_COLUMNS) + "\n" +
                       "example,squat,romDropDeg,20,warning,확인해 봐,천천히 움직여 봐,\n")
    report = supported_metrics(skeleton(), 30, manifest(), confidence=np.full(120, .8))
    assert report["rules"] == {"source": "fault_catalog.csv", "placeholder": False}
    assert report["faults"][0]["key"] == "example"


@pytest.mark.parametrize("duration, width, height, codec, valid", [
    (60, 1280, 720, "h264", True), (30, 720, 1280, "h264", True),
    (61, 1280, 720, "h264", False), (30, 1920, 1080, "h264", False),
    (30, 720, 1280, "hevc", False),
])
def test_normalize_bounds_without_reading_video(monkeypatch, tmp_path, duration, width, height, codec, valid):
    calls = []

    def command(args):
        calls.append(args)
        return json.dumps({"streams": [{"codec_type": "video", "codec_name": codec,
            "duration": duration, "width": width, "height": height}], "format": {}}).encode()

    monkeypatch.setattr(deep_worker, "command", command)
    if valid:
        deep_worker.normalize(tmp_path / "unused.mp4", tmp_path / "unused-target.mp4")
        assert calls[-1][0] == "ffmpeg" and "-an" in calls[-1]
        assert any("setpts=PTS-STARTPTS,fps=30" in x for x in calls[-1])
    else:
        with pytest.raises(Rejected):
            deep_worker.normalize(tmp_path / "unused.mp4", tmp_path / "unused-target.mp4")
        assert len(calls) == 1


def test_missing_support_never_fabricates_rule_confidence():
    report = deep.metrics(skeleton(), 30, manifest())
    assert report["faults"] == []
    assert all(r["confidence"] == 0 and r["comparison"] == "not_comparable" for r in report["reps"])
    assert report["reps"][0]["validity"]["reasons"] == ["missing_detection_support", "joint_support_missing", "tracking_mask_missing"]
    assert "판정을 보류" in report["timeline"][1]["body"]
    assert report["reps"][-1]["fatigueDrift"]["comparable"] is False


def test_low_support_evidence_does_not_claim_agreement():
    support = np.full(120, .8)
    support[105] = .1  # fourth rep's minimum angle: high rep average must not rescue bad evidence
    report = supported_metrics(skeleton(), 30, manifest(), confidence=support)
    assert report["faults"] == []
    assert report["reps"][-1]["comparison"] == "not_comparable"


def test_team_catalog_is_explicitly_unassessed_not_reinterpreted(tmp_path, monkeypatch):
    import csv
    path = tmp_path / "fault_catalog.csv"
    row = dict.fromkeys(deep_metrics.TEAM_COLUMNS, "")
    row.update(exercise="barbell_row", fault_id="row_torso_swing", severity="효율",
               metric_definition="P95(theta)-P05(theta)", threshold_standard="P:R>15deg")
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=deep_metrics.TEAM_COLUMNS)
        writer.writeheader()
        writer.writerow(row)
    monkeypatch.setattr(deep_metrics, "CATALOG_PATH", path)
    report = supported_metrics(skeleton(), 30, manifest(), confidence=np.full(120, .8))
    assert report["faults"] == []
    assert report["unassessedCatalog"] == [{"key": "row_torso_swing", "exercise": "barbell_row",
                                            "reason": "metric_contract_not_implemented"}]
    assert all(r["comparison"] == "not_comparable" for r in report["reps"])


def test_catalog_depth_fade_uses_means_and_requires_six_supported_reps(tmp_path, monkeypatch):
    import csv
    path = tmp_path / "fault_catalog.csv"
    contract = deep_metrics.DEPTH_FADE_CONTRACTS["squat_depth_fade"]
    row = dict.fromkeys(deep_metrics.TEAM_COLUMNS, "")
    row.update(fault_id="squat_depth_fade", exercise=contract[0], metric_definition=contract[1],
               threshold_standard=contract[2])
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=deep_metrics.TEAM_COLUMNS)
        writer.writeheader()
        writer.writerow(row)
    monkeypatch.setattr(deep_metrics, "CATALOG_PATH", path)
    reps = [{"repIndex": i+1, "depthAngleDeg": v, "confidence": .8,
             "metricValidity": {"depthAngleDeg": {"assessment": "available"}}}
            for i, v in enumerate([80, 90, 100, 110, 120, 130])]
    measurement = deep_metrics.catalog_measurements(reps, "squat", path.name)[0]
    assert measurement["value"] == 30
    assert measurement["assessment"] == "withheld"  # conditions are not yet in app manifest
    assert deep_metrics.catalog_measurements(reps[:5], "squat", path.name)[0]["value"] is None
    reps[0]["confidence"] = .1
    assert deep_metrics.catalog_measurements(reps, "squat", path.name)[0]["value"] is None
    assert deep_metrics.catalog_measurements(reps, "pushup", path.name) == []


def test_low_support_baseline_does_not_create_later_drift_warning():
    support = np.full(120, .8)
    support[:90] = .1
    report = supported_metrics(skeleton(), 30, manifest(), confidence=support)
    assert report["faults"] == []
    assert report["reps"][-1]["comparison"] == "not_comparable"


def test_low_baseline_is_visible_in_drift_and_timeline():
    support = np.full(120, .8)
    support[:90] = .1
    report = supported_metrics(skeleton(), 30, manifest(), confidence=support)
    assert report["reps"][-1]["fatigueDrift"]["comparable"] is False
    assert "low_baseline_support" in report["reps"][-1]["validity"]["reasons"]
    assert "변화 판정은 보류" in report["timeline"][-1]["body"]


def test_one_occluded_wrist_only_withholds_dependent_metrics():
    m = manifest(); m["exerciseId"] = "barbell-row"
    joints = np.full((120, 17), .9); joints[:, 9] = 0
    report = supported_metrics(skeleton(), 30, m, joint_confidence=joints)
    validity = report["reps"][0]["metricValidity"]
    for key in ("elbow", "handPath", "symmetryMaxDeg", "romDeg", "tempoSeconds"):
        assert validity[key]["assessment"] == "withheld"
        assert "low_joint_support" in validity[key]["reasons"]
    for key in ("knee", "hip", "shoulder", "torso", "trunkStdDeg"):
        assert validity[key]["assessment"] == "available"


def test_occluded_high_extremum_withholds_rom_drift():
    joints = np.full((120, 17), .9)
    joints[90, 13] = 0  # high knee angle; the old evidence-only check looked only at frame 105
    report = supported_metrics(skeleton(), 30, manifest(), joint_confidence=joints)
    assert report["reps"][-1]["metricValidity"]["romDropDeg"]["assessment"] == "withheld"
    assert report["reps"][-1]["fatigueDrift"]["comparable"] is False
    assert report["faults"] == []


def test_scalar_only_and_missing_tracking_are_explicitly_unassessed():
    report = deep.metrics(skeleton(), 30, manifest(), confidence=np.full(120, .9), tracked_mask=np.ones(120, bool))
    assert report["faults"] == []
    assert report["reps"][-1]["metricValidity"]["romDeg"]["reasons"] == ["joint_support_missing"]
    report = supported_metrics(skeleton(), 30, manifest(), tracked_mask=None)
    assert report["faults"] == []
    assert report["reps"][-1]["metricValidity"]["romDeg"]["reasons"] == ["tracking_mask_missing"]
    mask = np.ones(120, bool); mask[105] = False
    report = supported_metrics(skeleton(), 30, manifest(), tracked_mask=mask)
    assert report["reps"][0]["metricValidity"]["romDeg"]["assessment"] == "available"
    assert report["reps"][-1]["metricValidity"]["romDeg"]["reasons"] == ["tracking_interpolated"]


def test_overlay_distinguishes_unsupported_joints_and_tracking():
    joints = np.full((1, 17), .9); joints[0, 9] = 0
    valid, label = deep_worker.overlay_support(joints, np.array([True]), 0)
    assert not valid[13] and valid[5]  # left wrist gray, left knee remains supported
    assert "회색" in label
    valid, label = deep_worker.overlay_support(joints, np.array([False]), 0)
    assert not valid.any() and "보간" in label
    valid, label = deep_worker.overlay_support(joints, None, 0)
    assert not valid.any() and "없음" in label


def test_legacy_tracking_cache_never_fabricates_mask():
    import importlib.util
    from pathlib import Path
    path = Path(__file__).resolve().parents[3] / "scripts/deep_analysis/gvhmr_runner.py"
    spec = importlib.util.spec_from_file_location("runner_support_test", path)
    runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
    legacy = tuple(range(11))
    assert runner.unpack_preprocessing_cache(legacy) == (*legacy, None)
    mask = np.array([True, False])
    assert runner.unpack_preprocessing_cache((*legacy, mask))[-1] is mask


@pytest.mark.parametrize("kwargs,code", [
    ({"joint_confidence": np.ones((120, 16))}, "invalid_joint_confidence"),
    ({"tracked_mask": np.ones(120)}, "invalid_tracking_mask"),
])
def test_invalid_joint_or_tracking_support_is_rejected(kwargs, code):
    with pytest.raises(Rejected, match=code):
        supported_metrics(skeleton(), 30, manifest(), **kwargs)


def test_worker_passes_joint_and_observed_tracking_support(tmp_path, monkeypatch):
    import sys
    directory = tmp_path / "gvhmr"; directory.mkdir()
    joints = skeleton()
    keypoints = np.ones((120, 17, 3)); keypoints[:, :, 2] = .9
    mask = np.ones(120, bool); mask[105] = False
    np.savez(directory / "result.npz", h36m17_world=joints, h36m17_cam=joints,
             vitpose_coco17=keypoints, K=np.eye(3), tracked_mask=mask)
    monkeypatch.setitem(sys.modules, "gvhmr_runner", SimpleNamespace(run=lambda *a, **kw:
        {"other_people": 0, "person_frames": 119, "frames": 120, "timing_s": {},
         "device_used_peak_mib": {"track": 1000, "network": 3000},
         "vram_peak_mib": {"track": 100, "network": 200}, "elapsed_s": 4.5}))
    monkeypatch.setattr(deep_worker, "normalize", lambda *args: None)
    captured = {}
    def fake_render(*args, **kwargs):
        captured.update(kwargs)
    monkeypatch.setattr(deep_worker, "render", fake_render)
    report, _ = deep_worker.analyze(tmp_path / "video.mp4", tmp_path, manifest(), lambda x: None)
    assert report["reps"][-1]["metricValidity"]["romDeg"]["reasons"] == ["tracking_interpolated"]
    assert np.array_equal(captured["tracked_mask"], mask)
    assert captured["joint_support"].shape == (120, 17)
    assert report["resourceUsage"]["deviceUsedPeakMiB"] == 3000
    assert report["resourceUsage"]["stageDeltaMiB"]["network"] == 200
    assert report["runnerElapsedSeconds"] == 4.5
    assert set(report["processingTimingSeconds"]) == {"normalizeVideo", "infer", "metrics", "render", "analyze"}


def test_fault_confidence_includes_required_joint_and_baseline_minimum():
    joints = np.full((120, 17), .9)
    joints[10, 13] = .36  # valid but weak baseline knee support
    report = supported_metrics(skeleton(), 30, manifest(), confidence=np.full(120, .9), joint_confidence=joints)
    fault = next(f for f in report["faults"] if f["metric"] == "depthDriftDeg")
    assert fault["confidence"] == .36


def test_vram_sampler_reports_absolute_without_changing_delta_contract():
    import importlib.util
    from pathlib import Path
    path = Path(__file__).resolve().parents[3] / "scripts/deep_analysis/gvhmr_runner.py"
    spec = importlib.util.spec_from_file_location("runner_telemetry_test", path)
    runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
    sample = runner.VramPeak.__new__(runner.VramPeak)
    sample.base, sample.peak = 100 * 2**20, 350 * 2**20
    sample.th = SimpleNamespace(join=lambda: None)
    assert sample.done() == 250
    assert sample.device_used_peak_mib == 350


def test_panel_withholds_only_unsupported_metrics():
    keys = ('knee', 'hip', 'elbow', 'shoulder', 'torso', 'romDeg', 'tempoSeconds')
    rep = {'repIndex': 1, 'side': 'left', 'primaryJoint': 'knee', 'romDeg': 90.,
           'tempoSeconds': {'total': 2.}, 'comparison': 'agree',
           'metricValidity': {key: {'assessment': 'available'} for key in keys}}
    angles = {'left': {key: np.array([45.]) for key in keys[:5]}}
    support = np.ones((1, 17))
    support[0, 9] = 0  # Wrist occlusion does not invalidate knee/trunk estimates.
    lines = deep_worker.panel_lines(rep, 0, angles, support, np.array([True]))
    assert '팔꿈치 판정 보류' in lines
    assert '무릎 45.0°' in lines and '몸통 45.0°' in lines
    assert '가동 범위 90.0°' in lines
    assert '평가 항목 비교 보류' in lines
    support[:] = 1
    rep['metricValidity']['romDeg']['assessment'] = 'withheld'
    assert '가동 범위 판정 보류' in deep_worker.panel_lines(rep, 0, angles, support, np.array([True]))
    for tracking in (None, np.array([False])):
        lines = deep_worker.panel_lines(rep, 0, angles, support, tracking)
        assert not any('°' in line for line in lines)
        assert '반복 시간 판정 보류' in lines
    rep.pop('metricValidity')
    assert '무릎 판정 보류' in deep_worker.panel_lines(rep, 0, angles, support, np.array([True]))


def test_assessment_evidence_binds_estimands_support_and_baseline_without_form_claim():
    m = manifest()
    m["reps"] = [{**r, "repIndex": r["repIndex"] + 10} for r in m["reps"]]
    report = supported_metrics(skeleton(), 30, m)
    evidence = report["assessmentEvidence"]
    assert evidence["schema"] == "bpt.deep-assessment-evidence.v1"
    assert evidence["exerciseId"] == report["exerciseId"]
    assert evidence["fps"] == report["fps"] and evidence["sourceTimeBasis"] == "video_ms"
    for row, rep in zip(evidence["reps"], report["reps"]):
        assert {k: row[k] for k in ("repIndex", "startMs", "endMs", "side")} == {k: rep[k] for k in ("repIndex", "startMs", "endMs", "side")}
        assert len(row["metrics"]) == 15
        for metric in row["metrics"]:
            assert metric["measurement"] == rep["metricValidity"][metric["key"]]
            assert metric["postureAssessment"] == {"assessment": "withheld", "reasons": ["validated_posture_target_missing"]}
            assert metric["referenceReps"] == ([11, 12, 13] if metric["key"] in ("depthDriftDeg", "romDropDeg", "tempoDriftRatio") else [])
        by_key = {x["key"]: x for x in row["metrics"]}
        assert by_key["handPath"]["coordinateType"] == "pelvis_relative_wrist_midpoint"
        assert by_key["torso"]["coordinateType"] == "unsigned_gravity_aligned_torso_inclination"
        assert "not knee-gap" in by_key["symmetryMaxDeg"]["definition"]
        assert "not torso range" in by_key["trunkStdDeg"]["definition"]
        assert row["nativeComparison"]["assessment"] == "withheld"
        assert row["nativeComparison"]["comparableKeys"] == []


def test_assessment_evidence_retains_partial_geometry_and_missing_support():
    joints = skeleton()
    joints[:30, 13] = joints[:30, 12]  # collapsed left elbow only
    report = supported_metrics(joints, 30, manifest())
    metric = {x["key"]: x for x in report["assessmentEvidence"]["reps"][0]["metrics"]}
    assert metric["elbow"]["measurement"]["assessment"] == "withheld"
    assert "invalid_geometry" in metric["elbow"]["measurement"]["reasons"]
    assert metric["romDeg"]["measurement"]["assessment"] == "available"
    report = deep.metrics(skeleton(), 30, manifest())
    assert all(x["measurement"]["assessment"] == "withheld" for x in report["assessmentEvidence"]["reps"][0]["metrics"])


def test_matching_warning_alias_does_not_establish_native_metric_equivalence():
    m = manifest()
    m["reps"][-1]["onDeviceWarnings"] = ["squat_shallow"]
    rep = supported_metrics(skeleton(), 30, m)["reps"][-1]
    assert rep["faults"] and rep["serverWarnings"] == ["squat_shallow"]
    assert rep["comparison"] == "not_comparable" and rep["evaluatedKeys"] == []
    assert rep["unassessedDeviceWarnings"] == ["squat_shallow"]
