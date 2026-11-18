variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "bedrock_model_id" {
  description = "Amazon Bedrock foundation model or inference profile ID"
  type        = string
  default     = "us.amazon.nova-2-lite-v1:0"
}
