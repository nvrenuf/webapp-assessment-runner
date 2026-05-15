#!/usr/bin/env python3
"""Parse OWASP ZAP alerts JSON into normalized Phase 6 findings."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

RISK_MAP = {
    "high": ("high", "needs_review"),
    "medium": ("medium", "needs_review"),
    "low": ("low", "observed"),
    "informational": ("informational", "informational"),
    "info": ("informational", "informational"),
}


def text_blob(*parts: Any) -> str:
    return " ".join(str(part or "") for part in parts).lower()


def alerts_from_document(document: Any) -> list[dict[str, Any]]:
    if isinstance(document, dict):
        alerts = document.get("alerts", [])
    elif isinstance(document, list):
        alerts = document
    else:
        alerts = []
    return [alert for alert in alerts if isinstance(alert, dict)]


def normalize_risk(alert: dict[str, Any]) -> tuple[str, str]:
    risk = str(alert.get("risk") or alert.get("riskdesc") or "informational").split()[0].lower()
    return RISK_MAP.get(risk, ("informational", "informational"))


def category_for(alert: dict[str, Any]) -> str:
    name = str(alert.get("alert") or alert.get("name") or "ZAP alert")
    blob = text_blob(name, alert.get("description"), alert.get("solution"), alert.get("evidence"), alert.get("param"), alert.get("pluginId"))
    if "content security policy" in blob or "csp" in blob or "unsafe-inline" in blob or "unsafe-eval" in blob or "form-action" in blob:
        return "csp"
    if "x-content-type-options" in blob or "anti-mime-sniffing" in blob or "header" in blob:
        return "headers"
    if "cookie" in blob or "samesite" in blob or "httponly" in blob or "secure flag" in blob:
        return "cookie"
    if "cache" in blob or "cache-control" in blob or "pragma" in blob:
        return "cache"
    if "cross site scripting" in blob or "cross-site scripting" in blob or "xss" in blob or "script" in blob and "passive" in blob:
        return "xss"
    if "cors" in blob or "cross-origin resource sharing" in blob or "access-control-allow-origin" in blob:
        return "cors"
    return "misc"


def adjusted_severity(alert: dict[str, Any], severity: str) -> str:
    blob = text_blob(alert.get("alert"), alert.get("name"), alert.get("description"), alert.get("evidence"))
    if "x-content-type-options" in blob or "anti-mime-sniffing" in blob:
        return "low"
    if "modern web application" in blob or "browser" in blob and severity == "informational":
        return "informational"
    return severity


def recommendation_for(category: str, status: str) -> str:
    if category == "csp":
        return "Review the Content Security Policy, remove unsafe directives where practical, and add missing restrictive directives such as form-action after compatibility testing."
    if category == "headers":
        return "Add or correct the reported HTTP security header and de-duplicate this observation against Phase 2 header findings."
    if category == "cookie":
        return "Set appropriate Secure, HttpOnly, and SameSite cookie attributes based on cookie purpose and transport requirements."
    if category == "cache":
        return "Review caching headers for sensitive responses and apply no-store or private cache controls where appropriate."
    if category == "xss":
        return "Manually validate the passive XSS-related observation before reporting and remediate output encoding or policy gaps if confirmed."
    if category == "cors":
        return "Review CORS policy for least privilege and validate that only trusted origins can access sensitive responses."
    if status == "informational":
        return "Use this observation as supporting context; do not report it as a vulnerability without manual validation."
    return "Manually review the ZAP passive alert and remediate only confirmed application or configuration issues."


def description_for(alert: dict[str, Any]) -> str:
    for key in ("description", "desc", "riskdesc"):
        value = alert.get(key)
        if value:
            return str(value)
    return "OWASP ZAP reported this passive alert during Phase 6."


def evidence_for(alert: dict[str, Any]) -> str:
    evidence = str(alert.get("evidence") or "")
    param = str(alert.get("param") or "")
    attack = str(alert.get("attack") or "")
    pieces = []
    if evidence:
        pieces.append(evidence)
    if param:
        pieces.append(f"param: {param}")
    if attack:
        pieces.append(f"attack: {attack}")
    return "; ".join(pieces)[:1000]


def title_for(alert: dict[str, Any]) -> str:
    return str(alert.get("alert") or alert.get("name") or "ZAP passive alert")


def url_for(alert: dict[str, Any]) -> str:
    return str(alert.get("url") or alert.get("uri") or "")


def finding_from_alert(alert: dict[str, Any], index: int) -> dict[str, str]:
    severity, status = normalize_risk(alert)
    severity = adjusted_severity(alert, severity)
    if severity == "informational":
        status = "informational"
    elif severity in {"high", "medium"}:
        status = "needs_review"
    elif status == "informational":
        status = "observed"
    category = category_for(alert)
    return {
        "id": f"ZAP-{index:03d}",
        "title": title_for(alert),
        "severity": severity,
        "status": status,
        "source": "phase-6-zap",
        "category": category,
        "url": url_for(alert),
        "evidence": evidence_for(alert),
        "description": description_for(alert),
        "recommendation": str(alert.get("solution") or recommendation_for(category, status)),
    }


def parse_alerts(path: Path | None) -> list[dict[str, str]]:
    if path is None or not path.exists():
        return []
    document = json.loads(path.read_text(encoding="utf-8", errors="replace"))
    alerts = alerts_from_document(document)
    findings: list[dict[str, str]] = []
    seen: set[tuple[str, str, str]] = set()
    for alert in alerts:
        key = (title_for(alert), url_for(alert), evidence_for(alert))
        if key in seen:
            continue
        seen.add(key)
        findings.append(finding_from_alert(alert, len(findings) + 1))
    return findings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    findings = parse_alerts(args.input)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(findings, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
