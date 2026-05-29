output "bucket_name" {
  description = "Name of the S3 evidence bucket"
  value       = aws_s3_bucket.evidence.bucket
}

output "bucket_arn" {
  description = "ARN of the S3 evidence bucket"
  value       = aws_s3_bucket.evidence.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB evidence table"
  value       = aws_dynamodb_table.evidence.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB evidence table"
  value       = aws_dynamodb_table.evidence.arn
}
