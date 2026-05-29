variable "github_org" {
  description = "GitHub organization or user that owns the repository"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 evidence bucket the role may write to"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB evidence table the role may write to"
  type        = string
}

variable "lambda_function_arn" {
  description = "ARN of the report-generator Lambda the role may invoke"
  type        = string
}
