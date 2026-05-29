locals {
  function_name = "cato-report-generator-${var.environment}"
  lambda_zip    = "${path.module}/lambda_package.zip"
}

# Build the Lambda deployment package from the local source
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = local.lambda_zip
}

# ── IAM Role for Lambda ───────────────────────────────────────────────────────

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "cato-report-generator-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    sid    = "EvidenceS3Access"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      var.s3_bucket_arn,
      "${var.s3_bucket_arn}/*",
    ]
  }

  statement {
    sid    = "EvidenceDynamoAccess"
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
    sid    = "ReadClaudeApiKey"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [var.claude_api_key_secret_arn]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "cato-report-generator-policy-${var.environment}"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

# ── Lambda Function ───────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 90

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_lambda_function" "report_generator" {
  function_name    = local.function_name
  filename         = local.lambda_zip
  source_code_hash = data.archive_file.lambda.output_base64sha256
  role             = aws_iam_role.lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 300  # Claude API can be slow on large evidence sets
  memory_size      = 512

  environment {
    variables = {
      S3_BUCKET              = var.s3_bucket_name
      DYNAMO_TABLE           = var.dynamodb_table_name
      CLAUDE_API_KEY_SECRET_ARN = var.claude_api_key_secret_arn
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.lambda_basic,
  ]

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "cATO NIST 800-53 narrative generation"
  }
}
