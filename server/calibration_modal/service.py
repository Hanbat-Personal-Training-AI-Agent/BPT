"""The calibration upload API (docs/research/calibration_serverless_upload.md).

    POST /v1/calibrations/uploads                     issue presigned PUT URLs
    POST /v1/calibrations/uploads/{uploadId}/complete verify the files, accept once, queue fitting
    GET  /v1/calibrations/jobs/{jobId}                fitting status and result

`state` is a modal.Dict (or anything with get / put(skip_if_exists) / pop); entries:
    upload:{uploadId}             who may complete it, for which session, declared sizes
    session:{userId}:{sessionId}  {"jobId"}  - written once, atomically, by the first accepted complete
    job:{jobId}                   owner, inputs, status ("queued" | "running" | "done" | "failed"), result/error
"""
import uuid
from typing import Any

from fastapi import Body, FastAPI, Header
from fastapi.responses import JSONResponse

import checks
from checks import FILES, Rejected


def object_key(user_id, session, upload_id, name):
    return f"calibrations/{user_id}/{session}/{upload_id}/{name}"


def create_app(bucket, state, spawn, jwt_secret):
    """`spawn(job)` queues the fitting worker and returns its call id (fit_body.spawn in production)."""
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

    @app.exception_handler(Rejected)
    def rejected(_, error: Rejected):
        body = {"error": error.code} | ({"detail": error.detail} if error.detail else {})
        return JSONResponse(body, status_code=error.status)

    def accepted_job(user_id, session):
        record = state.get(f"session:{user_id}:{session}")
        return record and record["jobId"]

    @app.post("/v1/calibrations/uploads")
    def prepare(body: Any = Body(None), authorization: str = Header(None), idempotency_key: str = Header(None)):
        user_id = checks.user_id_from_token(authorization, jwt_secret)
        session = checks.session_id(idempotency_key, isinstance(body, dict) and body.get("clientSessionId"))
        if job_id := accepted_job(user_id, session):
            return {"status": "accepted", "jobId": job_id}
        sizes = checks.declared_files(body)
        upload_id = f"upload-{uuid.uuid4().hex}"
        state.put(f"upload:{upload_id}", {"userId": user_id, "sessionId": session, "sizes": sizes})
        return {
            "status": "upload_required",
            "uploadId": upload_id,
            "files": [
                {"name": name, "method": "PUT",
                 "url": bucket.presign_put(object_key(user_id, session, upload_id, name), FILES[name][0], size)}
                for name, size in sizes.items()
            ],
        }

    @app.post("/v1/calibrations/uploads/{upload_id}/complete", status_code=202)
    def complete(upload_id: str, body: Any = Body(None), authorization: str = Header(None),
                 idempotency_key: str = Header(None)):
        user_id = checks.user_id_from_token(authorization, jwt_secret)
        checks.identifier(upload_id, "invalid_upload_id")
        session = checks.session_id(idempotency_key, isinstance(body, dict) and body.get("clientSessionId"))
        upload = state.get(f"upload:{upload_id}")
        if not upload or upload["userId"] != user_id:  # someone else's upload looks like a missing one
            raise Rejected(404, "upload_not_found")
        if upload["sessionId"] != session:
            raise Rejected(400, "session_mismatch")
        if job_id := accepted_job(user_id, session):
            return {"status": "accepted", "jobId": job_id}

        verify_upload(bucket, user_id, session, upload_id, upload["sizes"])

        job_id = f"job-{uuid.uuid4().hex}"
        job = {"jobId": job_id, "userId": user_id, "sessionId": session, "uploadId": upload_id,
               "prefix": object_key(user_id, session, upload_id, ""), "status": "queued"}
        state.put(f"job:{job_id}", job)
        # The atomic step: only the first complete for this user and session gets to queue work.
        if not state.put(f"session:{user_id}:{session}", {"jobId": job_id}, skip_if_exists=True):
            state.pop(f"job:{job_id}", None)
            return {"status": "accepted", "jobId": accepted_job(user_id, session)}
        try:
            call_id = spawn(job)
        except Exception:
            # Release the claim so the app's retry can queue it; never report accepted without a job.
            state.pop(f"session:{user_id}:{session}", None)
            state.pop(f"job:{job_id}", None)
            raise
        state.put(f"job:{job_id}", job | {"callId": call_id})
        return {"status": "accepted", "jobId": job_id}

    @app.get("/v1/calibrations/jobs/{job_id}")
    def job_status(job_id: str, authorization: str = Header(None)):
        user_id = checks.user_id_from_token(authorization, jwt_secret)
        checks.identifier(job_id, "invalid_job_id")
        job = state.get(f"job:{job_id}")
        if not job or job["userId"] != user_id:
            raise Rejected(404, "job_not_found")
        return {key: job[key] for key in ("status", "result", "error") if key in job}

    return app


def verify_upload(bucket, user_id, session, upload_id, sizes):
    """Every file present with the declared size and type, decodable photos, a valid manifest."""
    for name, (content_type, limit) in FILES.items():
        meta = bucket.head(object_key(user_id, session, upload_id, name))
        if meta is None:
            raise Rejected(422, "file_missing", name)
        size, stored_type = meta
        if size != sizes[name] or size > limit:
            raise Rejected(422, "invalid_file_size", name)
        if stored_type != content_type:
            raise Rejected(422, "invalid_content_type", name)
    manifest = checks.manifest(bucket.get(object_key(user_id, session, upload_id, "manifest.json")), session)
    for view in checks.VIEWS:
        name = f"view_{view}.jpg"
        checks.jpeg(bucket.get(object_key(user_id, session, upload_id, name)), name)
    return manifest
