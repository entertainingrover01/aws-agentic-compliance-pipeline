data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ingest_role" {
  name               = "agentic-ingest-mask-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "ingest_policy" {
  role = aws_iam_role.ingest_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.buckets["raw"].arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.buckets["curated"].arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.agent_tasks.arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.pipeline.arn
      }
    ]
  })
}

data "archive_file" "ingest_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/ingest_and_mask"
  output_path = "${path.module}/.build/ingest_and_mask.zip"
}

resource "aws_lambda_function" "ingest_and_mask" {
  function_name    = "agentic-ingest-and-mask-${var.environment}"
  role             = aws_iam_role.ingest_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.ingest_zip.output_path
  source_code_hash = data.archive_file.ingest_zip.output_base64sha256

  environment {
    variables = {
      CURATED_BUCKET = aws_s3_bucket.buckets["curated"].id
      SQS_QUEUE_URL  = aws_sqs_queue.agent_tasks.url
    }
  }
}

resource "aws_iam_role" "reviewer_role" {
  name               = "agentic-reviewer-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "reviewer_policy" {
  role = aws_iam_role.reviewer_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.agent_tasks.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.buckets["audit"].arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.pipeline.arn
      }
    ]
  })
}

data "archive_file" "reviewer_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/agentic_reviewer"
  output_path = "${path.module}/.build/agentic_reviewer.zip"
}

resource "aws_lambda_function" "agentic_reviewer" {
  function_name    = "agentic-compliance-reviewer-${var.environment}"
  role             = aws_iam_role.reviewer_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60
  filename         = data.archive_file.reviewer_zip.output_path
  source_code_hash = data.archive_file.reviewer_zip.output_base64sha256

  environment {
    variables = {
      AUDIT_BUCKET     = aws_s3_bucket.buckets["audit"].id
      BEDROCK_MODEL_ID = var.bedrock_model_id
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_to_agent" {
  event_source_arn = aws_sqs_queue.agent_tasks.arn
  function_name    = aws_lambda_function.agentic_reviewer.arn
  batch_size       = 5
}
