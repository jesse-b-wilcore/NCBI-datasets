output "github_actions_role_arn" {
  description = "IAM role ARN to paste into your GitHub Actions workflow as AWS_ROLE_TO_ASSUME"
  value       = module.github_oidc.role_arn
}

output "evidence_bucket_name" {
  description = "S3 bucket where evidence artifacts are stored"
  value       = module.evidence_storage.bucket_name
}

output "evidence_dynamodb_table" {
  description = "DynamoDB table used as the evidence index"
  value       = module.evidence_storage.dynamodb_table_name
}

output "report_lambda_name" {
  description = "Name of the report generator Lambda function"
  value       = module.report_generator.function_name
}

output "report_lambda_arn" {
  description = "ARN of the report generator Lambda function"
  value       = module.report_generator.function_arn
}

output "next_steps" {
  description = "Setup instructions after terraform apply"
  value       = <<-EOT

    ╔══════════════════════════════════════════════════════════════════════════╗
    ║                    cATO Infrastructure — Setup Complete                  ║
    ╚══════════════════════════════════════════════════════════════════════════╝

    1. Add the following secret to your GitHub repository
       (Settings → Secrets → Actions → New repository secret):

       Name:  AWS_ROLE_TO_ASSUME
       Value: ${module.github_oidc.role_arn}

    2. The evidence collection workflow will trigger automatically on push.

    3. After a workflow run, find reports at:
       s3://${module.evidence_storage.bucket_name}/reports/<commit_sha>/control_narratives.md

    4. To invoke the report generator manually:
       aws lambda invoke \
         --function-name ${module.report_generator.function_name} \
         --payload '{"commit_sha":"<sha>"}' \
         --cli-binary-format raw-in-base64-out \
         response.json

  EOT
}
