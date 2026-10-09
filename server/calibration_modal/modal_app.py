"""Modal wiring for the calibration server (app `bpt-calibration`).

    modal deploy modal_app.py      # from server/calibration_modal/

Secrets (never in code): `bpt-r2` (R2_ENDPOINT_URL, R2_BUCKET, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY),
`bpt-jwt` (JWT_SECRET = the backend's base64 jwt.secret).
"""
import os

import modal

app = modal.App("bpt-calibration")
state = modal.Dict.from_name("bpt-calibration-state", create_if_missing=True)
secrets = [modal.Secret.from_name("bpt-r2"), modal.Secret.from_name("bpt-jwt")]

image = (
    modal.Image.debian_slim(python_version="3.12")
    .pip_install("fastapi[standard]==0.143.0", "boto3==1.43.110", "pyjwt==2.15.1", "pillow==12.3.0")
    .add_local_python_source("checks", "service", "storage", "worker")
)


@app.function(image=image, secrets=secrets[:1], timeout=15 * 60, min_containers=0)
def fit_body(job):
    import storage
    import worker

    return worker.run(job, storage.Bucket.from_env(), state, worker.stub_fit)


@app.function(image=image, secrets=secrets)
@modal.concurrent(max_inputs=50)
@modal.asgi_app()
def api():
    import service
    import storage

    return service.create_app(
        bucket=storage.Bucket.from_env(),
        state=state,
        spawn=lambda job: fit_body.spawn(job).object_id,
        jwt_secret=os.environ["JWT_SECRET"],
    )
