output "raw_bucket" { value = aws_s3_bucket.buckets["raw"].id }
output "curated_bucket" { value = aws_s3_bucket.buckets["curated"].id }
output "audit_bucket" { value = aws_s3_bucket.buckets["audit"].id }
output "sqs_queue_url" { value = aws_sqs_queue.agent_tasks.url }
output "athena_workgroup" { value = aws_athena_workgroup.compliance.name }
