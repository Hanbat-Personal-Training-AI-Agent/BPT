"""Request, token, file and manifest checks shared by the API and the fitting worker.

Rules mirror docs/research/calibration_serverless_upload.md and the app uploader
(lib/features/onboarding/services/calibration_upload_service.dart). The server checks
everything again: the app's checks are a convenience, not a trust boundary.
"""
import base64
import io
import json
import math
import re

import jwt
from PIL import Image

ID_PATTERN = re.compile(r"[A-Za-z0-9_-]{1,128}")
VIEWS = ("front", "rightfront", "back", "leftfront")
MIB = 1024 * 1024
# name -> (content type, max bytes). Exactly these five files, nothing else.
FILES = {"manifest.json": ("application/json", MIB)} | {
    f"view_{view}.jpg": ("image/jpeg", 25 * MIB) for view in VIEWS
}


class Rejected(Exception):
    """A request the client must fix. `code` is the stable reason returned to the app."""

    def __init__(self, status, code, detail=None):
        super().__init__(code)
        self.status, self.code, self.detail = status, code, detail


def user_id_from_token(authorization, secret_b64):
    """Bearer token from the Spring backend (jjwt, HMAC key = base64-decoded jwt.secret, sub = userId)."""
    if not authorization or not authorization.startswith("Bearer "):
        raise Rejected(401, "unauthorized")
    try:
        claims = jwt.decode(
            authorization[len("Bearer "):],
            # Padding is often lost when the secret is copied into a shell; the key bytes are the same.
            base64.b64decode(secret_b64 + "=" * (-len(secret_b64) % 4)),
            algorithms=["HS256", "HS384", "HS512"],  # jjwt picks the HS size from the key length
            options={"require": ["sub", "exp"]},
        )
    except jwt.PyJWTError:
        raise Rejected(401, "unauthorized") from None
    user_id = claims["sub"]
    # The backend issues Long user IDs; anything else must not reach an object key.
    if not isinstance(user_id, str) or not user_id.isdigit() or len(user_id) > 19:
        raise Rejected(401, "unauthorized")
    return user_id


def identifier(value, code):
    if not isinstance(value, str) or not ID_PATTERN.fullmatch(value):
        raise Rejected(400, code)
    return value


def session_id(idempotency_key, body_session_id):
    session = identifier(idempotency_key, "invalid_idempotency_key")
    if body_session_id != session:
        raise Rejected(400, "session_mismatch")
    return session


def declared_files(body):
    """`files` of the prepare request -> {name: sizeBytes}."""
    if not isinstance(body, dict) or body.get("schemaVersion") != 1:
        raise Rejected(400, "unsupported_schema")
    files = body.get("files")
    if not isinstance(files, list) or len(files) != len(FILES):
        raise Rejected(400, "invalid_files")
    sizes = {}
    for item in files:
        if not isinstance(item, dict):
            raise Rejected(400, "invalid_files")
        name, size = item.get("name"), item.get("sizeBytes")
        if name not in FILES or name in sizes:
            raise Rejected(400, "invalid_files", name)
        content_type, limit = FILES[name]
        if item.get("contentType") != content_type:
            raise Rejected(400, "invalid_content_type", name)
        if type(size) is not int or not 0 < size <= limit:
            raise Rejected(400, "invalid_file_size", name)
        sizes[name] = size
    return sizes


def _reject_constant(name):
    raise ValueError(name)


def manifest(data, expected_session):
    """Parse and check manifest.json bytes. Returns the parsed manifest."""
    try:
        # NaN/Infinity are not JSON; Python's parser accepts them unless told otherwise.
        m = json.loads(data, parse_constant=_reject_constant)
    except (ValueError, UnicodeDecodeError):
        raise Rejected(422, "invalid_manifest", "json") from None

    def bad(field):
        return Rejected(422, "invalid_manifest", field)

    def positive(value):
        return type(value) in (int, float) and math.isfinite(value) and value > 0

    if not isinstance(m, dict) or m.get("schemaVersion") != 1:
        raise bad("schemaVersion")
    if m.get("keypointFormat") != "coco17_pixel_unmirrored":
        raise bad("keypointFormat")
    if m.get("sessionId") != expected_session:
        raise bad("sessionId")
    if m.get("isComplete") is False:  # older complete sessions have no field
        raise bad("isComplete")
    for field in ("imageWidth", "imageHeight", "userHeightCm"):
        if not positive(m.get(field)):
            raise bad(field)
    views = m.get("views")
    if not isinstance(views, list) or len(views) != len(VIEWS):
        raise bad("views")
    labels = set()
    for view in views:
        label = view.get("label") if isinstance(view, dict) else None
        if label not in VIEWS or label in labels or view.get("file") != f"view_{label}.jpg":
            raise bad("views")
        labels.add(label)
        points = view.get("keypoints")
        if not isinstance(points, list) or len(points) != 17 or not all(
            isinstance(p, list) and len(p) == 3
            and all(type(v) in (int, float) and math.isfinite(v) for v in p)
            for p in points
        ):
            raise bad(f"views.{label}.keypoints")
        # Per-view camera fields (perViewCameraMetadata) are optional; when present they must be usable.
        for field in ("imageWidth", "imageHeight"):
            if field in view and not positive(view[field]):
                raise bad(f"views.{label}.{field}")
        intrinsics = view.get("intrinsics", m.get("intrinsics"))
        if intrinsics is not None and not (
            isinstance(intrinsics, dict)
            and all(type(intrinsics.get(k)) in (int, float) and math.isfinite(intrinsics[k]) for k in ("cx", "cy"))
            and (all(positive(intrinsics.get(k)) for k in ("fx", "fy")) or unknown_focal(intrinsics))
        ):
            raise bad(f"views.{label}.intrinsics")
    return m


def unknown_focal(intrinsics):
    """The app's no-camera fallback (CalibrationSession.intrinsics): fx = fy = 0, "fov_estimate".

    The photos are still valid; the fitting worker must estimate the focal length itself.
    """
    return intrinsics.get("fx") == 0 and intrinsics.get("fy") == 0 and intrinsics.get("source") == "fov_estimate"


def jpeg(data, name):
    """Fully decode the photo; a truncated or non-JPEG file is rejected."""
    try:
        with Image.open(io.BytesIO(data)) as image:
            if image.format != "JPEG":
                raise Rejected(422, "invalid_jpeg", name)
            image.load()
            return image.size
    except Rejected:
        raise
    except Exception:  # Pillow raises many types for corrupt input
        raise Rejected(422, "invalid_jpeg", name) from None
