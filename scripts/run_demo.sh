#!/usr/bin/env bash
set -euo pipefail

cd terraform
RAW_BUCKET=$(terraform output -raw raw_bucket)
AUDIT_BUCKET=$(terraform output -raw audit_bucket)
ATHENA_WG=$(terraform output -raw athena_workgroup)
cd ..

echo "1. Uploading synthetic transactions to s3://${RAW_BUCKET}/incoming/batch_01.json..."
aws s3 cp sample_data/transactions_batch.json "s3://${RAW_BUCKET}/incoming/batch_01.json"

echo "2. Waiting 12 seconds for EventBridge -> Lambda -> SQS -> Bedrock -> S3 Audit..."
sleep 12

echo "3. Checking audited agent decisions in S3:"
aws s3 ls "s3://${AUDIT_BUCKET}/decisions/" --recursive

echo "4. Running Athena SQL audit query..."
QUERY_ID=$(aws athena start-query-execution \
  --work-group "${ATHENA_WG}" \
  --query-execution-context Database=agentic_compliance_dev \
  --query-string "SELECT transaction_id, decision, risk_score, requires_human_review, guardrail_status, rationale FROM agent_decisions;" \
  --query 'QueryExecutionId' --output text)

sleep 5
aws athena get-query-results --query-execution-id "${QUERY_ID}" --output table
