output "security_hub_arn" {
  description = "ARN of the Security Hub account subscription"
  value       = aws_securityhub_account.main.id
}

output "config_recorder_name" {
  description = "Name of the AWS Config recorder"
  value       = aws_config_configuration_recorder.main.name
}

output "config_bucket_name" {
  description = "Name of the S3 bucket used for Config delivery"
  value       = aws_s3_bucket.config.bucket
}
