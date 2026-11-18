resource "aws_glue_catalog_database" "compliance" {
  name = "agentic_compliance_${var.environment}"
}

resource "aws_glue_catalog_table" "agent_decisions" {
  name          = "agent_decisions"
  database_name = aws_glue_catalog_database.compliance.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"            = "json"
    "projection.enabled"        = "true"
    "projection.dt.type"        = "date"
    "projection.dt.format"      = "yyyy-MM-dd"
    "projection.dt.range"       = "2026-01-01,NOW"
    "storage.location.template" = "s3://${aws_s3_bucket.buckets["audit"].bucket}/decisions/dt=$${dt}/"
  }

  partition_keys {
    name = "dt"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.buckets["audit"].bucket}/decisions/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns { name = "transaction_id"; type = "string" }
    columns { name = "batch_id"; type = "string" }
    columns { name = "account_token"; type = "string" }
    columns { name = "amount_usd"; type = "double" }
    columns { name = "country"; type = "string" }
    columns { name = "model_id"; type = "string" }
    columns { name = "reviewed_at_utc"; type = "string" }
    columns { name = "decision"; type = "string" }
    columns { name = "risk_score"; type = "int" }
    columns { name = "confidence"; type = "double" }
    columns { name = "rationale"; type = "string" }
    columns { name = "requires_human_review"; type = "boolean" }
    columns { name = "guardrail_status"; type = "string" }
  }
}

resource "aws_athena_workgroup" "compliance" {
  name          = "agentic-compliance-${var.environment}"
  force_destroy = true
  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.buckets["athena-results"].bucket}/results/"
    }
  }
}
