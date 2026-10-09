"""The fitting job, independent of Modal so it runs in tests with a fake bucket and state."""
import checks

# Stage 1 stub: inputs are verified for real, the body result is a fixed placeholder.
STUB_RESULT = {"stub": True, "betas": [0.0] * 10, "joints_h36m": None, "bone_lengths_cm": None,
               "quality": None}


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


def stub_fit(manifest, photos):
    return STUB_RESULT | {"userHeightCm": manifest["userHeightCm"]}
