variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "github_org" {
  description = "GitHub organization or username that owns the repository"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "claude_api_key_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret containing the Claude API key. Secret must have key 'claude_api_key'."
  type        = string
  sensitive   = true
}
