terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  # Uncomment and configure for remote state once the S3 backend bucket exists:
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "cato/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "cATO"
      Environment = var.environment
      GithubRepo  = "${var.github_org}/${var.github_repo}"
      ManagedBy   = "terraform"
    }
  }
}

# ── Evidence Storage (S3 + DynamoDB) ─────────────────────────────────────────

module "evidence_storage" {
  source = "./modules/evidence-storage"

  environment = var.environment
  github_org  = var.github_org
  github_repo = var.github_repo
}

# ── Report Generator Lambda ───────────────────────────────────────────────────

module "report_generator" {
  source = "./modules/report-generator"

  environment               = var.environment
  aws_region                = var.aws_region
  s3_bucket_name            = module.evidence_storage.bucket_name
  s3_bucket_arn             = module.evidence_storage.bucket_arn
  dynamodb_table_name       = module.evidence_storage.dynamodb_table_name
  dynamodb_table_arn        = module.evidence_storage.dynamodb_table_arn
  claude_api_key_secret_arn = var.claude_api_key_secret_arn
}

# ── GitHub OIDC Trust ─────────────────────────────────────────────────────────
# Depends on Lambda ARN so the role can also invoke it directly

module "github_oidc" {
  source = "./modules/github-oidc"

  github_org          = var.github_org
  github_repo         = var.github_repo
  environment         = var.environment
  s3_bucket_arn       = module.evidence_storage.bucket_arn
  dynamodb_table_arn  = module.evidence_storage.dynamodb_table_arn
  lambda_function_arn = module.report_generator.function_arn
}

# ── Security Hub + AWS Config ─────────────────────────────────────────────────

module "security_hub" {
  source = "./modules/security-hub"

  environment = var.environment
  aws_region  = var.aws_region
}
