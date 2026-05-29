variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_region" {
  description = "AWS region for the Lambda function"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 evidence bucket"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 evidence bucket"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB evidence table"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB evidence table"
  type        = string
}

variable "claude_api_key_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the Claude API key"
  type        = string
}
