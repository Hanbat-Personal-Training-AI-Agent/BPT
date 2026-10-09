import json

import pytest

import checks
from checks import Rejected
from conftest import SECRET, bundle, jpeg_bytes, manifest_dict, token


def rejected(code, fn, *args):
    with pytest.raises(Rejected) as error:
        fn(*args)
    assert error.value.code == code, error.value.detail
    return error.value


# Tokens


def test_backend_token_gives_the_user_id():
    assert checks.user_id_from_token(f"Bearer {token()}", SECRET) == "42"
    assert checks.user_id_from_token(f"Bearer {token()}", SECRET.rstrip("=")) == "42"
    assert checks.user_id_from_token(f"Bearer {token(algorithm='HS256')}", SECRET) == "42"


@pytest.mark.parametrize("header", [
    None, "", "Basic abc", "Bearer ", "Bearer not-a-jwt",
    f"Bearer {token(secret='b3RoZXI=' * 8)}",  # signed with another key
    f"Bearer {token(exp_in=-10)}",             # expired
    f"Bearer {token(sub='../other')}",         # not a backend user id
])
def test_bad_tokens_are_401(header):
    assert rejected("unauthorized", checks.user_id_from_token, header, SECRET).status == 401


def test_unsigned_token_is_401():
    import jwt
    unsigned = jwt.encode({"sub": "42", "exp": 9999999999}, None, algorithm="none")
    rejected("unauthorized", checks.user_id_from_token, f"Bearer {unsigned}", SECRET)


# Identifiers and declared files


@pytest.mark.parametrize("value", ["", "a" * 129, "has space", "../x", "ä", None, 5])
def test_identifier_rules(value):
    rejected("bad", checks.identifier, value, "bad")


def test_identifier_accepts_the_contract_alphabet():
    assert checks.identifier("Ab_9-" * 25 + "abc", "bad")


def test_idempotency_key_must_match_the_body():
    assert checks.session_id("s-1", "s-1") == "s-1"
    rejected("session_mismatch", checks.session_id, "s-1", "s-2")


def declared(**overrides):
    files = [{"name": n, "sizeBytes": len(b), "contentType": "application/json" if n.endswith("json") else "image/jpeg"}
             for n, b in bundle().items()]
    return {"schemaVersion": 1, "clientSessionId": "session-1", "files": files} | overrides


def test_declared_files_accepts_the_app_request():
    assert set(checks.declared_files(declared())) == set(checks.FILES)


@pytest.mark.parametrize("mutate, code", [
    (lambda b: b["files"].pop(), "invalid_files"),
    (lambda b: b["files"].append(dict(b["files"][0])), "invalid_files"),
    (lambda b: b["files"][1].update(name="debug.csv"), "invalid_files"),
    (lambda b: b["files"][1].update(name="manifest.json"), "invalid_files"),
    (lambda b: b["files"][1].update(contentType="image/png"), "invalid_content_type"),
    (lambda b: b["files"][1].update(sizeBytes=25 * 1024 * 1024 + 1), "invalid_file_size"),
    (lambda b: b["files"][0].update(sizeBytes=1024 * 1024 + 1), "invalid_file_size"),
    (lambda b: b["files"][1].update(sizeBytes=0), "invalid_file_size"),
    (lambda b: b["files"][1].update(sizeBytes=1.5), "invalid_file_size"),
    (lambda b: b.update(schemaVersion=2), "unsupported_schema"),
])
def test_declared_files_rejects(mutate, code):
    body = declared()
    mutate(body)
    rejected(code, checks.declared_files, body)


# Manifest


def raw(m):
    return json.dumps(m).encode()


def test_manifest_accepts_the_native_shape():
    assert checks.manifest(raw(manifest_dict()), "session-1")["userHeightCm"] == 172.0


def test_manifest_without_newer_fields_is_still_accepted():
    m = manifest_dict()
    del m["isComplete"], m["perViewCameraMetadata"]
    for view in m["views"]:
        del view["imageWidth"], view["imageHeight"], view["intrinsics"]
    checks.manifest(raw(m), "session-1")


@pytest.mark.parametrize("mutate", [
    lambda m: m.update(schemaVersion=2),
    lambda m: m.update(keypointFormat="coco17_normalized"),
    lambda m: m.update(sessionId="other"),
    lambda m: m.update(isComplete=False),
    lambda m: m.update(userHeightCm=0),
    lambda m: m.update(imageWidth=-1),
    lambda m: m["views"].pop(),
    lambda m: m["views"][1].update(label="front", file="view_front.jpg"),
    lambda m: m["views"][0].update(file="../view_front.jpg"),
    lambda m: m["views"][0]["keypoints"].pop(),
    lambda m: m["views"][0]["keypoints"][3].append(1.0),
    lambda m: m["views"][0]["keypoints"][3].__setitem__(0, "1"),
    lambda m: m["views"][0].update(imageHeight=0),
    lambda m: m["views"][0]["intrinsics"].update(fx=0),
])
def test_manifest_rejects(mutate):
    m = manifest_dict()
    mutate(m)
    rejected("invalid_manifest", checks.manifest, raw(m), "session-1")


def test_manifest_rejects_nan_and_garbage():
    nan = raw(manifest_dict()).replace(b"20.0", b"NaN", 1)
    rejected("invalid_manifest", checks.manifest, nan, "session-1")
    rejected("invalid_manifest", checks.manifest, b"\xff\xfe", "session-1")
    rejected("invalid_manifest", checks.manifest, b"[]", "session-1")


# Photos


def test_jpeg_decodes():
    assert checks.jpeg(jpeg_bytes(60, 80), "view_front.jpg") == (60, 80)


def test_broken_or_non_jpeg_photos_are_rejected():
    import io
    from PIL import Image
    png = io.BytesIO()
    Image.new("RGB", (4, 4)).save(png, "PNG")
    for data in (b"", b"not a jpeg", jpeg_bytes()[:200], png.getvalue()):
        rejected("invalid_jpeg", checks.jpeg, data, "view_front.jpg")
