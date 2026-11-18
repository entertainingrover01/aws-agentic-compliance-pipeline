# Event-Driven Agentic Compliance Pipeline (AWS + Terraform)

A serverless, Infrastructure-as-Code (IaC) data engineering pipeline that safely feeds financial transaction data to an AI compliance agent—enforcing **deterministic PII masking**, **least-privilege IAM**, **post-LLM output guardrails**, and **queryable audit logs** in Amazon Athena.

## Architecture

~~~mermaid
flowchart LR
    A[Raw Transactions<br/>S3 Raw Bucket] -->|Object Created| B[Amazon EventBridge]
    B --> C[Lambda: Ingest & Mask<br/>Schema Validation + SHA-256 PII Redaction]
    C -->|Clean Records| D[S3 Curated Bucket<br/>KMS Encrypted]
    C -->|Async Task| E[Amazon SQS<br/>+ Dead Letter Queue]
    E --> F[Lambda: Agentic Reviewer<br/>Amazon Bedrock Converse API]
    F -->|Post-LLM Guardrail<br/>Schema + Confidence Check| G[S3 Audit Bucket<br/>Partitioned JSON]
    G --> H[AWS Glue Catalog +<br/>Amazon Athena]
~~~

## Why This Architecture Matters for Financial Services

AI agents should never query raw production databases or write unverified outputs directly to downstream systems. This pipeline separates **deterministic data engineering** from **probabilistic agent reasoning**:

1. **Zero-PII Agent Context:** Sensitive fields (`account_number`, `customer_ssn`, `customer_name`) are deterministically tokenized or stripped in Lambda *before* any payload reaches Amazon Bedrock.
2. **Post-LLM Deterministic Guardrails:** Every agent response is validated against a strict JSON schema. Any malformed output, low confidence score (< 0.80), or high risk score (>= 60) automatically triggers `requires_human_review = true`.
3. **Full Auditability & Lineage:** Every decision is written as partitioned newline-delimited JSON (`dt=YYYY-MM-DD`) with `batch_id`, `model_id`, and `guardrail_status` for immediate SQL auditing in Amazon Athena.
4. **Security by Default:** All S3 buckets enforce `BlockPublicAccess` and customer-managed KMS encryption (`aws:kms`), with separate least-privilege IAM roles per Lambda function.

## Project Structure

~~~text
├── terraform/                  # Modular Terraform IaC (AWS Provider ~> 6.0)
│   ├── providers.tf            # Provider config & default resource tags
│   ├── variables.tf            # Region, environment, and Bedrock model ID
│   ├── storage_and_kms.tf      # KMS CMK + 4 encrypted S3 buckets
│   ├── messaging_and_events.tf # EventBridge rule + SQS queue & DLQ
│   ├── compute_and_iam.tf      # 2 Python 3.12 Lambdas + least-privilege IAM
│   ├── analytics.tf            # Glue Data Catalog table + Athena workgroup
│   └── outputs.tf              # Bucket names, SQS URL, Athena workgroup
├── src/
│   ├── ingest_and_mask/        # Deterministic validation & PII tokenization
│   └── agentic_reviewer/       # Bedrock Converse API + guardrail enforcement
├── sample_data/                # Synthetic financial transactions (incl. structuring pattern)
└── scripts/                    # Automated end-to-end demo & Athena query script
~~~

## Quickstart

### Prerequisites
* AWS CLI configured (`aws sts get-caller-identity`)
* Terraform `>= 1.6.0`
* Amazon Bedrock model access enabled in `us-east-1` (default: `us.amazon.nova-2-lite-v1:0`)

### 1. Deploy Infrastructure
~~~bash
cd terraform
terraform init
terraform apply -auto-approve
~~~

### 2. Run End-to-End Pipeline Test
~~~bash
cd ..
chmod +x scripts/run_demo.sh
./scripts/run_demo.sh
~~~

### 3. Teardown (Zero Ongoing Cost)
~~~bash
cd terraform
terraform destroy -auto-approve
~~~
