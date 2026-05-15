#!/usr/bin/env python3
"""Parse low-impact Nmap web service output into structured findings."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

OPEN_PORT_RE = re.compile(r"^(?P<port>\d+)/tcp\s+open\s+(?P<service>\S+)(?:\s+(?P<version>.*))?$", re.IGNORECASE)
HEADER_MISSING_PATTERNS = {
    "x-content-type-options": "X-Content-Type-Options",
    "referrer-policy": "Referrer-Policy",
    "permissions-policy": "Permissions-Policy",
}


def configured_ports(value: str) -> set[int]:
    ports: set[int] = set()
    for part in value.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            start, _, end = part.partition("-")
            if start.isdigit() and end.isdigit():
                ports.update(range(int(start), int(end) + 1))
        elif part.isdigit():
            ports.add(int(part))
    return ports


def finding(
    idx: int,
    title: str,
    severity: str,
    status: str,
    category: str,
    url: str,
    evidence: str,
    description: str,
    recommendation: str,
) -> dict[str, str]:
    return {
        "id": f"NMAP-{idx:03d}",
        "title": title,
        "severity": severity,
        "status": status,
        "source": "phase-4-nmap",
        "category": category,
        "url": url,
        "evidence": evidence,
        "description": description,
        "recommendation": recommendation,
    }


def port_url(host: str, port: int) -> str:
    scheme = "https" if port == 443 else "http"
    default = (scheme == "https" and port == 443) or (scheme == "http" and port == 80)
    return f"{scheme}://{host}" if default else f"{scheme}://{host}:{port}"


def parse_nmap_text(text: str, target_host: str, ports_value: str) -> list[dict[str, str]]:
    configured = configured_ports(ports_value)
    findings: list[dict[str, str]] = []
    next_id = 1
    current_port: int | None = None
    open_ports: dict[int, str] = {}
    lines = text.splitlines()

    def add(*args: Any) -> None:
        nonlocal next_id
        findings.append(finding(next_id, *args))
        next_id += 1

    for raw_line in lines:
        line = raw_line.rstrip()
        match = OPEN_PORT_RE.match(line)
        if match:
            current_port = int(match.group("port"))
            service = match.group("service") or "unknown"
            version = (match.group("version") or "").strip()
            open_ports[current_port] = " ".join(part for part in [service, version] if part)
            url = port_url(target_host, current_port)
            evidence = line.strip()
            if current_port == 443:
                add(
                    "TCP/443 web service is open",
                    "informational",
                    "observed",
                    "service",
                    url,
                    evidence,
                    "Nmap observed an HTTPS service on TCP/443.",
                    "Confirm the exposed HTTPS service is expected and remains covered by TLS and application monitoring.",
                )
            elif current_port == 80:
                # Redirect evidence may appear later; classify after first pass.
                pass
            elif current_port not in configured:
                add(
                    f"Unexpected open TCP/{current_port} service observed",
                    "low",
                    "observed",
                    "service",
                    url,
                    evidence,
                    "Nmap output contained an open port outside the configured low-impact port list.",
                    "Verify whether this service is intended; keep Nmap profiles constrained to approved ports.",
                )
            if re.search(r"amazon|aws|elastic load balancing|awselb", version, re.IGNORECASE):
                add(
                    "AWS Elastic Load Balancing service observed",
                    "informational",
                    "informational",
                    "service",
                    url,
                    evidence,
                    "The detected service/banner is consistent with AWS Elastic Load Balancing.",
                    "No action is required if the load balancer is expected; continue to validate application-layer controls.",
                )
            continue

    redirect_to_https = bool(re.search(r"http-title:.*redirect.*https://", text, re.IGNORECASE)) or bool(
        re.search(r"did not follow redirect to https://", text, re.IGNORECASE)
    )

    if 80 in open_ports:
        url = port_url(target_host, 80)
        evidence = f"80/tcp open {open_ports[80]}"
        if 80 in configured and redirect_to_https:
            add(
                "TCP/80 redirects to HTTPS",
                "informational",
                "observed",
                "redirect",
                url,
                evidence,
                "TCP/80 is in the configured scan scope and Nmap observed an HTTP-to-HTTPS redirect.",
                "Keep redirect behavior in place and ensure HTTP does not serve sensitive content before redirecting.",
            )
        else:
            add(
                "TCP/80 web service requires review",
                "low",
                "observed",
                "service",
                url,
                evidence,
                "TCP/80 is open and Nmap output did not include clear HTTPS redirect evidence.",
                "Manually verify whether HTTP is intentionally exposed and enforce HTTPS redirection where appropriate.",
            )

    if re.search(r"http-server-header:.*awselb/2\.0|awselb/2\.0", text, re.IGNORECASE | re.DOTALL):
        add(
            "AWS ELB server header observed",
            "informational",
            "informational",
            "headers",
            port_url(target_host, 443 if 443 in open_ports else 80),
            "http-server-header: awselb/2.0",
            "Nmap observed the common AWS Elastic Load Balancing server header.",
            "No direct remediation is required if this infrastructure banner is expected.",
        )

    title_matches = [line.strip(" |_\t") for line in lines if "http-title:" in line.lower()]
    for title_line in title_matches:
        if "redirect" in title_line.lower() or "https://" in title_line.lower():
            add(
                "HTTP title indicates redirect",
                "informational",
                "informational",
                "redirect",
                port_url(target_host, 80 if 80 in open_ports else 443),
                title_line,
                "Nmap's http-title script observed redirect-related page title/output.",
                "Confirm redirects are intentional and terminate at the expected HTTPS application endpoint.",
            )
            break

    if re.search(r"least strength:\s*A\b", text, re.IGNORECASE):
        add(
            "TLS cipher least strength A observed",
            "informational",
            "informational",
            "tls",
            port_url(target_host, 443),
            "ssl-enum-ciphers least strength: A",
            "Nmap ssl-enum-ciphers reported an A least-strength grade for the enumerated TLS ciphers.",
            "Maintain modern TLS configuration and review Phase 1 TLS evidence for more complete validation.",
        )

    seen_missing: set[str] = set()
    for key, pretty in HEADER_MISSING_PATTERNS.items():
        pattern = rf"{re.escape(pretty)}[^\n]*(not set|not present|missing)|{key}[^\n]*(not set|not present|missing)"
        if re.search(pattern, text, re.IGNORECASE) and key not in seen_missing:
            seen_missing.add(key)
            add(
                f"Missing {pretty}",
                "low",
                "confirmed",
                "headers",
                port_url(target_host, 443 if 443 in open_ports else 80),
                f"Nmap http-security-headers reported {pretty} missing",
                f"Nmap's http-security-headers script indicated that {pretty} was absent. Treat this as corroborating evidence and de-duplicate against Phase 2 during reporting.",
                f"Set an appropriate {pretty} response header on applicable HTTP responses.",
            )

    return findings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--target-host", default="")
    parser.add_argument("--ports", default="443")
    args = parser.parse_args()

    text = ""
    if args.input and args.input.exists():
        text = args.input.read_text(encoding="utf-8", errors="replace")
    findings = parse_nmap_text(text, args.target_host or "unknown-target", args.ports)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(findings, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
