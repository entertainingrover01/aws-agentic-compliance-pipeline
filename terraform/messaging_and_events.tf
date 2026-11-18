resource "aws_sqs_queue" "agent_dlq" {
  name                      = "agentic-compliance-dlq-${var.environment}"
  kms_master_key_id         = aws_kms_key.pipeline.arn
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "agent_tasks" {
  name                       = "agentic-compliance-tasks-${var.environment}"
  kms_master_key_id          = aws_kms_key.pipeline.arn
  visibility_timeout_seconds = 90
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.agent_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_cloudwatch_event_rule" "s3_raw_created" {
  name        = "agentic-raw-s3-ingest-${var.environment}"
  description = "Triggers PII masking pipeline on raw transaction upload"
  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.buckets["raw"].id]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "trigger_ingest_lambda" {
  rule      = aws_cloudwatch_event_rule.s3_raw_created.name
  target_id = "IngestAndMaskLambda"
  arn       = aws_lambda_function.ingest_and_mask.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest_and_mask.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_raw_created.arn
}
