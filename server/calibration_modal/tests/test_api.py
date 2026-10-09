"""Upload -> complete -> job flow against a real HTTP S3 endpoint (moto server).

Photos go up with the presigned URLs exactly like the app does: PUT, raw bytes,
Content-Type and Content-Length, no Authorization header.
"""
import threading

import httpx
import pytest
from fastapi.testclient import TestClient
from moto.server import ThreadedMotoServer

import service
import worker
from conftest import SECRET, bundle, jpeg_bytes, token
from storage import Bucket, BucketState


@pytest.fixture(scope="module")
def s3_endpoint():
    server = ThreadedMotoServer(port=0, verbose=False)
    server.start()
    host, port = server.get_host_and_port()
    yield f"http://{host}:{port}"
    server.stop()


@pytest.fixture
def bucket(s3_endpoint, request):
    b = Bucket(s3_endpoint, f"bpt-{request.node.name.lower().replace('_', '-')[:40]}", "test", "test",
               region="us-east-1")
    b.client.create_bucket(Bucket=b.bucket)
    return b


class Spawner:
    """Records queued jobs; `run()` executes them like the Modal worker would."""

    def __init__(self, bucket, state):
        self.jobs, self.bucket, self.state = [], bucket, state

    def __call__(self, job):
        self.jobs.append(job)

    def run(self, fit=worker.stub_fit):
        for job in self.jobs:
            worker.run(job, self.bucket, self.state, fit)


@pytest.fixture
def env(bucket):
    state = BucketState(bucket)
    spawner = Spawner(bucket, state)
    client = TestClient(service.create_app(bucket, state, spawner, SECRET))
    return client, bucket, state, spawner


def headers(session="session-1", user="42"):
    return {"Authorization": f"Bearer {token(sub=user)}", "Idempotency-Key": session}


def prepare(client, files, session="session-1", user="42"):
    body = {"schemaVersion": 1, "clientSessionId": session,
            "files": [{"name": n, "sizeBytes": len(b),
                       "contentType": "application/json" if n.endswith(".json") else "image/jpeg"}
                      for n, b in files.items()]}
    return client.post("/v1/calibrations/uploads", json=body, headers=headers(session, user))


def put_all(response, files, skip=()):
    for target in response.json()["files"]:
        if target["name"] in skip:
            continue
        data = files[target["name"]]
        content_type = "application/json" if target["name"].endswith(".json") else "image/jpeg"
        put = httpx.put(target["url"], content=data,
                        headers={"Content-Type": content_type, "Content-Length": str(len(data))})
        assert put.status_code == 200, put.text


def complete(client, upload_id, session="session-1", user="42"):
    return client.post(f"/v1/calibrations/uploads/{upload_id}/complete", json={"clientSessionId": session},
                       headers=headers(session, user))


def upload(client, files=None, session="session-1", user="42", skip=()):
    files = files or bundle(session)
    prepared = prepare(client, files, session, user)
    assert prepared.status_code == 200, prepared.text
    put_all(prepared, files, skip)
    return prepared.json()["uploadId"], complete(client, prepared.json()["uploadId"], session, user)


def test_end_to_end(env):
    client, bucket, state, spawner = env
    prepared = prepare(client, bundle())
    body = prepared.json()
    assert body["status"] == "upload_required"
    assert sorted(f["name"] for f in body["files"]) == sorted(bundle())
    assert all(f["method"] == "PUT" and f"/calibrations/42/session-1/{body['uploadId']}/" in f["url"]
               for f in body["files"])

    put_all(prepared, bundle())
    done = complete(client, body["uploadId"])
    assert done.status_code == 202
    job_id = done.json()["jobId"]
    assert done.json() == {"status": "accepted", "jobId": job_id}

    job = client.get(f"/v1/calibrations/jobs/{job_id}", headers=headers())
    assert job.json() == {"status": "queued"}
    spawner.run()
    job = client.get(f"/v1/calibrations/jobs/{job_id}", headers=headers()).json()
    assert job["status"] == "done" and job["result"]["stub"] is True
    assert bucket.head(f"results/42/session-1/{job_id}.json")

    # The app retrying prepare after a lost response gets the acceptance back, no new upload.
    again = prepare(client, bundle())
    assert again.json() == {"status": "accepted", "jobId": job_id}


def test_duplicate_complete_queues_one_job(env):
    client, _, _, spawner = env
    upload_id, first = upload(client)
    second = complete(client, upload_id)
    assert first.json() == second.json()
    assert len(spawner.jobs) == 1


def test_concurrent_completes_queue_one_job(env):
    client, _, _, spawner = env
    files = bundle()
    prepared = prepare(client, files)
    put_all(prepared, files)
    upload_id = prepared.json()["uploadId"]
    results = []
    threads = [threading.Thread(target=lambda: results.append(complete(client, upload_id))) for _ in range(8)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert {r.status_code for r in results} == {202}
    assert len({r.json()["jobId"] for r in results}) == 1
    assert len(spawner.jobs) == 1


def test_second_upload_of_an_accepted_session_returns_the_same_job(env):
    client, _, _, spawner = env
    _, first = upload(client)
    files = bundle()
    stale = prepare(client, files).json()  # accepted already: no URLs
    assert stale == first.json()
    assert len(spawner.jobs) == 1


def test_bad_token_is_401(env):
    client, *_ = env
    bad = {"Authorization": "Bearer nope", "Idempotency-Key": "session-1"}
    assert client.post("/v1/calibrations/uploads", json={}, headers=bad).status_code == 401
    assert client.post("/v1/calibrations/uploads/upload-1/complete", json={}, headers=bad).status_code == 401
    assert client.get("/v1/calibrations/jobs/job-1", headers=bad).status_code == 401


def test_missing_file_is_rejected(env):
    client, _, state, spawner = env
    upload_id, response = upload(client, skip=("view_back.jpg",))
    assert response.status_code == 422
    assert response.json() == {"error": "file_missing", "detail": "view_back.jpg"}
    assert not spawner.jobs and "session:42:session-1" not in state


def test_broken_jpeg_is_rejected(env):
    client, _, _, spawner = env
    files = bundle()
    files["view_front.jpg"] = jpeg_bytes()[:300]
    _, response = upload(client, files)
    assert response.json() == {"error": "invalid_jpeg", "detail": "view_front.jpg"}
    assert not spawner.jobs


def test_invalid_manifest_is_rejected(env):
    client, _, _, spawner = env
    files = bundle()
    files["manifest.json"] = files["manifest.json"].replace(b'"isComplete": true', b'"isComplete": false')
    _, response = upload(client, files)
    assert response.status_code == 422 and response.json()["error"] == "invalid_manifest"
    assert not spawner.jobs


def test_a_size_other_than_declared_is_rejected(env):
    client, bucket, _, _ = env
    files = bundle()
    prepared = prepare(client, files)
    put_all(prepared, files)
    body = prepared.json()
    # Overwrite one photo out of band with different bytes (the signed URL would not allow it).
    key = f"calibrations/42/session-1/{body['uploadId']}/view_back.jpg"
    bucket.client.put_object(Bucket=bucket.bucket, Key=key, Body=jpeg_bytes(400, 300), ContentType="image/jpeg")
    response = complete(client, body["uploadId"])
    assert response.json()["error"] == "invalid_file_size"


def test_other_users_cannot_complete_or_read(env):
    client, *_ = env
    upload_id, response = upload(client)
    job_id = response.json()["jobId"]
    assert complete(client, upload_id, user="7").status_code == 404
    assert client.get(f"/v1/calibrations/jobs/{job_id}", headers=headers(user="7")).status_code == 404


def test_complete_with_another_session_is_rejected(env):
    client, *_ = env
    files = bundle()
    prepared = prepare(client, files)
    put_all(prepared, files)
    assert complete(client, prepared.json()["uploadId"], session="session-2").json()["error"] == "session_mismatch"


def test_spawn_failure_releases_the_claim(env):
    client, bucket, state, spawner = env
    files = bundle()
    prepared = prepare(client, files)
    put_all(prepared, files)
    upload_id = prepared.json()["uploadId"]

    def broken(job):
        raise RuntimeError("queue down")

    failing = TestClient(service.create_app(bucket, state, broken, SECRET), raise_server_exceptions=False)
    assert complete(failing, upload_id).status_code == 500
    assert "session:42:session-1" not in state
    assert complete(client, upload_id).status_code == 202  # the retry queues it
    assert len(spawner.jobs) == 1


def test_failed_fit_reports_its_code(env):
    client, _, _, spawner = env
    _, response = upload(client)

    def no_person(manifest, photos):
        raise worker.FitFailed("person_not_found")

    with pytest.raises(worker.FitFailed):
        spawner.run(no_person)
    job = client.get(f"/v1/calibrations/jobs/{response.json()['jobId']}", headers=headers()).json()
    assert job == {"status": "failed", "error": "person_not_found"}
