import json
import os
from datetime import datetime, timezone
import boto3

s3 = boto3.client("s3")
bedrock = boto3.client("bedrock-runtime")

AUDIT_BUCKET = os.environ["AUDIT_BUCKET"]
BEDROCK_MODEL_ID = os.environ["BEDROCK_MODEL_ID"]
ALLOWED_DECISIONS = {"APPROVE", "FLAG_FOR_REVIEW", "BLOCK_AND_ESCALATE"}

SYSTEM_PROMPT = """You are a financial compliance triage agent.
Analyze the anonymized transaction JSON for potential AML/fraud patterns
(e.g., structuring just under $10,000, high-risk jurisdictions, unusual velocity).
Respond ONLY with valid JSON matching this exact schema:
{
  "decision": "APPROVE" | "FLAG_FOR_REVIEW" | "BLOCK_AND_ESCALATE",
  "risk_score": <integer 0-100>,
  "confidence": <float 0.0-1.0>,
  "rationale": "<concise 1-2 sentence explanation>"
}"""


def enforce_guardrails(raw_text: str) -> dict:
    try:
        cleaned = raw_text.strip().removeprefix("```json").removesuffix("```").strip()
        parsed = json.loads(cleaned)
        decision = parsed.get("decision")
        risk_score = int(parsed.get("risk_score", 100))
        confidence = float(parsed.get("confidence", 0.0))
        rationale = str(parsed.get("rationale", ""))[:500]

        if decision not in ALLOWED_DECISIONS or not (0 <= risk_score <= 100):
            raise ValueError("Invalid decision or risk_score bounds")

        requires_human = (
            decision != "APPROVE" or confidence < 0.80 or risk_score >= 60
        )
        return {
            "decision": decision,
            "risk_score": risk_score,
            "confidence": confidence,
            "rationale": rationale,
            "requires_human_review": requires_human,
            "guardrail_status": "PASSED",
        }
    except Exception as exc:
        return {
            "decision": "FLAG_FOR_REVIEW",
            "risk_score": 100,
            "confidence": 0.0,
            "rationale": f"Guardrail fallback triggered: {exc}",
            "requires_human_review": True,
            "guardrail_status": "FALLBACK_TRIGGERED",
        }


def evaluate_with_bedrock(tx: dict) -> dict:
    response = bedrock.converse(
        modelId=BEDROCK_MODEL_ID,
        system=[{"text": SYSTEM_PROMPT}],
        messages=[{"role": "user", "content": [{"text": json.dumps(tx)}]}],
        inferenceConfig={"temperature": 0.0, "maxTokens": 300},
    )
    output_text = response["output"]["message"]["content"][0]["text"]
    return enforce_guardrails(output_text)


def lambda_handler(event, context):
    now = datetime.now(timezone.utc)
    dt_partition = now.strftime("dt=%Y-%m-%d")

    for record in event["Records"]:
        tx = json.loads(record["body"])
        verdict = evaluate_with_bedrock(tx)

        audit_entry = {
            "transaction_id": tx["transaction_id"],
            "batch_id": tx["batch_id"],
            "account_token": tx["account_token"],
            "amount_usd": tx["amount_usd"],
            "country": tx["country"],
            "model_id": BEDROCK_MODEL_ID,
            "reviewed_at_utc": now.isoformat(),
            **verdict,
        }

        audit_key = f"decisions/{dt_partition}/{tx['transaction_id']}.json"
        s3.put_object(
            Bucket=AUDIT_BUCKET,
            Key=audit_key,
            Body=(json.dumps(audit_entry) + "\n").encode("utf-8"),
            ContentType="application/json",
        )

    return {"processed": len(event["Records"])}
