"""The fitting job, independent of Modal so it runs in tests with a fake bucket and state."""
import math
import time

import body
import checks


class FitFailed(Exception):
    """A job failure with a reason code for the app (person_not_found, fit_diverged, ...)."""

    def __init__(self, code):
        super().__init__(code)
        self.code = code


def result_key(job):
    return f"results/{job['userId']}/{job['sessionId']}/{job['jobId']}.json"


def model_key(job):
    # Short on purpose: the presigned GET of this key must fit UserCalibration.modelGlbUrl (500 chars).
    return f"models/{job['jobId']}.glb"


def update(state, key, job, **fields):
    """Read-modify-write of the job record; returns the new record."""
    record = state.get(key, job) | fields
    state.put(key, record)
    return record


def run(job, bucket, state, fit):
    """Load the bundle, fit, store the result. `fit(manifest, photos, progress)` returns the result
    dict, optionally with "modelGlb" bytes (uploaded to model_key, never kept in the JSON).

    Failures mark the job failed with a code and re-raise, so they show in Modal logs too. Crashes
    that skip this handler (OOM, Modal timeout) are caught by service.watchdog.
    """
    key = f"job:{job['jobId']}"
    if state.get(key, job).get("status") == "failed":  # the watchdog gave up before we started
        return None
    update(state, key, job, status="running", progressRate=5)
    try:
        manifest = checks.manifest(bucket.get(job["prefix"] + "manifest.json"), job["sessionId"])
        photos = {}
        for view in checks.VIEWS:
            data = bucket.get(job["prefix"] + f"view_{view}.jpg")
            checks.jpeg(data, view)
            photos[view] = data
        result = fit(manifest, photos, lambda rate: update(state, key, job, progressRate=int(rate)))
        glb = result.pop("modelGlb", None)
        require_real(result)
        if glb:
            bucket.put_bytes(model_key(job), glb, "model/gltf-binary")
        result["coachComment"] = coach_comment(result)
        result["calibratedAt"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        bucket.put_json(result_key(job), result)
    except Exception as error:
        code = error.code if isinstance(error, (FitFailed, checks.Rejected)) else "internal_error"
        update(state, key, job, status="failed", error=code)
        raise
    if state.get(key, job).get("status") == "failed":  # the watchdog gave up on us meanwhile; stay failed
        return result
    update(state, key, job, status="done", progressRate=100, result=result, modelKey=model_key(job) if glb else None)
    return result


def require_real(result):
    """Only a real body fit may become `done`: no stub, a finite 10-value β and bone lengths."""
    beta = result.get("smplBeta")
    segments = (result.get("boneLengthData") or {}).get("segments") or {}
    if (result.get("stub") is not False or not isinstance(beta, list) or len(beta) != 10
            or not all(isinstance(b, (int, float)) and math.isfinite(b) for b in beta)
            or not segments or not all(isinstance(v, (int, float)) and 0 < v < 200 for v in segments.values())):
        raise FitFailed("internal_error")


# Thigh (hip-knee) / height of the SMPL neutral mean shape put onto any height (eval_fit.py heightOnly).
MEAN_THIGH_RATIO = 0.256


def coach_comment(result):
    """One rule-based line for UserCalibration.coachComment (<= 255 chars). Squat torso lean grows
    with thigh length relative to the body (추정, a coaching heuristic, not a measurement claim)."""
    s = result["boneLengthData"]["segments"]
    thigh = (s["right_hip-right_knee"] + s["left_hip-left_knee"]) / 2
    ratio = thigh / result["userHeightCm"] / MEAN_THIGH_RATIO
    if ratio > 1.02:
        return "허벅지가 키에 비해 긴 편이야. 스쿼트에서 상체가 조금 더 숙여지는 건 자연스러우니 등만 곧게 지켜 줘!"
    if ratio < 0.98:
        return "허벅지가 키에 비해 짧은 편이야. 스쿼트에서 상체를 비교적 세운 채로 앉기 좋은 체형이야!"
    return "체형 정보를 저장했어. 이제 네 몸에 맞춰 자세를 더 정확하게 봐 줄게!"


def build_result(manifest, *, beta, joints, mesh_height_m=None, reprojection_px=None, per_view=None):
    """The result JSON. smplBeta and boneLengthData are named after the backend's UserCalibration
    columns; everything the app should not rely on sits under debug.per_view.

    beta: fitted SMPL β (10). joints: (17, 3) H36M joints of the rest-pose mesh in metres.
    reprojection_px: {view: mean px}. per_view: {view: {body_pose, global_orient, transl}}.
    """
    views = [v["label"] for v in manifest["views"]]
    segments = body.bone_lengths_cm(joints)
    return {
        "schemaVersion": 1,
        "stub": False,
        "bodyModel": "smpl_neutral_v1.1.0",
        "userHeightCm": manifest["userHeightCm"],
        "smplBeta": [float(b) for b in beta],
        "boneLengthData": {
            "unit": "cm",
            "skeleton": "h36m17",
            "pose": "rest",
            "segments": segments,
            # The app synthesises spine/thorax/neck/head from COCO averages; these are not comparable.
            "appDefinitionDiffers": [name for name in segments if body.app_definition_differs(name)],
        },
        "jointsH36m": {
            "order": list(body.H36M_JOINTS), "unit": "m", "pose": "rest",
            "positions": [[round(float(c), 5) for c in j] for j in joints],
        },
        "quality": {
            "heightErrorCm": None if mesh_height_m is None
            else round(mesh_height_m * 100 - manifest["userHeightCm"], 2),
            "perView": {v: {"reprojectionErrorPx": (reprojection_px or {}).get(v)} for v in views},
        },
        "debug": {"per_view": {
            v["label"]: (per_view or {}).get(v["label"], {})
            | {"camera": v.get("intrinsics", manifest.get("intrinsics"))}
            for v in manifest["views"]
        }},
    }


