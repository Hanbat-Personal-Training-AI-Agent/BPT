"""Replays the app's upload against a deployed server, then polls the job.

    python e2e.py --api https://<workspace>--bpt-calibration-api.modal.run/v1 \
        --storage-host <account>.r2.cloudflarestorage.com --session-dir <capture folder> [--wait 900]

The token comes from BPT_TOKEN (a backend login token); it is never printed. Requests match
lib/features/onboarding/services/calibration_upload_service.dart: same headers and bodies, storage
PUTs with only Content-Type and Content-Length, no redirects, and the app's storage URL rules.
Without --session-dir a synthetic bundle is sent: it checks the upload path only, the fit itself fails on it.
Also checks: duplicate complete -> same job, bad token -> 401, missing file -> rejected.
"""
import argparse
import json
import os
import re
import sys
import time
import uuid
from pathlib import Path
from urllib.parse import urlparse

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parent / "tests"))


def valid_https(url, hosts=None, base=False):
    """Reject ambiguous destinations before attaching credentials or sending bytes."""
    try:
        u = urlparse(url)
        return (isinstance(url, str) and not any(c.isspace() for c in url)
                and u.scheme == "https" and u.hostname is not None
                and u.port in (None, 443) and u.username is None and u.password is None
                and not u.fragment and (not base or not u.query)
                and (hosts is None or u.hostname.lower() in hosts))
    except (ValueError, TypeError):
        return False


def app_allows_storage(url, hosts):
    return valid_https(url, hosts)


def validate_targets(body, files, hosts):
    """Validate the entire response, so a later invalid target cannot follow a PUT."""
    targets = body.get("files") if isinstance(body, dict) else None
    if (not isinstance(targets, list) or len(targets) != len(files)
            or not all(isinstance(t, dict) and isinstance(t.get("name"), str) for t in targets)
            or sorted(t.get("name", "") for t in targets) != sorted(files)
            or any(t.get("method") != "PUT" or not app_allows_storage(t.get("url"), hosts)
                   for t in targets)):
        raise ValueError("invalid upload targets")
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", str(body.get("uploadId", ""))):
        raise ValueError("invalid upload identifier")
    return targets


def job_log_summary(job):
    """Only bounded protocol values may enter logs; returned text stays private."""
    status = job.get("status")
    progress = job.get("progressRate")
    return {
        "status": status if status in ("queued", "running", "done", "failed") else "unknown",
        "progressRate": progress if type(progress) is int and 0 <= progress <= 100 else None,
        "resultPresent": isinstance(job.get("result"), dict),
    }


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
    api = opts.api.rstrip("/")
    hosts = [h.lower() for h in opts.storage_host]
    if not valid_https(api, base=True):
        args.error("--api must be an HTTPS base URL on port 443 without credentials, query or fragment")
    if any(not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?", h) for h in hosts):
        args.error("--storage-host requires exact host names")
    token = os.environ["BPT_TOKEN"]
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
    partial_targets = validate_targets(partial, files, hosts)
    for target in partial_targets:
        if target["name"] != "view_back.jpg":
            data = files[target["name"]]
            client.put(target["url"], content=data, headers={"Content-Type": content_type(target["name"]),
                                                             "Content-Length": str(len(data))}).raise_for_status()
    missing = client.post(f"{api}/calibrations/uploads/{partial['uploadId']}/complete",
                          json={"clientSessionId": session}, headers=auth)
    check("missing file -> rejected", missing.status_code == 422, missing.status_code)

    started = time.time()
    prepared = client.post(f"{api}/calibrations/uploads", json=prepare_body, headers=auth)
    body = prepared.json()
    check("prepare", prepared.status_code in (200, 201) and body["status"] == "upload_required", prepared.status_code)
    validate_targets(body, files, hosts)
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
    check("complete -> accepted", first.status_code in (200, 202) and first.json()["status"] == "accepted", first.status_code)
    second = client.post(complete_url, json={"clientSessionId": session}, headers=auth)
    check("duplicate complete -> same job", second.json() == first.json())
    again = client.post(f"{api}/calibrations/uploads", json=prepare_body, headers=auth)
    check("prepare after acceptance -> accepted", again.json() == first.json())
    print(f"      accepted in {time.time() - started:.1f}s")

    job_url = f"{api}/calibrations/jobs/{first.json()['jobId']}"
    deadline = time.time() + opts.wait
    rates = []
    while True:
        job = client.get(job_url, headers={"Authorization": f"Bearer {token}"}).json()
        summary = job_log_summary(job)
        rates.append((summary["status"], summary["progressRate"]))
        if job["status"] in ("done", "failed") or time.time() > deadline:
            break
        time.sleep(3)
    print(f"      job {summary['status']} after {time.time() - started:.1f}s, polls {sorted(set(rates), key=str)}")
    check("progressRate on every poll", all(isinstance(r, int) for _, r in rates))
    result = job.get("result") or {}
    glb_url = result.get("modelGlbUrl")
    print(json.dumps(summary, sort_keys=True))
    check("job finished", job["status"] == "done")
    check("real fit, not a stub", result.get("stub") is False and len(result.get("smplBeta") or []) == 10)
    check("backend fields", all(k in result for k in ("smplBeta", "boneLengthData", "coachComment", "calibratedAt")))
    if glb_url:
        check("GLB URL fits UserCalibration.modelGlbUrl (500)", len(glb_url) <= 500, len(glb_url))
        check("GLB URL passes the app's storage host rules", app_allows_storage(glb_url, hosts))
        glb = client.get(glb_url)
        check("GLB downloads", glb.status_code == 200 and glb.content[:4] == b"glTF", f"{len(glb.content)} bytes")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Transport exceptions may embed signed storage URLs. Keep them out of logs.
        print(f"FAIL operator request failed ({type(error).__name__})")
        sys.exit(1)
