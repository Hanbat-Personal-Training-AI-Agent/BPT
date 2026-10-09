"""The fitting job, independent of Modal so it runs in tests with a fake bucket and state."""
import body
import checks


class FitFailed(Exception):
    """A job failure with a reason code for the app (person_not_found, fit_diverged, ...)."""

    def __init__(self, code):
        super().__init__(code)
        self.code = code


def result_key(job):
    return f"results/{job['userId']}/{job['sessionId']}/{job['jobId']}.json"


def run(job, bucket, state, fit):
    """Load the bundle, fit, store the result. `fit(manifest, photos)` returns the result dict.

    Failures mark the job failed with a code and re-raise, so they show in Modal logs too.
    """
    key = f"job:{job['jobId']}"
    state.put(key, state.get(key, job) | {"status": "running"})
    try:
        manifest = checks.manifest(bucket.get(job["prefix"] + "manifest.json"), job["sessionId"])
        photos = {}
        for view in checks.VIEWS:
            data = bucket.get(job["prefix"] + f"view_{view}.jpg")
            checks.jpeg(data, view)
            photos[view] = data
        result = fit(manifest, photos)
        bucket.put_json(result_key(job), result)
    except Exception as error:
        code = error.code if isinstance(error, (FitFailed, checks.Rejected)) else "internal_error"
        state.put(key, state.get(key, job) | {"status": "failed", "error": code})
        raise
    state.put(key, state.get(key, job) | {"status": "done", "result": result})
    return result


def build_result(manifest, *, beta=None, joints=None, mesh_height_m=None, reprojection_px=None,
                 per_view=None, stub=False):
    """The result JSON. smplBeta and boneLengthData are named after the backend's UserCalibration
    columns; everything the app should not rely on sits under debug.per_view.

    beta: fitted SMPL β (10). joints: (17, 3) H36M joints of the rest-pose mesh in metres.
    reprojection_px: {view: mean px}. per_view: {view: {body_pose, global_orient, transl}}.
    """
    views = [v["label"] for v in manifest["views"]]
    segments = body.bone_lengths_cm(joints) if joints is not None else None
    return {
        "schemaVersion": 1,
        "stub": stub,
        "bodyModel": "smpl_neutral_v1.1.0",
        "userHeightCm": manifest["userHeightCm"],
        "smplBeta": None if beta is None else [float(b) for b in beta],
        "boneLengthData": None if segments is None else {
            "unit": "cm",
            "skeleton": "h36m17",
            "pose": "rest",
            "segments": segments,
            # The app synthesises spine/thorax/neck/head from COCO averages; these are not comparable.
            "appDefinitionDiffers": [name for name in segments if body.app_definition_differs(name)],
        },
        "jointsH36m": None if joints is None else {
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


def stub_fit(manifest, photos):
    """Stage 1: inputs are verified for real, there is no body fit yet."""
    return build_result(manifest, stub=True)
