"""The S3-compatible photo bucket (Cloudflare R2 or S3), through boto3 only."""
import json
import os
import time

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

URL_TTL_SECONDS = 15 * 60


class Bucket:
    def __init__(self, endpoint_url, bucket, access_key_id, secret_access_key, region="auto"):
        self.bucket = bucket
        self.client = boto3.client(
            "s3",
            endpoint_url=endpoint_url,
            region_name=region,
            aws_access_key_id=access_key_id,
            aws_secret_access_key=secret_access_key,
            # Path style keeps one fixed host for the app's CALIBRATION_STORAGE_HOSTS allow-list.
            config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
        )

    @classmethod
    def from_env(cls):
        """Values come from the `bpt-r2` Modal Secret."""
        return cls(
            os.environ["R2_ENDPOINT_URL"],
            os.environ["R2_BUCKET"],
            os.environ["R2_ACCESS_KEY_ID"],
            os.environ["R2_SECRET_ACCESS_KEY"],
            os.environ.get("R2_REGION", "auto"),
        )

    def presign_put(self, key, content_type, size):
        # Content-Type and Content-Length become signed headers: the PUT must send exactly these.
        return self.client.generate_presigned_url(
            "put_object",
            Params={"Bucket": self.bucket, "Key": key, "ContentType": content_type, "ContentLength": size},
            ExpiresIn=URL_TTL_SECONDS,
        )

    def head(self, key):
        """(size, content type) or None when the object is missing."""
        try:
            meta = self.client.head_object(Bucket=self.bucket, Key=key)
        except ClientError as error:
            if error.response["Error"]["Code"] in ("404", "NoSuchKey", "NotFound"):
                return None
            raise
        return meta["ContentLength"], meta.get("ContentType")

    def get(self, key):
        return self.client.get_object(Bucket=self.bucket, Key=key)["Body"].read()

    def put_json(self, key, value, if_absent=False):
        """Returns False when `if_absent` and the object already exists (conditional write)."""
        extra = {"IfNoneMatch": "*"} if if_absent else {}
        for attempt in range(10):
            try:
                self.client.put_object(Bucket=self.bucket, Key=key, Body=json.dumps(value).encode(),
                                       ContentType="application/json", **extra)
                return True
            except ClientError as error:
                code = error.response["Error"]["Code"]
                if if_absent and code in ("PreconditionFailed", "412"):
                    return False
                # Another conditional write to the same key is in flight; retry until one wins.
                if if_absent and code in ("ConditionalRequestConflict", "409") and attempt < 9:
                    time.sleep(0.05 * (attempt + 1))
                    continue
                raise


class BucketState:
    """The API's state as small JSON objects under `state/` in the photo bucket.

    Same interface as modal.Dict (get / put(skip_if_exists) / pop). skip_if_exists is the
    bucket's conditional write (If-None-Match: *), atomic on S3 and R2; objects do not expire.
    """

    def __init__(self, bucket):
        self.bucket = bucket

    @staticmethod
    def _key(key):
        return "state/" + key.replace(":", "/") + ".json"

    def get(self, key, default=None):
        try:
            return json.loads(self.bucket.get(self._key(key)))
        except ClientError as error:
            if error.response["Error"]["Code"] in ("NoSuchKey", "404"):
                return default
            raise

    def put(self, key, value, *, skip_if_exists=False):
        return self.bucket.put_json(self._key(key), value, if_absent=skip_if_exists)

    def pop(self, key, default=None):
        self.bucket.client.delete_object(Bucket=self.bucket.bucket, Key=self._key(key))
        return default

    def __contains__(self, key):
        return self.get(key) is not None
