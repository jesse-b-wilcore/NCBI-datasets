"""
cATO Report Generator Lambda

Reads evidence artifacts from S3, calls Claude API to generate
draft NIST 800-53 control narratives, and writes a markdown report
back to S3.
"""

import json
import os
import boto3
import anthropic
from datetime import datetime, timezone

s3 = boto3.client("s3")
secrets = boto3.client("secretsmanager")
dynamodb = boto3.resource("dynamodb")

S3_BUCKET = os.environ["S3_BUCKET"]
DYNAMO_TABLE = os.environ["DYNAMO_TABLE"]
SECRET_ARN = os.environ["CLAUDE_API_KEY_SECRET_ARN"]

# NIST 800-53 controls addressed by each evidence type
CONTROL_MAPPING = {
    "trivy_scan": [
        "RA-5",   # Vulnerability Scanning
        "SI-2",   # Flaw Remediation
        "SI-3",   # Malicious Code Protection
        "CM-6",   # Configuration Settings
        "CM-7",   # Least Functionality
        "SA-11",  # Developer Security Testing
    ],
    "sbom": [
        "CM-8",   # System Component Inventory
        "SA-12",  # Supply Chain Protection
        "SR-3",   # Supply Chain Controls and Processes
        "SR-11",  # Component Authenticity
    ],
    "build_log": [
        "CM-3",   # Configuration Change Control
        "CM-4",   # Security Impact Analysis
        "SA-10",  # Developer Configuration Management
        "SI-7",   # Software, Firmware, and Information Integrity
    ],
    "dependency_list": [
        "CM-8",   # System Component Inventory
        "SA-12",  # Supply Chain Protection
        "CM-6",   # Configuration Settings
    ],
}

SEVERITY_ORDER = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3, "UNKNOWN": 4}


def get_claude_api_key() -> str:
    response = secrets.get_secret_value(SecretId=SECRET_ARN)
    secret = json.loads(response["SecretString"])
    return secret["claude_api_key"]


def load_evidence(commit_sha: str) -> dict:
    """Fetch all evidence artifacts for a commit from S3."""
    evidence = {}
    prefix = f"evidence/{commit_sha}/"

    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=S3_BUCKET, Prefix=prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            evidence_type = key.split("/")[2].split(".")[0]  # e.g. "trivy_scan"
            body = s3.get_object(Bucket=S3_BUCKET, Key=key)["Body"].read()
            try:
                evidence[evidence_type] = json.loads(body)
            except json.JSONDecodeError:
                evidence[evidence_type] = body.decode("utf-8")

    return evidence


def summarize_trivy(trivy_data: dict) -> str:
    """Produce a compact human-readable summary of Trivy findings."""
    if not trivy_data or "Results" not in trivy_data:
        return "No Trivy scan results available."

    counts: dict[str, int] = {}
    critical_vulns: list[str] = []

    for result in trivy_data.get("Results", []):
        for vuln in result.get("Vulnerabilities", []):
            sev = vuln.get("Severity", "UNKNOWN")
            counts[sev] = counts.get(sev, 0) + 1
            if sev == "CRITICAL":
                vid = vuln.get("VulnerabilityID", "unknown")
                pkg = vuln.get("PkgName", "unknown")
                critical_vulns.append(f"{vid} in {pkg}")

    if not counts:
        return "Trivy scan completed — no vulnerabilities found."

    summary_lines = ["Vulnerability counts by severity:"]
    for sev in sorted(counts, key=lambda s: SEVERITY_ORDER.get(s, 99)):
        summary_lines.append(f"  - {sev}: {counts[sev]}")

    if critical_vulns:
        summary_lines.append("\nCritical vulnerabilities:")
        for v in critical_vulns[:10]:  # cap at 10 for prompt size
            summary_lines.append(f"  - {v}")
        if len(critical_vulns) > 10:
            summary_lines.append(f"  ... and {len(critical_vulns) - 10} more")

    return "\n".join(summary_lines)


def build_prompt(commit_sha: str, evidence: dict) -> str:
    trivy_summary = summarize_trivy(evidence.get("trivy_scan", {}))

    sbom_info = "Not collected."
    if "sbom" in evidence:
        sbom = evidence["sbom"]
        num_components = len(sbom.get("components", []))
        sbom_info = f"{num_components} components inventoried."

    dep_info = "Not collected."
    if "dependency_list" in evidence:
        deps = evidence["dependency_list"]
        if isinstance(deps, list):
            dep_info = f"{len(deps)} dependencies identified."
        elif isinstance(deps, str):
            dep_info = deps[:500]

    build_info = "Not collected."
    if "build_log" in evidence:
        log = evidence["build_log"]
        if isinstance(log, str):
            build_info = log[-1500:]  # last 1500 chars of build log
        elif isinstance(log, dict):
            build_info = json.dumps(log)[:1500]

    return f"""You are a cybersecurity compliance expert specializing in NIST 800-53 and FedRAMP documentation.

You have been given automated security evidence collected from a CI/CD pipeline for a software system.
Your task is to generate draft NIST 800-53 Rev 5 control narrative sections suitable for a System Security Plan (SSP).

## Evidence Summary

**Commit SHA:** {commit_sha}
**Collection Timestamp:** {datetime.now(timezone.utc).isoformat()}

### Trivy Container/Dependency Scan
{trivy_summary}

### Software Bill of Materials (SBOM)
{sbom_info}

### Dependency Inventory
{dep_info}

### Build Log Excerpt
{build_info}

## Instructions

Generate draft narrative text for each of the following NIST 800-53 Rev 5 controls. For each control:
1. State how the evidence demonstrates implementation of the control
2. Note any gaps or remediation items suggested by the evidence
3. Use formal SSP language (present tense, system-centric, passive/active mix)
4. Flag HIGH PRIORITY for any critical vulnerabilities requiring immediate remediation

Controls to address:
- RA-5: Vulnerability Monitoring and Scanning
- SI-2: Flaw Remediation
- SI-3: Malicious Code Protection
- CM-8: System Component Inventory
- SA-12: Supply Chain Protection
- SA-10: Developer Configuration Management
- SI-7: Software, Firmware, and Information Integrity
- CM-6: Configuration Settings

Format your response as a JSON object with this structure:
{{
  "generated_at": "<ISO timestamp>",
  "commit_sha": "{commit_sha}",
  "controls": {{
    "<control_id>": {{
      "title": "<control title>",
      "narrative": "<draft SSP narrative>",
      "gaps": ["<gap 1>", ...],
      "priority": "NORMAL" | "HIGH" | "CRITICAL"
    }}
  }},
  "executive_summary": "<2-3 sentence summary for leadership>",
  "remediation_items": [
    {{
      "id": "<vuln or finding id>",
      "description": "<what needs fixing>",
      "affected_controls": ["<control_id>", ...],
      "suggested_timeline": "<immediate|30-days|90-days>"
    }}
  ]
}}"""


def generate_report(commit_sha: str, evidence: dict, api_key: str) -> dict:
    client = anthropic.Anthropic(api_key=api_key)

    prompt = build_prompt(commit_sha, evidence)

    message = client.messages.create(
        model="claude-opus-4-7",
        max_tokens=4096,
        system=(
            "You are a FedRAMP/NIST 800-53 compliance expert. "
            "Always respond with valid JSON only — no markdown fences, no preamble."
        ),
        messages=[{"role": "user", "content": prompt}],
    )

    raw_text = message.content[0].text
    report = json.loads(raw_text)
    report["model"] = message.model
    report["usage"] = {
        "input_tokens": message.usage.input_tokens,
        "output_tokens": message.usage.output_tokens,
    }
    return report


def write_markdown(report: dict, commit_sha: str) -> str:
    """Convert the JSON report to a human-readable markdown narrative."""
    lines = [
        f"# cATO Security Control Narratives",
        f"",
        f"**Commit:** `{commit_sha}`  ",
        f"**Generated:** {report.get('generated_at', 'N/A')}  ",
        f"**Model:** {report.get('model', 'N/A')}",
        f"",
        f"---",
        f"",
        f"## Executive Summary",
        f"",
        report.get("executive_summary", ""),
        f"",
        f"---",
        f"",
        f"## Control Narratives",
        f"",
    ]

    controls = report.get("controls", {})
    for control_id, control in sorted(controls.items()):
        priority = control.get("priority", "NORMAL")
        priority_badge = "🔴 CRITICAL" if priority == "CRITICAL" else ("🟡 HIGH" if priority == "HIGH" else "🟢 NORMAL")
        lines += [
            f"### {control_id}: {control.get('title', '')} {priority_badge}",
            f"",
            control.get("narrative", ""),
            f"",
        ]
        gaps = control.get("gaps", [])
        if gaps:
            lines.append("**Identified Gaps:**")
            for gap in gaps:
                lines.append(f"- {gap}")
            lines.append("")

    remediation = report.get("remediation_items", [])
    if remediation:
        lines += [
            f"---",
            f"",
            f"## Remediation Items",
            f"",
        ]
        for item in remediation:
            timeline = item.get("suggested_timeline", "TBD")
            lines += [
                f"### {item.get('id', 'Unknown')} — _{timeline}_",
                f"",
                item.get("description", ""),
                f"",
                f"**Affected controls:** {', '.join(item.get('affected_controls', []))}",
                f"",
            ]

    return "\n".join(lines)


def lambda_handler(event, context):
    commit_sha = event.get("commit_sha")
    if not commit_sha:
        return {"statusCode": 400, "body": "Missing commit_sha in event payload"}

    print(f"Generating cATO report for commit {commit_sha}")

    api_key = get_claude_api_key()
    evidence = load_evidence(commit_sha)

    if not evidence:
        return {"statusCode": 404, "body": f"No evidence found for commit {commit_sha}"}

    report = generate_report(commit_sha, evidence, api_key)

    # Store JSON report
    json_key = f"reports/{commit_sha}/control_narratives.json"
    s3.put_object(
        Bucket=S3_BUCKET,
        Key=json_key,
        Body=json.dumps(report, indent=2).encode("utf-8"),
        ContentType="application/json",
        ServerSideEncryption="AES256",
    )

    # Store Markdown report
    markdown_key = f"reports/{commit_sha}/control_narratives.md"
    s3.put_object(
        Bucket=S3_BUCKET,
        Key=markdown_key,
        Body=write_markdown(report, commit_sha).encode("utf-8"),
        ContentType="text/markdown",
        ServerSideEncryption="AES256",
    )

    # Update DynamoDB index
    table = dynamodb.Table(DYNAMO_TABLE)
    table.put_item(Item={
        "commit_sha": commit_sha,
        "evidence_type": "report",
        "s3_json_key": json_key,
        "s3_markdown_key": markdown_key,
        "collected_at": datetime.now(timezone.utc).isoformat(),
        "controls_assessed": list(report.get("controls", {}).keys()),
        "model": report.get("model"),
        "token_usage": report.get("usage"),
    })

    print(f"Report written to s3://{S3_BUCKET}/{json_key}")
    return {
        "statusCode": 200,
        "commit_sha": commit_sha,
        "json_report": f"s3://{S3_BUCKET}/{json_key}",
        "markdown_report": f"s3://{S3_BUCKET}/{markdown_key}",
    }
