import hashlib
import json
import os
import uuid
from datetime import datetime, timezone
import boto3

s3 = boto3.client("s3")
sqs = boto3.client("sqs")

CURATED_BUCKET = os.environ["CURATED_BUCKET"]
SQS_QUEUE_URL = os.environ["SQS_QUEUE_URL"]
PII_SALT = os.environ.get("PII_SALT", "jpm-showcase-demo-salt")
REQUIRED_FIELDS = {"transaction_id", "amount_usd", "currency", "country", "timestamp", "account_number"}


def hash_pii(value: str) -> str:
    return hashlib.sha256(f"{PII_SALT}:{value}".encode("utf-8")).hexdigest()[:16]


def validate_and_mask(record: dict) -> dict:
    missing = REQUIRED_FIELDS - record.keys()
    if missing:
        raise ValueError(f"Schema violation. Missing fields: {sorted(missing)}")

    masked = dict(record)
    masked["account_token"] = hash_pii(str(masked.pop("account_number")))
    if "customer_ssn" in masked:
        masked["ssn_token"] = hash_pii(str(masked.pop("customer_ssn")))
    if "customer_name" in masked:
        masked.pop("customer_name")
        masked["customer_redacted"] = True

    masked["ingested_at_utc"] = datetime.now(timezone.utc).isoformat()
    return masked


def lambda_handler(event, context):
    bucket = event["detail"]["bucket"]["name"]
    key = event["detail"]["object"]["key"]

    obj = s3.get_object(Bucket=bucket, Key=key)
    raw_records = json.loads(obj["Body"].read().decode("utf-8"))
    if isinstance(raw_records, dict):
        raw_records = [raw_records]

    curated_records = []
    batch_id = str(uuid.uuid4())

    for rec in raw_records:
        clean_rec = validate_and_mask(rec)
        clean_rec["batch_id"] = batch_id
        clean_rec["source_s3_uri"] = f"s3://{bucket}/{key}"
        curated_records.append(clean_rec)

        sqs.send_message(
            QueueUrl=SQS_QUEUE_URL,
            MessageBody=json.dumps(clean_rec),
        )

    curated_key = f"curated/{datetime.now(timezone.utc).strftime('%Y/%m/%d')}/{batch_id}.json"
    s3.put_object(
        Bucket=CURATED_BUCKET,
        Key=curated_key,
        Body="\n".join(json.dumps(r) for r in curated_records).encode("utf-8"),
        ContentType="application/json",
    )

    return {"status": "ok", "batch_id": batch_id, "records_dispatched": len(curated_records)}
