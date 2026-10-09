"""Replays the app's upload against a deployed server, then polls the job.

    python e2e.py --api https://<workspace>--bpt-calibration-api.modal.run/v1 \
        --storage-host <account>.r2.cloudflarestorage.com --session-dir <capture folder> [--wait 900]

The token comes from BPT_TOKEN (a backend login token); it is never printed. Requests match
lib/features/onboarding/services/calibration_upload_service.dart: same headers and bodies, storage
PUTs with only Content-Type and Content-Length, no redirects, and the app's storage URL rules.
Without --session-dir a synthetic bundle is sent (fine for stage 1, the stub accepts it).
Also checks: duplicate complete -> same job, bad token -> 401, missing file -> rejected.
"""
import argparse
import json
import os
import sys
import time
import uuid
from pathlib import Path
from urllib.parse import urlparse

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parent / "tests"))


def app_allows_storage(url, hosts):
    """CalibrationUploadConfig.allowsStorage: https, port 443, exact host, no user info or fragment."""
    u = urlparse(url)
    return (u.scheme == "https" and (u.port or 443) == 443 and not u.username and not u.fragment
            and (u.hostname or "").lower() in hosts)


def load_bundle(session_dir):
    if session_dir is None:
        from conftest import bundle  # synthetic photos and manifest
        session = f"e2e-{uuid.uuid4().hex[:12]}"
        return session, bundle(session)
    folder = Path(session_dir)
    manifest = json.loads((folder / "manifest.json").read_text())
    names = ["manifest.json"] + [f"view_{v}.jpg" for v in ("front", "rightfront", "back", "leftfront")]
    return manifest["sessionId"], {name: (folder / name).read_bytes() for name in names}


def content_type(name):
    return "application/json" if name.endswith(".json") else "image/jpeg"


def main():
    args = argparse.ArgumentParser()
    args.add_argument("--api", required=True)
    args.add_argument("--storage-host", required=True, action="append")
    args.add_argument("--session-dir")
    args.add_argument("--wait", type=int, default=120, help="seconds to poll the job")
    opts = args.parse_args()
    token = os.environ["BPT_TOKEN"]
    api = opts.api.rstrip("/")
    hosts = [h.lower() for h in opts.storage_host]
    session, files = load_bundle(opts.session_dir)
    auth = {"Authorization": f"Bearer {token}", "Idempotency-Key": session}
    client = httpx.Client(timeout=30, follow_redirects=False)

    def check(label, ok, extra=""):
        print(f"{'PASS' if ok else 'FAIL'}  {label} {extra}")
        if not ok:
            sys.exit(1)

    prepare_body = {"schemaVersion": 1, "clientSessionId": session,
                    "files": [{"name": n, "sizeBytes": len(b), "contentType": content_type(n)} for n, b in files.items()]}

    bad = client.post(f"{api}/calibrations/uploads", json=prepare_body,
                      headers={"Authorization": "Bearer invalid", "Idempotency-Key": session})
    check("bad token -> 401", bad.status_code == 401, bad.status_code)

    # A first upload missing one photo must not be accepted.
    partial = client.post(f"{api}/calibrations/uploads", json=prepare_body, headers=auth).json()
    for target in partial["files"]:
        if target["name"] != "view_back.jpg":
            data = files[target["name"]]
            client.put(target["url"], content=data, headers={"Content-Type": content_type(target["name"]),
                                                             "Content-Length": str(len(data))}).raise_for_status()
    missing = client.post(f"{api}/calibrations/uploads/{partial['uploadId']}/complete",
                          json={"clientSessionId": session}, headers=auth)
    check("missing file -> rejected", missing.status_code == 422, missing.text)

    started = time.time()
    prepared = client.post(f"{api}/calibrations/uploads", json=prepare_body, headers=auth)
    body = prepared.json()
    check("prepare", prepared.status_code in (200, 201) and body["status"] == "upload_required", prepared.status_code)
    check("five targets, all PUT", sorted(t["name"] for t in body["files"]) == sorted(files)
          and all(t["method"] == "PUT" for t in body["files"]))
    check("storage URLs pass the app's host rules", all(app_allows_storage(t["url"], hosts) for t in body["files"]),
          f"(host {urlparse(body['files'][0]['url']).hostname})")

    for target in body["files"]:
        data = files[target["name"]]
        put = client.put(target["url"], content=data,
                         headers={"Content-Type": content_type(target["name"]), "Content-Length": str(len(data))})
        check(f"PUT {target['name']}", 200 <= put.status_code < 300, put.status_code)
    wrong_type = client.put(body["files"][0]["url"], content=files[body["files"][0]["name"]],
                            headers={"Content-Type": "text/plain"})
    check("signed URL refuses another Content-Type", wrong_type.status_code == 403, wrong_type.status_code)

    complete_url = f"{api}/calibrations/uploads/{body['uploadId']}/complete"
    first = client.post(complete_url, json={"clientSessionId": session}, headers=auth)
    check("complete -> accepted", first.status_code in (200, 202) and first.json()["status"] == "accepted", first.text)
    second = client.post(complete_url, json={"clientSessionId": session}, headers=auth)
    check("duplicate complete -> same job", second.json() == first.json())
    again = client.post(f"{api}/calibrations/uploads", json=prepare_body, headers=auth)
    check("prepare after acceptance -> accepted", again.json() == first.json())
    print(f"      accepted in {time.time() - started:.1f}s, jobId {first.json()['jobId']}")

    job_url = f"{api}/calibrations/jobs/{first.json()['jobId']}"
    deadline = time.time() + opts.wait
    while True:
        job = client.get(job_url, headers={"Authorization": f"Bearer {token}"}).json()
        if job["status"] in ("done", "failed") or time.time() > deadline:
            break
        time.sleep(3)
    print(f"      job {job['status']} after {time.time() - started:.1f}s")
    print(json.dumps(job, indent=2, ensure_ascii=False)[:2000])
    check("job finished", job["status"] == "done")


if __name__ == "__main__":
    main()
