output "function_arn" {
  description = "ARN of the report generator Lambda function"
  value       = aws_lambda_function.report_generator.arn
}

output "function_name" {
  description = "Name of the report generator Lambda function"
  value       = aws_lambda_function.report_generator.function_name
}

output "role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda.arn
}
