# cATO Evidence Collection Prototype

A **continuous Authority to Operate (cATO)** prototype that automatically collects security evidence from CI/CD pipelines and generates draft NIST 800-53 control narratives using Claude AI. Built for federal customers evaluating automated compliance workflows.

When a commit is pushed to this repository, a GitHub Actions workflow runs Trivy vulnerability scans, generates a software bill of materials (SBOM), and collects dependency and build metadata. That evidence is stored in AWS S3 and indexed in DynamoDB. A Lambda function then reads the evidence and calls the Claude API to produce draft System Security Plan (SSP) narrative sections mapped to NIST 800-53 Rev 5 controls.

---

## Architecture

```
GitHub Push
    │
    ▼
GitHub Actions Workflow (.github/workflows/evidence-collection.yml)
    │
    ├── Trivy scan (vulnerabilities + SARIF → GitHub Security tab)
    ├── CycloneDX SBOM generation
    ├── Dependency inventory (Python / Node / Go)
    └── Build metadata collection
            │
            ▼
       AWS S3 (evidence artifacts)
       AWS DynamoDB (evidence index)
            │
            ▼
    Lambda: report-generator
            │
            ▼
       Claude API (claude-opus-4-7)
            │
            ▼
    S3: reports/<commit_sha>/control_narratives.md
    S3: reports/<commit_sha>/control_narratives.json
```

**AWS services used:** S3, DynamoDB, Lambda, IAM (OIDC), Secrets Manager, Security Hub, AWS Config  
**GitHub Actions authenticates to AWS via OIDC** — no long-lived access keys are stored anywhere.

---

## NIST 800-53 Controls Addressed

| Control | Title | Evidence Source |
|---------|-------|----------------|
| RA-5 | Vulnerability Monitoring and Scanning | Trivy scan |
| SI-2 | Flaw Remediation | Trivy scan |
| SI-3 | Malicious Code Protection | Trivy scan |
| CM-8 | System Component Inventory | SBOM, dependency list |
| SA-12 | Supply Chain Protection | SBOM, dependency list |
| SA-10 | Developer Configuration Management | Build log |
| SI-7 | Software, Firmware, and Information Integrity | Build log |
| CM-6 | Configuration Settings | Trivy scan |

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       └── evidence-collection.yml   # CI/CD evidence pipeline
└── terraform/
    ├── main.tf                        # Root module
    ├── variables.tf                   # Input variables
    ├── outputs.tf                     # Post-apply instructions
    └── modules/
        ├── github-oidc/               # OIDC provider + IAM role for GitHub Actions
        ├── evidence-storage/          # S3 bucket + DynamoDB table
        ├── security-hub/              # AWS Security Hub + AWS Config
        └── report-generator/          # Lambda function + IAM role
            └── lambda/
                ├── handler.py         # Claude API integration, report generation
                └── requirements.txt
```

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.6
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured with credentials for the target account
- An [Anthropic API key](https://console.anthropic.com/)
- AWS account in `us-east-1` (region is configurable via variable)

---

## Setup

### 1. Store the Claude API key in AWS Secrets Manager

Do this **before** running Terraform. The secret must exist so its ARN can be passed as a variable.

```bash
aws secretsmanager create-secret \
  --name cato/claude-api-key \
  --secret-string '{"claude_api_key":"sk-ant-YOUR_KEY_HERE"}' \
  --region us-east-1
```

Note the ARN in the output — you'll need it in the next step.

---

### 2. Deploy infrastructure with Terraform

```bash
cd terraform
terraform init
terraform apply \
  -var="github_org=YOUR_GITHUB_ORG_OR_USERNAME" \
  -var="github_repo=datasets" \
  -var="claude_api_key_secret_arn=arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:cato/claude-api-key-XXXXXX"
```

Optional variables (defaults shown):

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region for all resources |
| `environment` | `dev` | Environment tag applied to all resources |

After `terraform apply` completes, the output will print the values you need for the next step.

---

### 3. Add GitHub Actions secrets

In your GitHub repository, go to **Settings → Secrets and variables → Actions → New repository secret** and add the following four secrets using the values from `terraform output`:

| Secret name | Where to get the value |
|-------------|----------------------|
| `AWS_ROLE_TO_ASSUME` | `terraform output github_actions_role_arn` |
| `EVIDENCE_BUCKET` | `terraform output evidence_bucket_name` |
| `EVIDENCE_DYNAMO_TABLE` | `terraform output evidence_dynamodb_table` |
| `REPORT_LAMBDA_NAME` | `terraform output report_lambda_name` |

---

### 4. Push a commit

The workflow triggers automatically on any push or pull request. You can also trigger it manually from the **Actions** tab using **Run workflow**.

---

## Viewing Reports

After a workflow run completes, reports are available in S3:

```bash
# Download the markdown narrative
aws s3 cp \
  s3://$(terraform output -raw evidence_bucket_name)/reports/<COMMIT_SHA>/control_narratives.md \
  ./control_narratives.md

# Download the full JSON report
aws s3 cp \
  s3://$(terraform output -raw evidence_bucket_name)/reports/<COMMIT_SHA>/control_narratives.json \
  ./control_narratives.json
```

Vulnerability findings also appear in the **GitHub Security tab** (Security → Code scanning alerts) via SARIF upload.

---

## Invoking the Report Generator Manually

To regenerate a report for an existing evidence set:

```bash
aws lambda invoke \
  --function-name $(terraform output -raw report_lambda_name) \
  --payload '{"commit_sha":"YOUR_COMMIT_SHA"}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json
```

---

## Teardown

```bash
cd terraform
terraform destroy \
  -var="github_org=YOUR_GITHUB_ORG_OR_USERNAME" \
  -var="github_repo=datasets" \
  -var="claude_api_key_secret_arn=YOUR_SECRET_ARN"
```

Note: the S3 bucket has versioning enabled and will not be destroyed if it contains objects. Empty it first if needed:

```bash
aws s3 rm s3://BUCKET_NAME --recursive
```
