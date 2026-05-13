#!/usr/bin/env python3
"""Generate a minimal Markdown report from a workspace."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def load_findings(workspace: Path) -> list[dict[str, object]]:
    findings_path = workspace / "reports" / "findings" / "normalized-findings.json"
    if not findings_path.exists():
        return []
    data = json.loads(findings_path.read_text(encoding="utf-8"))
    return data if isinstance(data, list) else []


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace", type=Path, required=True)
    args = parser.parse_args()

    workspace = args.workspace.resolve()
    reports_dir = workspace / "reports"
    reports_dir.mkdir(parents=True, exist_ok=True)
    findings = load_findings(workspace)

    lines = [
        "# Web Application Security Assessment Report",
        "",
        f"Workspace: `{workspace}`",
        "",
        "## Findings",
        "",
    ]
    if findings:
        for finding in findings:
            lines.append(f"- {finding.get('severity', 'informational')}: {finding.get('title', 'Untitled')}")
    else:
        lines.append("No normalized findings are present. Scanner observations require manual review.")
    lines.append("")

    output = reports_dir / "report.md"
    output.write_text("\n".join(lines), encoding="utf-8")
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
