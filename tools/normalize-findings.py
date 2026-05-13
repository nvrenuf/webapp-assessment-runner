#!/usr/bin/env python3
"""Normalize parser output into a shared findings shape."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def normalize_item(item: dict[str, Any], source: str) -> dict[str, Any]:
    return {
        "title": item.get("title", "Unreviewed scanner observation"),
        "severity": item.get("severity", "informational"),
        "source": item.get("source", source),
        "status": item.get("status", "unvalidated"),
        "evidence": item.get("evidence", []),
        "description": item.get("description", ""),
        "recommendation": item.get("recommendation", ""),
    }


def load_items(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, list):
        return [item for item in data if isinstance(item, dict)]
    if isinstance(data, dict) and isinstance(data.get("findings"), list):
        return [item for item in data["findings"] if isinstance(item, dict)]
    return []


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    findings: list[dict[str, Any]] = []
    for input_path in args.input:
        source = input_path.stem
        findings.extend(normalize_item(item, source) for item in load_items(input_path))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(findings, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
