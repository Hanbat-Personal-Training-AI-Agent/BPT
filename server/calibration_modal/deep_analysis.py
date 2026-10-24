"""심층분석 업로드 계약과 H36M-17 반복 지표. GPU 없이 테스트할 수 있다."""
import json
import math
import time
import uuid
from typing import Any

from fastapi import Body, Header

import checks
from deep_metrics import frame_angles, metrics  # noqa: F401
from checks import Rejected

FILES = {"video.mp4": ("video/mp4", 32 * 1024 * 1024),
         "reps.json": ("application/json", 256 * 1024)}
EXERCISES = {"squat", "pushup", "barbell-row", "benchpress", "deadlift"}


def manifest(data, session):
    try:
        m = json.loads(data)
        assert isinstance(m, dict) and m.get("schemaVersion") == 1
        assert m.get("sessionId") == session and m.get("exerciseId") in EXERCISES
        assert m.get("timebase") == "video_ms"
        assert isinstance(m.get("reps"), list) and 1 <= len(m["reps"]) <= 100
        previous = 0
        for i, rep in enumerate(m["reps"]):
            assert isinstance(rep, dict) and rep.get("repIndex") == i + 1
            start, end = rep["startMs"], rep["endMs"]
            assert all(type(x) in (int, float) and math.isfinite(x) for x in (start, end))
            assert previous <= start < end <= 60_000
            assert rep.get("side") in ("left", "right")
            warnings = rep["onDeviceWarnings"]
            assert isinstance(warnings, list) and len(warnings) <= 30
            assert all(isinstance(w, str) and len(w) <= 80 for w in warnings)
            for field in ("onDeviceMetrics2D", "onDeviceMetrics3D"):
                values = rep.get(field, {})
                assert isinstance(values, dict) and len(values) <= 128
                assert all(isinstance(k, str) and len(k) <= 80 and type(v) in (int, float)
                           and math.isfinite(v) for k, v in values.items())
            previous = end
        return m
    except (ValueError, TypeError, KeyError, AssertionError):
        raise Rejected(422, "invalid_reps") from None


def verify_upload(bucket, prefix, sizes, session):
    for name, (content_type, limit) in FILES.items():
        meta = bucket.head(prefix + name)
        if meta is None:
            raise Rejected(422, "file_missing", name)
        if meta[0] != sizes[name] or not 0 < meta[0] <= limit:
            raise Rejected(422, "invalid_file_size", name)
        if meta[1] != content_type:
            raise Rejected(422, "invalid_content_type", name)
    return manifest(bucket.get(prefix + "reps.json"), session)


def calibrated_shape(bucket, user):
    """사용자의 가장 최근 체형 스캔 β(worker.result_key 위치). 없거나 읽지 못하면 None → GVHMR 자체 β."""
    try:
        key = bucket.latest(f"results/{user}/")
        beta = key and json.loads(bucket.get(key)).get("smplBeta")
    except Exception:  # 저장소 오류로 접수를 막지 않는다. 리포트에 대체 체형으로 표시된다.
        return None
    if (isinstance(beta, list) and len(beta) == 10
            and all(type(b) in (int, float) and math.isfinite(b) for b in beta)):
        return {"calibrationJobId": key.rsplit("/", 1)[-1].removesuffix(".json"), "smplBeta": beta}
    return None


def attach(app, bucket, state, spawn, jwt_secret, call_failure):
    """캘리브레이션과 상태 키를 분리하고 같은 인증·조건부 작업 접수 방식을 쓴다."""
    def accepted(user, session):
        return state.get(f"deep-session:{user}:{session}")

    @app.post("/v1/deep-analysis/uploads")
    def prepare(body: Any = Body(None), authorization: str = Header(None), idempotency_key: str = Header(None)):
        user = checks.user_id_from_token(authorization, jwt_secret)
        session = checks.session_id(idempotency_key, isinstance(body, dict) and body.get("clientSessionId"))
        if record := accepted(user, session):
            return {"status": "accepted", **record}
        if not isinstance(body, dict) or body.get("schemaVersion") != 1:
            raise Rejected(400, "unsupported_schema")
        files, sizes = body.get("files"), {}
        if not isinstance(files, list) or len(files) != len(FILES):
            raise Rejected(400, "invalid_files")
        for item in files:
            if not isinstance(item, dict) or not isinstance(item.get("name"), str):
                raise Rejected(400, "invalid_files")
            name, size = item["name"], item.get("sizeBytes")
            if name not in FILES or name in sizes:
                raise Rejected(400, "invalid_files")
            if item.get("contentType") != FILES[name][0]:
                raise Rejected(400, "invalid_content_type")
            if type(size) is not int or not 0 < size <= FILES[name][1]:
                raise Rejected(400, "invalid_file_size")
            sizes[name] = size
        upload = f"upload-{uuid.uuid4().hex}"
        prefix = f"deep-analysis/{user}/{session}/{upload}/"
        state.put(f"deep-upload:{upload}", {"userId": user, "sessionId": session, "sizes": sizes, "prefix": prefix})
        return {"status": "upload_required", "uploadId": upload, "files": [
            {"name": name, "method": "PUT", "url": bucket.presign_put(prefix + name, FILES[name][0], size)}
            for name, size in sizes.items()]}

    @app.post("/v1/deep-analysis/uploads/{upload_id}/complete", status_code=202)
    def complete(upload_id: str, body: Any = Body(None), authorization: str = Header(None),
                 idempotency_key: str = Header(None)):
        user = checks.user_id_from_token(authorization, jwt_secret)
        checks.identifier(upload_id, "invalid_upload_id")
        session = checks.session_id(idempotency_key, isinstance(body, dict) and body.get("clientSessionId"))
        upload = state.get(f"deep-upload:{upload_id}")
        if not upload or upload["userId"] != user:
            raise Rejected(404, "upload_not_found")
        if upload["sessionId"] != session:
            raise Rejected(400, "session_mismatch")
        if record := accepted(user, session):
            return {"status": "accepted", **record}
        reps = verify_upload(bucket, upload["prefix"], upload["sizes"], session)
        job_id = f"job-{uuid.uuid4().hex}"
        job = {**upload, "jobId": job_id, "type": "deep_analysis", "manifest": reps,
               "shape": calibrated_shape(bucket, user),
               "status": "queued", "progressRate": 0, "queuedAt": time.time()}
        state.put(f"deep-job:{job_id}", job)
        if not state.put(f"deep-session:{user}:{session}", {"jobId": job_id}, skip_if_exists=True):
            state.pop(f"deep-job:{job_id}", None)
            return {"status": "accepted", **accepted(user, session)}
        try:
            call = spawn(job)
        except Exception:
            state.pop(f"deep-session:{user}:{session}", None)
            state.pop(f"deep-job:{job_id}", None)
            raise
        if getattr(call, "object_id", None):
            state.put(f"deep-call:{job_id}", {"callId": call.object_id})
        return {"status": "accepted", "jobId": job_id}

    @app.get("/v1/deep-analysis/jobs/{job_id}")
    def status(job_id: str, authorization: str = Header(None)):
        user = checks.user_id_from_token(authorization, jwt_secret)
        checks.identifier(job_id, "invalid_job_id")
        job = state.get(f"deep-job:{job_id}")
        if not job or job["userId"] != user:
            raise Rejected(404, "job_not_found")
        if job["status"] in ("queued", "running"):
            call = state.get(f"deep-call:{job_id}")
            code = ("timeout" if time.time() - job["queuedAt"] > 30 * 60
                    else call_failure(call["callId"]) if call else None)
            if code:
                job = state.get(f"deep-job:{job_id}", job)
                if job["status"] in ("queued", "running"):
                    job = job | {"status": "failed", "error": code}
                    state.put(f"deep-job:{job_id}", job)
        result = {"status": job["status"], "progressRate": job.get("progressRate", 0)}
        if job["status"] == "done":
            result["result"] = {"report": job["report"],
                                "reportUrl": bucket.presign_get(job["reportKey"], ttl=3600),
                                "videoUrl": bucket.presign_get(job["videoKey"], ttl=3600)}
        if job["status"] == "failed":
            result["error"] = job.get("error", "internal_error")
            result["retryable"] = job.get("attempt", 0) < 1
        return result

    @app.post("/v1/deep-analysis/jobs/{job_id}/retry", status_code=202)
    def retry(job_id: str, authorization: str = Header(None)):
        user = checks.user_id_from_token(authorization, jwt_secret)
        checks.identifier(job_id, "invalid_job_id")
        job = state.get(f"deep-job:{job_id}")
        if not job or job["userId"] != user:
            raise Rejected(404, "job_not_found")
        claim = f"deep-retry:{job_id}"
        if record := state.get(claim):
            return {"status": "accepted", **record}
        if job["status"] != "failed" or job.get("attempt", 0) >= 1:
            raise Rejected(409, "retry_unavailable")
        next_id = f"job-{uuid.uuid4().hex}"
        next_job = {**job, "jobId": next_id, "attempt": 1, "status": "queued", "progressRate": 0,
                    "queuedAt": time.time()}
        next_job.pop("error", None)
        state.put(f"deep-job:{next_id}", next_job)
        if not state.put(claim, {"jobId": next_id}, skip_if_exists=True):
            state.pop(f"deep-job:{next_id}", None)
            return {"status": "accepted", **state.get(claim)}
        try:
            call = spawn(next_job)
        except Exception:
            state.pop(claim, None)
            state.pop(f"deep-job:{next_id}", None)
            raise
        if getattr(call, "object_id", None):
            state.put(f"deep-call:{next_id}", {"callId": call.object_id})
        return {"status": "accepted", "jobId": next_id}

