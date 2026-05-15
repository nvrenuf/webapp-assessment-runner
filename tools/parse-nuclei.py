#!/usr/bin/env python3
"""Parse Nuclei JSONL output into normalized runner findings."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

SEVERITIES = {"critical", "high", "medium", "low", "informational"}
SENSITIVE_WORDS = {
    "secret",
    "token",
    "apikey",
    "api-key",
    "api key",
    "password",
    "passwd",
    "credential",
    "private key",
    "backup",
    "dump",
    "config",
    "configuration",
    "env",
    ".env",
    "sensitive",
    "admin",
}


def normalize_severity(value: Any) -> str:
    severity = str(value or "informational").strip().lower()
    if severity in {"info", "unknown"}:
        return "informational"
    if severity not in SEVERITIES:
        return "informational"
    return severity


def as_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item) for item in value if str(item)]
    if isinstance(value, str):
        return [part.strip() for part in value.split(",") if part.strip()]
    return [str(value)]


def lower_blob(*parts: Any) -> str:
    tokens: list[str] = []
    for part in parts:
        if isinstance(part, (list, tuple, set)):
            tokens.extend(str(item) for item in part)
        elif isinstance(part, dict):
            tokens.append(json.dumps(part, sort_keys=True))
        elif part is not None:
            tokens.append(str(part))
    return " ".join(tokens).lower()


def category_for(record: dict[str, Any], tags: list[str], title: str) -> str:
    template_id = str(record.get("template-id") or record.get("templateID") or "")
    blob = lower_blob(template_id, title, tags, record.get("matcher-name"), record.get("type"))
    for category in ["cors", "csp", "headers", "tls", "ssl", "tech", "exposure"]:
        if category in tags or re.search(rf"(^|[-_/\s]){re.escape(category)}($|[-_/\s])", blob):
            return category
    if any(tag in tags for tag in ["misconfig", "config"]):
        return "misconfig"
    if any(word in blob for word in SENSITIVE_WORDS):
        return "exposure"
    return "misc"


def is_tls_supported_info(record: dict[str, Any], title: str, evidence: str) -> bool:
    template_id = str(record.get("template-id") or record.get("templateID") or "").lower()
    blob = lower_blob(template_id, title, evidence)
    return "tls-version" in blob and ("tls 1.2" in blob or "tls1.2" in blob or "tlsv1.2" in blob or "tls 1.3" in blob or "tls1.3" in blob or "tlsv1.3" in blob)


def is_sensitive_exposure(record: dict[str, Any], title: str, evidence: str, tags: list[str]) -> bool:
    blob = lower_blob(record.get("template-id"), title, evidence, tags)
    return any(word in blob for word in SENSITIVE_WORDS)


def classify(record: dict[str, Any]) -> tuple[str, str, str]:
    info = record.get("info") if isinstance(record.get("info"), dict) else {}
    title = str(info.get("name") or record.get("template-id") or "Nuclei finding")
    tags = [tag.lower() for tag in as_list(info.get("tags") or record.get("tags"))]
    evidence = evidence_for(record)
    category = category_for(record, tags, title)
    severity = normalize_severity(info.get("severity") or record.get("severity"))

    if is_tls_supported_info(record, title, evidence):
        severity = "informational"
        category = "tls"
    elif category == "tech" or "tech" in tags or "technology" in lower_blob(title, record.get("template-id")):
        severity = "informational"
        category = "tech"
    elif category == "exposure" and is_sensitive_exposure(record, title, evidence, tags):
        if severity in {"informational", "low"}:
            severity = "medium"
    elif category in {"headers", "csp", "cors"}:
        if severity == "critical":
            severity = "high"

    if severity == "informational":
        status = "informational"
    elif severity in {"critical", "high", "medium"}:
        status = "needs_review"
    else:
        status = "observed"

    return severity, status, category


def matched_url(record: dict[str, Any]) -> str:
    for key in ["matched-at", "matched_at", "url", "host"]:
        value = record.get(key)
        if value:
            return str(value)
    return ""


def evidence_for(record: dict[str, Any]) -> str:
    extracted = as_list(record.get("extracted-results") or record.get("extracted_results"))
    if extracted:
        return "; ".join(extracted[:5])
    parts = []
    for key in ["matcher-name", "type", "matched-at", "ip", "curl-command"]:
        value = record.get(key)
        if value:
            parts.append(f"{key}: {value}")
    return "; ".join(parts)[:1000]


def recommendation_for(category: str, severity: str) -> str:
    if category in {"headers", "csp", "cors"}:
        return "Review the reported HTTP policy or header behavior, de-duplicate against Phase 2, and apply the least-permissive safe configuration."
    if category in {"tls", "ssl"}:
        return "Review the reported TLS observation against the supported-baseline policy and disable weak protocol or cipher support where applicable."
    if category == "exposure":
        return "Manually validate the exposure, remove public access to sensitive resources, rotate any exposed secrets, and add regression controls."
    if category == "tech" or severity == "informational":
        return "Use this detection as supporting context; no vulnerability should be reported without manual validation."
    return "Manually validate the Nuclei observation and remediate only confirmed misconfigurations."


def finding_from_record(record: dict[str, Any], index: int) -> dict[str, str]:
    info = record.get("info") if isinstance(record.get("info"), dict) else {}
    title = str(info.get("name") or record.get("template-id") or "Nuclei finding")
    severity, status, category = classify(record)
    description = str(info.get("description") or f"Nuclei template {record.get('template-id', 'unknown')} matched the target.")
    return {
        "id": f"NUCLEI-{index:03d}",
        "title": title,
        "severity": severity,
        "status": status,
        "source": "phase-5-nuclei",
        "category": category,
        "url": matched_url(record),
        "evidence": evidence_for(record),
        "description": description,
        "recommendation": str(info.get("remediation") or recommendation_for(category, severity)),
    }


def dedup_key(record: dict[str, Any]) -> tuple[str, str, str]:
    extracted = as_list(record.get("extracted-results") or record.get("extracted_results"))
    return (
        str(record.get("template-id") or record.get("templateID") or ""),
        matched_url(record),
        "|".join(extracted),
    )


def parse_jsonl(path: Path | None) -> list[dict[str, str]]:
    if path is None or not path.exists():
        return []
    records: list[dict[str, Any]] = []
    seen: set[tuple[str, str, str]] = set()
    for line_number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"invalid JSONL at {path}:{line_number}: {exc}") from exc
        if not isinstance(record, dict):
            continue
        key = dedup_key(record)
        if key in seen:
            continue
        seen.add(key)
        records.append(record)
    return [finding_from_record(record, idx) for idx, record in enumerate(records, start=1)]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    findings = parse_jsonl(args.input)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(findings, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
