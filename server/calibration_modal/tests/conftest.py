import base64
import io
import json
import sys
import time
from pathlib import Path

import jwt
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

SECRET = base64.b64encode(b"k" * 64).decode()  # a jjwt-style base64 key, HS512-sized


def token(sub="42", secret=SECRET, exp_in=600, algorithm="HS512", **claims):
    payload = {"sub": sub, "exp": int(time.time()) + exp_in} | claims
    return jwt.encode(payload, base64.b64decode(secret), algorithm=algorithm)


def jpeg_bytes(width=60, height=80):
    out = io.BytesIO()
    Image.new("RGB", (width, height), (120, 90, 60)).save(out, "JPEG")
    return out.getvalue()


def manifest_dict(session="session-1"):
    """Shaped like CalibrationStore's manifest.json."""
    views = [
        {"label": label, "file": f"view_{label}.jpg", "nominalYawDeg": yaw,
         "keypoints": [[10.0 + i, 20.0 + i, 0.9] for i in range(17)],
         "imageWidth": 60, "imageHeight": 80,
         "intrinsics": {"fx": 70.0, "fy": 70.0, "cx": 30.0, "cy": 40.0, "source": "fov_estimate"}}
        for label, yaw in (("front", 0), ("rightfront", 60), ("back", 180), ("leftfront", -60))
    ]
    return {"schemaVersion": 1, "isComplete": True, "sessionId": session, "userHeightCm": 172.0,
            "imageWidth": 60, "imageHeight": 80, "keypointFormat": "coco17_pixel_unmirrored",
            "perViewCameraMetadata": True, "views": views}


def bundle(session="session-1"):
    files = {"manifest.json": json.dumps(manifest_dict(session)).encode()}
    for label in ("front", "rightfront", "back", "leftfront"):
        files[f"view_{label}.jpg"] = jpeg_bytes()
    return files
