data "aws_caller_identity" "current" {}

# GitHub's OIDC provider thumbprint (stable — rotates rarely)
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # SHA-1 thumbprint of the GitHub Actions OIDC leaf cert
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict to the specific repo; allow any branch/PR ref
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "cato-github-actions-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "cATO evidence collection via GitHub Actions OIDC"
  }
}

# Permissions the workflow needs: write evidence to S3/DynamoDB, invoke Lambda
data "aws_iam_policy_document" "github_actions_permissions" {
  statement {
    sid    = "EvidenceS3Write"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      var.s3_bucket_arn,
      "${var.s3_bucket_arn}/*",
    ]
  }

  statement {
    sid    = "EvidenceDynamoWrite"
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
    ]
    resources = [var.dynamodb_table_arn]
  }

  statement {
    sid    = "InvokeReportLambda"
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction",
    ]
    resources = [var.lambda_function_arn]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "cato-github-actions-policy-${var.environment}"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}
