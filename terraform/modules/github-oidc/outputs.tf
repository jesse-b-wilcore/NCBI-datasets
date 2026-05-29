output "role_arn" {
  description = "IAM role ARN for GitHub Actions to assume via OIDC"
  value       = aws_iam_role.github_actions.arn
}

output "role_name" {
  description = "IAM role name"
  value       = aws_iam_role.github_actions.name
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}
