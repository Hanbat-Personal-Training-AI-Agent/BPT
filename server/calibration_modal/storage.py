"""The S3-compatible photo bucket (Cloudflare R2 or S3), through boto3 only."""
import json
import os

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

    def put_json(self, key, value):
        self.client.put_object(Bucket=self.bucket, Key=key, Body=json.dumps(value).encode(),
                               ContentType="application/json")
