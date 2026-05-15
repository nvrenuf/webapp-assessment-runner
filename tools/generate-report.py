#!/usr/bin/env python3
"""Generate Phase 9 report artifacts from workspace evidence.

This helper is intentionally offline-only. It reads existing workspace files,
normalizes and deduplicates findings, builds report deliverables, indexes
local evidence, and optionally creates a sanitized evidence archive.
"""

from __future__ import annotations

import argparse
import csv
import fnmatch
import hashlib
import json
import os
import re
import tarfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

REPORT_VERSION = "phase-9-reporting-v1"
AUTH_NOTE = (
    "Authenticated testing was not completed because credentials/test accounts were not available. "
    "A complete application assessment requires authenticated testing with approved test accounts."
)
SOURCE_FINDING_FILES: list[tuple[str, str]] = [
    ("phase-1-tls", "evidence/phase-1-tls/tls-findings.json"),
    ("phase-2-headers", "evidence/phase-2-headers/headers-findings.json"),
    ("phase-3-nikto", "evidence/phase-3-nikto/nikto-findings.json"),
    ("phase-4-nmap", "evidence/phase-4-nmap/nmap-findings.json"),
    ("phase-5-nuclei", "evidence/phase-5-nuclei/nuclei-findings.json"),
    ("phase-6-zap", "evidence/phase-6-zap/zap-findings.json"),
    ("phase-7-validation", "evidence/phase-7-validation/validation-findings.json"),
    ("phase-8-authenticated", "evidence/phase-8-authenticated/authenticated-findings.json"),
]
SEVERITIES = ["critical", "high", "medium", "low", "informational"]
FINAL_STATUSES = {"confirmed", "observed", "informational"}
NON_FINAL_STATUSES = {"not_confirmed", "not_observed", "not_enabled", "needs_input", "needs_review", "unvalidated"}
CANONICAL_TITLES = {
    "csp": "Permissive Content-Security-Policy",
    "headers": "Missing recommended browser security headers",
    "hsts": "HSTS max-age below one-year hardening baseline",
}
BROWSER_PROFILE_DIR_NAMES = {
    "browser-profile",
    "browser_profiles",
    "browser-profiles",
    "chrome-profile",
    "chromium-profile",
    "firefox-profile",
    "playwright-profile",
    "user-data-dir",
}


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return default


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=False) + "\n", encoding="utf-8")


def parse_env(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    if not path.exists():
        return result
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        result[key] = value
    return result


def as_bool(value: Any) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes", "on", "placeholder", "enabled"}


def metadata_value(metadata: dict[str, Any], env: dict[str, str], keys: list[str], default: str = "") -> str:
    for key in keys:
        if key in metadata and metadata[key] not in (None, ""):
            return str(metadata[key])
        env_key = key.upper()
        if env_key in env and env[env_key] != "":
            return env[env_key]
    return default


def ensure_list(document: Any) -> list[dict[str, Any]]:
    if isinstance(document, list):
        return [item for item in document if isinstance(item, dict)]
    if isinstance(document, dict):
        for key in ("findings", "items", "results", "alerts"):
            value = document.get(key)
            if isinstance(value, list):
                return [item for item in value if isinstance(item, dict)]
    return []


def normalize_source_item(item: dict[str, Any], phase: str, index: int) -> dict[str, Any]:
    source = str(item.get("source") or phase)
    source_id = str(item.get("id") or item.get("source_id") or f"{phase.upper().replace('-', '_')}-{index:03d}")
    title = str(item.get("title") or item.get("name") or item.get("alert") or "Untitled finding")
    severity = str(item.get("severity") or item.get("risk") or item.get("riskdesc") or "informational").split()[0].lower()
    if severity not in SEVERITIES:
        severity = "informational"
    status = str(item.get("status") or item.get("state") or "unvalidated").lower()
    category = category_for(item, title)
    return {
        "id": source_id,
        "title": title,
        "severity": severity,
        "status": status,
        "source": source,
        "source_phase": phase,
        "category": category,
        "url": str(item.get("url") or item.get("affected_url") or item.get("uri") or ""),
        "evidence": str(item.get("evidence") or item.get("proof") or item.get("request") or ""),
        "description": str(item.get("description") or item.get("desc") or ""),
        "recommendation": str(item.get("recommendation") or item.get("solution") or item.get("remediation") or ""),
        "evidence_files": evidence_files_from(item, phase),
        "raw": item,
    }


def load_source_findings(workspace: Path) -> tuple[list[dict[str, Any]], list[dict[str, str]]]:
    findings: list[dict[str, Any]] = []
    files: list[dict[str, str]] = []
    for phase, rel in SOURCE_FINDING_FILES:
        path = workspace / rel
        found = path.exists()
        files.append({"phase": phase, "path": rel, "status": "found" if found else "missing"})
        if not found:
            continue
        for idx, item in enumerate(ensure_list(read_json(path, [])), 1):
            normalized = normalize_source_item(item, phase, idx)
            normalized["source_file"] = rel
            findings.append(normalized)
    return findings, files


def text_blob(*parts: Any) -> str:
    return " ".join(str(part or "") for part in parts).lower()


def category_for(item: dict[str, Any], title: str) -> str:
    explicit = str(item.get("category") or "").lower()
    blob = text_blob(title, explicit, item.get("description"), item.get("evidence"), item.get("recommendation"))
    if "content-security-policy" in blob or "content security policy" in blob or "csp" in blob or "unsafe-inline" in blob or "unsafe-eval" in blob or "form-action" in blob:
        return "csp"
    if "hsts" in blob or "strict-transport-security" in blob:
        return "hsts"
    if "x-content-type-options" in blob or "referrer-policy" in blob or "permissions-policy" in blob or "x-frame-options" in blob or ("browser" in blob and "header" in blob) or explicit == "headers":
        return "headers"
    if "cors" in blob or "cross-origin" in blob or "access-control-allow-origin" in blob:
        return "cors"
    if "null" in blob and "cipher" in blob or "anonymous cipher" in blob:
        return "tls"
    if "tls" in blob or "protocol" in blob or "cipher" in blob:
        return "tls"
    if "cache" in blob or "no-store" in blob:
        return "cache"
    if "auth" in blob or explicit == "auth" or "credentials" in blob:
        return "auth"
    if "redirect" in blob or "location" in blob:
        return "redirect"
    return explicit if explicit in {"misc", "headers", "csp", "cors", "tls", "cache", "auth", "redirect"} else "misc"


def canonical_theme(finding: dict[str, Any]) -> str:
    category = str(finding.get("category") or "misc")
    title = str(finding.get("title") or "")
    blob = text_blob(title, finding.get("description"), finding.get("evidence"), category)
    if category == "csp" or "content-security-policy" in blob or "content security policy" in blob or "unsafe-inline" in blob or "unsafe-eval" in blob:
        return "csp"
    if "hsts" in blob or "strict-transport-security" in blob or "max-age" in blob and "hardening baseline" in blob:
        return "hsts"
    if category == "headers" or "x-content-type-options" in blob or "referrer-policy" in blob or "permissions-policy" in blob:
        return "headers"
    if category == "cors" or "cors" in blob or "cross-origin" in blob:
        return "cors"
    if category == "tls" or "null" in blob and "cipher" in blob or "tls" in blob:
        return "tls"
    if category == "cache" or "cache" in blob:
        return "cache"
    if category == "auth" or "authenticated testing" in blob:
        return "auth"
    if category == "redirect" or "redirect" in blob:
        return "redirect"
    slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:80]
    return f"misc:{slug or 'untitled'}"


def evidence_files_from(item: dict[str, Any], phase: str) -> list[str]:
    values: list[str] = []
    for key in ("evidence_files", "evidence_file", "source_files", "file"):
        value = item.get(key)
        if isinstance(value, list):
            values.extend(str(v) for v in value if v)
        elif value:
            values.append(str(value))
    if values:
        return sorted(dict.fromkeys(values))
    defaults = {
        "phase-7-validation": [
            "evidence/phase-7-validation/validation-login-headers-latest.txt",
            "evidence/phase-7-validation/validation-summary.md",
        ],
        "phase-8-authenticated": ["evidence/phase-8-authenticated/authenticated-summary.md"],
    }
    return defaults.get(phase, [])


def default_impact(theme: str, severity: str) -> str:
    if theme == "csp":
        return "A permissive CSP reduces browser-enforced defense-in-depth and can increase impact if an injection issue is introduced elsewhere."
    if theme == "headers":
        return "Missing browser hardening headers reduce client-side protections and can make some classes of attacks easier to exploit."
    if theme == "hsts":
        return "A short HSTS lifetime weakens HTTPS downgrade protection compared with common one-year hardening baselines."
    return f"The observed issue is rated {severity} and should be reviewed in the context of the tested application."


def default_recommendation(theme: str) -> str:
    if theme == "csp":
        return "Tighten the Content-Security-Policy by removing unsafe directives where practical, adding missing restrictive directives such as form-action, and regression testing required application flows."
    if theme == "headers":
        return "Add the missing recommended browser security headers with values appropriate for the application and verify them on final application responses."
    if theme == "hsts":
        return "Increase Strict-Transport-Security max-age to at least 31536000 seconds after confirming HTTPS coverage, and consider includeSubDomains/preload where appropriate."
    return "Remediate the validated issue and preserve supporting evidence for verification."


def related_source(source: dict[str, Any]) -> dict[str, str]:
    return {
        "source": str(source.get("source") or source.get("source_phase") or "unknown"),
        "id": str(source.get("id") or ""),
        "title": str(source.get("title") or "Untitled finding"),
    }


def merge_evidence_files(items: list[dict[str, Any]]) -> list[str]:
    values: list[str] = []
    for item in items:
        values.extend(str(v) for v in item.get("evidence_files", []) if v)
        if item.get("source_file"):
            values.append(str(item["source_file"]))
    return sorted(dict.fromkeys(values))


def normalize_final_findings(sources: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[str]]:
    notes: list[str] = []
    observations: list[dict[str, Any]] = []
    by_theme: dict[str, list[dict[str, Any]]] = {}
    for item in sources:
        theme = canonical_theme(item)
        item["theme"] = theme
        by_theme.setdefault(theme, []).append(item)

    finals: list[dict[str, Any]] = []
    for theme, items in by_theme.items():
        phase7 = [item for item in items if item.get("source_phase") == "phase-7-validation"]
        selected = [item for item in phase7 if item.get("status") in {"confirmed", "observed", "informational"}]
        if phase7:
            for item in phase7:
                if item.get("status") in NON_FINAL_STATUSES or item.get("status") not in FINAL_STATUSES:
                    observations.append(item)
                    notes.append(f"Kept {item['id']} {item['title']} ({item['status']}) out of final vulnerabilities based on Phase 7 validation status.")
            selected_confirmed = [item for item in selected if item.get("status") == "confirmed"]
            selected_observed_info = [item for item in selected if item.get("status") in {"observed", "informational"}]
            if selected_confirmed:
                base = selected_confirmed[0]
            elif theme in {"tls", "redirect"}:
                # Useful context, but not a final vulnerability for current reports.
                observations.extend(selected_observed_info)
                notes.append(f"Kept {theme} Phase 7 observation out of vulnerability list as informational context.")
                continue
            elif selected_observed_info and selected_observed_info[0].get("severity") == "informational":
                observations.extend(selected_observed_info)
                notes.append(f"Kept {theme} informational observation out of vulnerability list.")
                continue
            elif selected_observed_info:
                base = selected_observed_info[0]
            else:
                continue
        else:
            # Scanner-only issues require review; only include benign informational observations, not vulns.
            for item in items:
                observations.append(item)
            notes.append(f"Did not promote scanner-only theme {theme} to final vulnerability without Phase 7 validation.")
            continue

        if theme in {"cors", "cache", "auth", "tls", "redirect"} and base.get("status") != "confirmed":
            observations.append(base)
            notes.append(f"Kept {base['id']} {base['title']} as observation/limitation instead of final vulnerability.")
            continue
        if base.get("status") == "confirmed" and theme in {"auth"}:
            observations.append(base)
            continue

        category = "headers" if theme == "headers" else "csp" if theme == "csp" else "tls" if theme == "hsts" else str(base.get("category") or "misc")
        title = CANONICAL_TITLES.get(theme, str(base.get("title") or "Untitled finding"))
        related = [related_source(item) for item in items if item is not base]
        source_ids = sorted(dict.fromkeys(str(item.get("id") or "") for item in items if item.get("source_phase") == "phase-7-validation" and item.get("id")))
        source_phases = sorted(dict.fromkeys(str(item.get("source_phase") or item.get("source") or "unknown") for item in phase7 or [base]))
        final = {
            "id": "",
            "title": title,
            "severity": str(base.get("severity") or "informational"),
            "status": str(base.get("status") or "observed"),
            "category": category if category in {"csp", "headers", "cors", "tls", "cache", "auth", "redirect", "misc"} else "misc",
            "affected_url": str(base.get("url") or ""),
            "description": str(base.get("description") or f"Phase 7 directly validated {title}."),
            "evidence": str(base.get("evidence") or ""),
            "impact": default_impact(theme, str(base.get("severity") or "informational")),
            "recommendation": str(base.get("recommendation") or default_recommendation(theme)),
            "source_phases": source_phases,
            "source_ids": source_ids or [str(base.get("id") or "")],
            "related_sources": related,
            "evidence_files": merge_evidence_files(items),
        }
        if final["severity"] in {"critical", "high"} and base.get("source_phase") != "phase-7-validation":
            final["severity"] = "medium"
            notes.append(f"Downgraded {title} because high/critical was not directly validated.")
        finals.append(final)

    severity_order = {name: index for index, name in enumerate(SEVERITIES)}
    finals.sort(key=lambda f: (severity_order.get(f["severity"], 99), f["title"]))
    for idx, item in enumerate(finals, 1):
        item["id"] = f"FINDING-{idx:03d}"
    return finals, observations, notes


def count_by_severity(findings: list[dict[str, Any]]) -> dict[str, int]:
    counts = Counter(str(item.get("severity") or "informational") for item in findings)
    return {severity: counts.get(severity, 0) for severity in SEVERITIES}


def md_table(headers: list[str], rows: list[list[str]]) -> str:
    if not rows:
        return "_None._\n"
    out = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
    for row in rows:
        out.append("| " + " | ".join(str(cell).replace("\n", " ").replace("|", "\\|") for cell in row) + " |")
    return "\n".join(out) + "\n"


def phase_statuses(workspace: Path) -> list[dict[str, str]]:
    statuses: list[dict[str, str]] = []
    status_dir = workspace / "status"
    if not status_dir.exists():
        return statuses
    for path in sorted(status_dir.glob("*.status")):
        data: dict[str, str] = {"phase": path.stem, "path": str(path.relative_to(workspace))}
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                data[key] = value.strip("'")
        statuses.append(data)
    return statuses


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def infer_phase(rel: str) -> str:
    parts = rel.split("/")
    for part in parts:
        if part.startswith("phase-"):
            return part
    if parts and parts[0] in {"status", "reports", "config"}:
        return parts[0]
    return "workspace"


def infer_type(rel: str) -> str:
    name = Path(rel).name.lower()
    if name.endswith(".json"):
        return "json"
    if name.endswith(".md"):
        return "markdown"
    if name.endswith(".csv"):
        return "csv"
    if name.endswith(".txt") or name.endswith(".status"):
        return "text"
    if name.endswith(".tar.gz"):
        return "archive"
    if name.endswith(".html"):
        return "html"
    return "file"


def evidence_index(workspace: Path) -> list[dict[str, Any]]:
    roots = [workspace / "evidence", workspace / "status", workspace / "reports"]
    entries: list[dict[str, Any]] = []
    for root in roots:
        if not root.exists():
            continue
        for path in sorted(p for p in root.rglob("*") if p.is_file()):
            try:
                stat = path.stat()
                rel = path.relative_to(workspace).as_posix()
                entries.append(
                    {
                        "relative_path": rel,
                        "size": stat.st_size,
                        "modified_time": datetime.fromtimestamp(stat.st_mtime, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                        "sha256": file_sha256(path),
                        "phase": infer_phase(rel),
                        "type": infer_type(rel),
                    }
                )
            except OSError:
                continue
    return entries


def write_evidence_index_md(path: Path, entries: list[dict[str, Any]]) -> None:
    rows = [[e["relative_path"], str(e["size"]), e["modified_time"], e["sha256"], e["phase"], e["type"]] for e in entries]
    path.write_text("# Evidence Index\n\n" + md_table(["Path", "Size", "Modified UTC", "SHA-256", "Phase", "Type"], rows), encoding="utf-8")


def limitations_from_sources(sources: list[dict[str, Any]]) -> list[str]:
    limitations: list[str] = []
    for item in sources:
        if item.get("source_phase") == "phase-8-authenticated" and item.get("status") in {"not_enabled", "needs_input"}:
            limitations.append(AUTH_NOTE)
    if not limitations:
        limitations.append(AUTH_NOTE)
    return sorted(dict.fromkeys(limitations))


def observations_md(observations: list[dict[str, Any]]) -> str:
    if not observations:
        return "- None documented.\n"
    rows = []
    for item in observations:
        rows.append([str(item.get("id") or ""), str(item.get("title") or ""), str(item.get("severity") or ""), str(item.get("status") or ""), str(item.get("source_phase") or item.get("source") or "")])
    return md_table(["ID", "Title", "Severity", "Status", "Source"], rows)


def write_reports(workspace: Path, reports_dir: Path, metadata: dict[str, Any], source_files: list[dict[str, str]], finals: list[dict[str, Any]], observations: list[dict[str, Any]], limitations: list[str], archive_created: bool, archive_path: str | None, generated_at: str) -> None:
    counts = count_by_severity(finals)
    title = metadata.get("engagement") or "Web Application Security Assessment"
    company = metadata.get("company") or "Unknown company"
    target = metadata.get("target") or metadata.get("target_base_url") or "Unknown target"
    run_id = metadata.get("run_id") or "unknown"
    summary_rows = [[severity.title(), str(counts[severity])] for severity in SEVERITIES]
    finding_rows = [[f["id"], f["title"], f["severity"], f["status"], f["affected_url"]] for f in finals]
    source_file_rows = [[item["phase"], item["path"], item["status"]] for item in source_files]

    executive = [
        f"# Executive Summary: {title}",
        "",
        "## Engagement Metadata",
        "",
        f"- Company: {company}",
        f"- Engagement: {metadata.get('engagement', '')}",
        f"- Target: {target}",
        f"- Environment: {metadata.get('environment', '')}",
        f"- Profile: {metadata.get('profile', '')}",
        f"- Tester: {metadata.get('tester', '')}",
        f"- Run ID: {run_id}",
        "",
        "## Scope",
        "",
        f"Assessment evidence was generated from the selected workspace for `{target}`. Phase 9 did not perform network testing.",
        "",
        "## High-Level Result",
        "",
        f"Phase 9 produced {len(finals)} final report finding(s) from validated evidence. Scanner-only duplicates were retained as related source evidence or observations rather than promoted as separate vulnerabilities.",
        "",
        "## Finding Counts by Severity",
        "",
        md_table(["Severity", "Count"], summary_rows),
        "## Confirmed Findings",
        "",
        md_table(["ID", "Title", "Severity", "Status", "Affected URL"], finding_rows),
        "## Key Limitations",
        "",
        *[f"- {limitation}" for limitation in limitations],
        "",
    ]
    (reports_dir / "executive-summary.md").write_text("\n".join(executive), encoding="utf-8")

    finding_sections: list[str] = []
    for finding in finals:
        finding_sections.extend(
            [
                f"### {finding['id']} {finding['title']}",
                "",
                f"- Severity: {finding['severity']}",
                f"- Status: {finding['status']}",
                f"- Affected URL: {finding['affected_url']}",
                f"- Source phases: {', '.join(finding['source_phases'])}",
                f"- Source IDs: {', '.join(finding['source_ids'])}",
                f"- Source evidence files: {', '.join(finding['evidence_files']) if finding['evidence_files'] else 'None listed'}",
                "",
                "**Evidence**",
                "",
                finding["evidence"] or "Evidence is referenced in the listed source files.",
                "",
                "**Impact**",
                "",
                finding["impact"],
                "",
                "**Recommendation**",
                "",
                finding["recommendation"],
                "",
            ]
        )

    technical = [
        f"# Technical Report: {title}",
        "",
        "## 1. Title / Metadata",
        "",
        f"- Generated UTC: {generated_at}",
        f"- Company: {company}",
        f"- Engagement: {metadata.get('engagement', '')}",
        f"- Target: {target}",
        f"- Environment: {metadata.get('environment', '')}",
        f"- Profile: {metadata.get('profile', '')}",
        f"- Tester: {metadata.get('tester', '')}",
        f"- Run ID: {run_id}",
        "",
        "## 2. Scope and Target",
        "",
        f"The report covers evidence in `{workspace}` for `{target}`. Scope details are available in `config/scope.yaml` when present.",
        "",
        "## 3. Methodology / Phases",
        "",
        "Phase 9 read completed phase outputs, normalized findings, deduplicated scanner overlap, prioritized Phase 7 direct validation, and generated report-ready artifacts. It did not scan, authenticate, install dependencies, or call external APIs.",
        "",
        "## 4. Executive Summary",
        "",
        f"{len(finals)} final finding(s) were generated. Counts by severity are shown below.",
        "",
        md_table(["Severity", "Count"], summary_rows),
        "## 5. Findings Summary Table",
        "",
        md_table(["ID", "Title", "Severity", "Status", "Affected URL"], finding_rows),
        "## 6. Confirmed Findings",
        "",
        *(finding_sections or ["_No confirmed final findings._\n"]),
        "## 7. Validated Non-Findings / Informational Observations",
        "",
        observations_md(observations),
        "## 8. Authenticated Testing Limitation",
        "",
        AUTH_NOTE,
        "",
        "## 9. Evidence Index Reference",
        "",
        "See `reports/evidence-index.md` and `reports/evidence-index.json`.",
        "",
        "## 10. Appendix: Phase Status Summary",
        "",
        md_table(["Phase", "Status", "Message", "Path"], [[s.get("phase", ""), s.get("STATUS", ""), s.get("MESSAGE", ""), s.get("path", "")] for s in metadata.get("source_phase_statuses", [])]),
    ]
    (reports_dir / "technical-report.md").write_text("\n".join(technical), encoding="utf-8")

    with (reports_dir / "findings-final.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["id", "title", "severity", "status", "category", "affected_url", "description", "evidence", "impact", "recommendation", "source_phases", "source_ids", "evidence_files"])
        writer.writeheader()
        for item in finals:
            row = dict(item)
            row["source_phases"] = ";".join(item["source_phases"])
            row["source_ids"] = ";".join(item["source_ids"])
            row["evidence_files"] = ";".join(item["evidence_files"])
            row.pop("related_sources", None)
            writer.writerow(row)

    summary = [
        "# Report Summary",
        "",
        f"- Generated UTC: {generated_at}",
        f"- Workspace: `{workspace}`",
        f"- Archive created: {str(archive_created).lower()}",
        f"- Archive path: `{archive_path or ''}`",
        "",
        "## Source Files",
        "",
        md_table(["Phase", "Path", "Status"], source_file_rows),
        "## Final Finding Counts",
        "",
        md_table(["Severity", "Count"], summary_rows),
        "## Report Paths",
        "",
        *[f"- reports/{name}" for name in ["executive-summary.md", "technical-report.md", "findings-final.json", "findings-final.csv", "evidence-index.md", "evidence-index.json", "report-metadata.json", "report-summary.md"]],
        "",
    ]
    (reports_dir / "report-summary.md").write_text("\n".join(summary), encoding="utf-8")
    # Backward-compatible convenience report for older tests/operators.
    compatibility = (reports_dir / "technical-report.md").read_text(encoding="utf-8")
    if not finals:
        compatibility += "\nNo normalized findings are present. Scanner observations require manual review.\n"
    (reports_dir / "report.md").write_text(compatibility, encoding="utf-8")


def archive_excluded(rel: str) -> bool:
    rel_lower = rel.lower()
    name = Path(rel_lower).name
    parts = set(Path(rel_lower).parts)
    if rel_lower == "config/auth.env":
        return True
    if any(part in BROWSER_PROFILE_DIR_NAMES for part in parts):
        return True
    for pattern in ("*cookie*", "*session*", "*token*", "*.har"):
        if fnmatch.fnmatch(name, pattern) or fnmatch.fnmatch(rel_lower, pattern):
            return True
    return False


def build_archive(workspace: Path, reports_dir: Path, phase_run_id: str) -> tuple[str | None, dict[str, Any]]:
    archive_path = reports_dir / f"evidence-package-{phase_run_id}.tar.gz"
    include_roots = ["config/metadata.json", "config/scope.yaml", "status", "evidence", "reports"]
    included: list[dict[str, Any]] = []
    excluded: list[str] = []
    candidates: list[Path] = []
    for rel in include_roots:
        path = workspace / rel
        if not path.exists():
            continue
        if path.is_file():
            candidates.append(path)
        else:
            candidates.extend(sorted(p for p in path.rglob("*") if p.is_file()))
    with tarfile.open(archive_path, "w:gz") as tar:
        for path in candidates:
            rel = path.relative_to(workspace).as_posix()
            if rel == archive_path.relative_to(workspace).as_posix() or archive_excluded(rel):
                excluded.append(rel)
                continue
            try:
                stat = path.stat()
                tar.add(path, arcname=rel, recursive=False)
                included.append({"relative_path": rel, "size": stat.st_size, "sha256": file_sha256(path)})
            except OSError:
                excluded.append(rel)
    manifest = {
        "archive": archive_path.relative_to(workspace).as_posix(),
        "created_at": utc_now(),
        "phase_run_id": phase_run_id,
        "included": included,
        "excluded": sorted(excluded),
        "exclusion_rules": ["config/auth.env", "*cookie*", "*session*", "*token*", "*.har", "browser profile directories"],
    }
    write_json(reports_dir / f"archive-manifest-{phase_run_id}.json", manifest)
    write_json(reports_dir / "archive-manifest-latest.json", manifest)
    return archive_path.as_posix(), manifest


def generate(workspace: Path, phase_run_id: str, archive: bool) -> dict[str, Any]:
    workspace = workspace.resolve()
    reports_dir = workspace / "reports"
    phase9_dir = workspace / "evidence" / "phase-9-reporting"
    reports_dir.mkdir(parents=True, exist_ok=True)
    phase9_dir.mkdir(parents=True, exist_ok=True)
    generated_at = utc_now()
    env = parse_env(workspace / "config" / "target.env")
    metadata_doc = read_json(workspace / "config" / "metadata.json", {})
    metadata_doc = metadata_doc if isinstance(metadata_doc, dict) else {}
    source_findings, source_files = load_source_findings(workspace)
    finals, observations, notes = normalize_final_findings(source_findings)
    limitations = limitations_from_sources(source_findings)
    statuses = phase_statuses(workspace)
    report_metadata = {
        "company": metadata_value(metadata_doc, env, ["company"], ""),
        "engagement": metadata_value(metadata_doc, env, ["engagement", "engagement_name"], ""),
        "target": metadata_value(metadata_doc, env, ["target", "target_base_url"], env.get("TARGET_BASE_URL", "")),
        "environment": metadata_value(metadata_doc, env, ["environment"], env.get("ENVIRONMENT", "")),
        "profile": metadata_value(metadata_doc, env, ["profile"], env.get("PROFILE", "")),
        "auth_mode": metadata_value(metadata_doc, env, ["auth_mode"], env.get("AUTH_MODE", "none")),
        "auth_enabled": bool(metadata_doc.get("auth_enabled", as_bool(env.get("AUTH_ENABLED", "false")))),
        "tester": metadata_value(metadata_doc, env, ["tester"], ""),
        "run_id": metadata_value(metadata_doc, env, ["run_id"], workspace.name),
        "workspace": workspace.as_posix(),
        "generated_at": generated_at,
        "report_version": REPORT_VERSION,
        "source_phase_statuses": statuses,
    }
    archive_path: str | None = None
    archive_manifest: dict[str, Any] | None = None
    planned_archive_path = (reports_dir / f"evidence-package-{phase_run_id}.tar.gz").as_posix() if archive else None

    write_json(reports_dir / "findings-final.json", finals)
    write_json(phase9_dir / f"source-findings-{phase_run_id}.json", {"source_files": source_files, "findings": source_findings})
    write_json(phase9_dir / "source-findings-latest.json", {"source_files": source_files, "findings": source_findings})

    notes_text = ["# Normalization Notes", "", f"- Generated UTC: {generated_at}", f"- Source findings loaded: {len(source_findings)}", f"- Final findings produced: {len(finals)}", "", "## Decisions", ""]
    notes_text.extend([f"- {note}" for note in notes] or ["- No normalization decisions were required beyond default Phase 7 prioritization."])
    notes_text.extend(["", "## Limitations", ""] + [f"- {limitation}" for limitation in limitations] + [""])
    (phase9_dir / f"normalization-notes-{phase_run_id}.md").write_text("\n".join(notes_text), encoding="utf-8")
    (phase9_dir / "normalization-notes-latest.md").write_text("\n".join(notes_text), encoding="utf-8")

    write_json(reports_dir / "report-metadata.json", report_metadata)
    write_reports(workspace, reports_dir, report_metadata, source_files, finals, observations, limitations, archive, planned_archive_path, generated_at)

    # Build an initial evidence index so the archive contains the report index files.
    entries = evidence_index(workspace)
    write_json(reports_dir / "evidence-index.json", entries)
    write_evidence_index_md(reports_dir / "evidence-index.md", entries)

    if archive:
        archive_path, archive_manifest = build_archive(workspace, reports_dir, phase_run_id)

    # Refresh index after index/archive/manifest files exist; this pass includes Phase 9 report artifacts.
    entries = evidence_index(workspace)
    write_json(reports_dir / "evidence-index.json", entries)
    write_evidence_index_md(reports_dir / "evidence-index.md", entries)

    return {
        "workspace": workspace.as_posix(),
        "report_dir": reports_dir.as_posix(),
        "phase9_dir": phase9_dir.as_posix(),
        "phase_run_id": phase_run_id,
        "final_findings": len(finals),
        "counts": count_by_severity(finals),
        "archive_created": bool(archive_path),
        "archive_path": archive_path,
        "archive_manifest": archive_manifest,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 9 report artifacts from workspace evidence.")
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--phase-run-id", default=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
    parser.add_argument("--archive", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()
    result = generate(args.workspace, args.phase_run_id, args.archive)
    print(f"Report directory: {result['report_dir']}")
    print(f"Final findings: {result['final_findings']}")
    print(f"Archive created: {str(result['archive_created']).lower()}")
    if result.get("archive_path"):
        print(f"Archive path: {result['archive_path']}")
    if args.verbose:
        print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
