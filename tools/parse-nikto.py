#!/usr/bin/env python3
"""Parse Nikto text output into conservative structured findings."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

SOURCE = "phase-3-nikto"


class FindingBuilder:
    def __init__(self) -> None:
        self._items: list[dict[str, Any]] = []
        self._seen: set[tuple[str, str, str]] = set()

    def add(
        self,
        *,
        title: str,
        severity: str,
        status: str,
        category: str,
        url: str,
        evidence: str,
        description: str,
        recommendation: str,
    ) -> None:
        key = (title.lower(), category, evidence.lower())
        if key in self._seen:
            return
        self._seen.add(key)
        self._items.append(
            {
                "id": f"NIKTO-{len(self._items) + 1:03d}",
                "title": title,
                "severity": severity,
                "status": status,
                "source": SOURCE,
                "category": category,
                "url": url,
                "evidence": evidence,
                "description": description,
                "recommendation": recommendation,
            }
        )

    @property
    def items(self) -> list[dict[str, Any]]:
        return self._items


def clean_observation(line: str) -> str:
    line = line.strip()
    line = re.sub(r"^\+\s*", "", line)
    return line.strip()


def classify(line: str, url: str) -> dict[str, str] | None:
    obs = clean_observation(line)
    if not obs:
        return None
    lower = obs.lower()

    if "x-content-type-options" in lower and ("not present" in lower or "missing" in lower):
        return {
            "title": "Missing X-Content-Type-Options",
            "severity": "low",
            "status": "confirmed",
            "category": "headers",
            "description": "Nikto observed that the X-Content-Type-Options response header is missing.",
            "recommendation": "Send X-Content-Type-Options: nosniff on applicable HTTP responses.",
        }
    if "permissions-policy" in lower and ("not present" in lower or "missing" in lower):
        return {
            "title": "Missing Permissions-Policy",
            "severity": "low",
            "status": "confirmed",
            "category": "headers",
            "description": "Nikto observed that the Permissions-Policy response header is missing.",
            "recommendation": "Define a least-privilege Permissions-Policy header for browser features used by the application.",
        }
    if "referrer-policy" in lower and ("not present" in lower or "missing" in lower):
        return {
            "title": "Missing Referrer-Policy",
            "severity": "low",
            "status": "confirmed",
            "category": "headers",
            "description": "Nikto observed that the Referrer-Policy response header is missing.",
            "recommendation": "Set an explicit Referrer-Policy such as strict-origin-when-cross-origin after application review.",
        }
    if "refresh" in lower and "header" in lower and ("uncommon" in lower or "non-standard" in lower):
        return {
            "title": "Uncommon Refresh header observed",
            "severity": "low",
            "status": "observed",
            "category": "headers",
            "description": "Nikto reported an uncommon Refresh header behavior that may warrant review.",
            "recommendation": "Review whether Refresh redirects are intentional and replace them with standard HTTP redirects where practical.",
        }
    if "server banner" in lower and "changed" in lower:
        return {
            "title": "Server banner changed during scan",
            "severity": "informational",
            "status": "informational",
            "category": "server",
            "description": "Nikto observed a server banner change during the run.",
            "recommendation": "Confirm whether the banner variation is expected from load balancing, CDN, or deployment behavior.",
        }
    if "server:" in lower and ("awselb/2.0" in lower or "private" in lower):
        return {
            "title": "Server header disclosure observed",
            "severity": "informational",
            "status": "informational",
            "category": "server",
            "description": "Nikto observed a server header value that discloses platform or internal implementation details.",
            "recommendation": "Review whether server banner disclosure can be minimized without impacting operations.",
        }
    if "wildcard" in lower and ("certificate" in lower or "cert" in lower):
        return {
            "title": "Wildcard certificate observed",
            "severity": "informational",
            "status": "informational",
            "category": "tls",
            "description": "Nikto observed use of a wildcard TLS certificate.",
            "recommendation": "Ensure wildcard certificate private keys are tightly controlled and certificate scope is intentional.",
        }
    if "no cgi directories" in lower or "no cgi dirs" in lower:
        return {
            "title": "No CGI directories found",
            "severity": "informational",
            "status": "informational",
            "category": "directories",
            "description": "Nikto did not identify common CGI directories on the target.",
            "recommendation": "No action is required; retain this as scanner context.",
        }
    if "failed" in lower and "update" in lower:
        return {
            "title": "Nikto update check failed",
            "severity": "informational",
            "status": "informational",
            "category": "tooling",
            "description": "Nikto reported that it could not check for updates during execution.",
            "recommendation": "Update Nikto out of band during maintenance windows and do not rely on in-scan update checks.",
        }
    if "multiple ip" in lower or "multiple address" in lower:
        return {
            "title": "Multiple IP addresses found for target",
            "severity": "informational",
            "status": "informational",
            "category": "server",
            "description": "Nikto observed multiple resolved IP addresses for the target host.",
            "recommendation": "Confirm that all resolved addresses are expected load balancer, CDN, or hosting endpoints.",
        }

    medium_patterns = (
        "directory indexing",
        "index of /",
        ".env",
        "config.php",
        "wp-config",
        "backup",
        "database dump",
        "admin",
        "phpinfo",
    )
    low_patterns = (
        "default file",
        "interesting file",
        "readme",
        "license",
        "robots.txt",
        "sitemap.xml",
        "directory",
        "file found",
    )
    if any(pattern in lower for pattern in medium_patterns):
        return {
            "title": "Potentially exposed sensitive path or file",
            "severity": "medium",
            "status": "observed",
            "category": "files",
            "description": "Nikto reported an exposed path or file that may present risk depending on content and access controls.",
            "recommendation": "Manually validate the path, remove unnecessary exposure, and restrict access where appropriate.",
        }
    if any(pattern in lower for pattern in low_patterns):
        return {
            "title": "Potentially exposed default or informational path",
            "severity": "low",
            "status": "observed",
            "category": "files",
            "description": "Nikto reported a potentially exposed default or informational path.",
            "recommendation": "Review the path manually and remove or restrict it if it is not intentionally public.",
        }
    return None


def parse_file(path: Path, target_url: str | None, builder: FindingBuilder) -> None:
    text = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
    url = target_url or infer_url(text) or ""
    for line in text.splitlines():
        if not line.lstrip().startswith("+"):
            continue
        classification = classify(line, url)
        if classification is None:
            continue
        builder.add(url=url, evidence=clean_observation(line), **classification)


def infer_url(text: str) -> str:
    for line in text.splitlines():
        match = re.search(r"https?://\S+", line)
        if match:
            return match.group(0).rstrip(",.;")
    return ""


def parse_target_map(values: list[str]) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for value in values:
        if "=" not in value:
            continue
        key, url = value.split("=", 1)
        mapping[key] = url
    return mapping


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, action="append", default=[])
    parser.add_argument("--target", action="append", default=[], help="label=url mapping for input filename labels")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    target_map = parse_target_map(args.target)
    builder = FindingBuilder()
    for input_path in args.input:
        label = input_path.name
        match = re.match(r"nikto-([a-z0-9_-]+)-", label)
        target_url = target_map.get(match.group(1)) if match else None
        parse_file(input_path, target_url, builder)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(builder.items, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
