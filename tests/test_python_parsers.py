import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def run_tool(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, *args],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )


def test_parser_stubs_write_empty_findings(tmp_path: Path) -> None:
    zap_output = tmp_path / "parse-zap.py.json"
    run_tool("tools/parse-zap.py", "--output", str(zap_output))
    assert json.loads(zap_output.read_text(encoding="utf-8")) == []

    nuclei_output = tmp_path / "parse-nuclei.py.json"
    run_tool("tools/parse-nuclei.py", "--output", str(nuclei_output))
    assert json.loads(nuclei_output.read_text(encoding="utf-8")) == []

    nmap_output = tmp_path / "parse-nmap.py.json"
    run_tool("tools/parse-nmap.py", "--output", str(nmap_output))
    assert json.loads(nmap_output.read_text(encoding="utf-8")) == []


def test_parse_nikto_without_input_writes_empty_list(tmp_path: Path) -> None:
    output = tmp_path / "parse-nikto.py.json"
    run_tool("tools/parse-nikto.py", "--output", str(output))
    assert json.loads(output.read_text(encoding="utf-8")) == []


def test_normalize_findings(tmp_path: Path) -> None:
    source = tmp_path / "source.json"
    output = tmp_path / "normalized.json"
    source.write_text(
        json.dumps({"findings": [{"title": "Missing header", "severity": "low"}]}),
        encoding="utf-8",
    )

    run_tool("tools/normalize-findings.py", "--input", str(source), "--output", str(output))
    findings = json.loads(output.read_text(encoding="utf-8"))

    assert findings[0]["title"] == "Missing header"
    assert findings[0]["status"] == "unvalidated"


def test_generate_report(tmp_path: Path) -> None:
    workspace = tmp_path / "workspace"
    findings_dir = workspace / "reports" / "findings"
    findings_dir.mkdir(parents=True)
    (findings_dir / "normalized-findings.json").write_text("[]\n", encoding="utf-8")

    run_tool("tools/generate-report.py", "--workspace", str(workspace))

    report = workspace / "reports" / "report.md"
    assert report.exists()
    assert "No normalized findings" in report.read_text(encoding="utf-8")


def test_parse_nikto_classification_rules(tmp_path: Path) -> None:
    raw = tmp_path / "nikto-login-20260514T000000Z.txt"
    output = tmp_path / "findings.json"
    raw.write_text(
        "\n".join(
            [
                "+ Target URL: https://app.example.com/login",
                "+ The X-Content-Type-Options header is not present.",
                "+ Permissions-Policy header is not present.",
                "+ Referrer-Policy header is not present.",
                "+ Uncommon header 'Refresh' found, with contents: 0; url=/next",
                "+ Server banner changed from 'awselb/2.0' to 'private'",
                "+ SSL Certificate Subject Wildcard *.example.com",
                "+ ERROR: Failed to check for updates: 403 Forbidden",
                "+ No CGI Directories found (use '-C all' to force check all possible dirs)",
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    run_tool(
        "tools/parse-nikto.py",
        "--input",
        str(raw),
        "--target",
        "login=https://app.example.com/login",
        "--output",
        str(output),
    )
    findings = json.loads(output.read_text(encoding="utf-8"))

    def has(title: str, severity: str, status: str, category: str) -> bool:
        return any(
            item["title"] == title
            and item["severity"] == severity
            and item["status"] == status
            and item["category"] == category
            for item in findings
        )

    assert has("Missing X-Content-Type-Options", "low", "confirmed", "headers")
    assert has("Missing Permissions-Policy", "low", "confirmed", "headers")
    assert has("Missing Referrer-Policy", "low", "confirmed", "headers")
    assert has("Uncommon Refresh header observed", "low", "observed", "headers")
    assert has("Server banner changed during scan", "informational", "informational", "server")
    assert has("Wildcard certificate observed", "informational", "informational", "tls")
    assert has("Nikto update check failed", "informational", "informational", "tooling")
    assert has("No CGI directories found", "informational", "informational", "directories")
    assert not any(item["severity"] == "high" for item in findings)



def nmap_fixture() -> str:
    return """
Starting Nmap 7.95 ( https://nmap.org )
Nmap scan report for app.example.com (203.0.113.10)
Host is up (0.020s latency).
PORT    STATE SERVICE  VERSION
80/tcp  open  http     awselb/2.0
|_http-title: Did not follow redirect to https://app.example.com/
443/tcp open  ssl/http Amazon Elastic Load Balancing
| http-server-header:
|_  awselb/2.0
| http-security-headers:
|   X-Content-Type-Options: Header not set
|   Referrer-Policy: Header not set
|_  Permissions-Policy: Header not set
| ssl-enum-ciphers:
|   TLSv1.2:
|     ciphers:
|       TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256 (secp256r1) - A
|_  least strength: A
Service detection performed.
Nmap done: 1 IP address (1 host up) scanned in 1.23 seconds
""".lstrip()


def test_parse_nmap_classification_rules(tmp_path: Path) -> None:
    raw = tmp_path / "nmap-web-20260515T000000Z.nmap"
    output = tmp_path / "nmap-findings.json"
    raw.write_text(nmap_fixture(), encoding="utf-8")

    run_tool(
        "tools/parse-nmap.py",
        "--input",
        str(raw),
        "--output",
        str(output),
        "--target-host",
        "app.example.com",
        "--ports",
        "80,443",
    )
    findings = json.loads(output.read_text(encoding="utf-8"))

    def has(title: str, severity: str, status: str, category: str) -> bool:
        return any(
            item["title"] == title
            and item["severity"] == severity
            and item["status"] == status
            and item["category"] == category
            for item in findings
        )

    assert has("TCP/443 web service is open", "informational", "observed", "service")
    assert has("TCP/80 redirects to HTTPS", "informational", "observed", "redirect")
    assert has("AWS Elastic Load Balancing service observed", "informational", "informational", "service")
    assert has("AWS ELB server header observed", "informational", "informational", "headers")
    assert has("HTTP title indicates redirect", "informational", "informational", "redirect")
    assert has("TLS cipher least strength A observed", "informational", "informational", "tls")
    assert has("Missing X-Content-Type-Options", "low", "confirmed", "headers")
    assert has("Missing Referrer-Policy", "low", "confirmed", "headers")
    assert has("Missing Permissions-Policy", "low", "confirmed", "headers")
    assert not any(item["severity"] == "high" for item in findings)


def test_parse_nmap_missing_headers_with_underscore_names(tmp_path: Path) -> None:
    raw = tmp_path / "nmap-web-underscore-20260515T000000Z.nmap"
    output = tmp_path / "nmap-findings.json"
    raw.write_text(
        """
Starting Nmap 7.95 ( https://nmap.org )
Nmap scan report for app.example.com (203.0.113.10)
Host is up (0.020s latency).
PORT    STATE SERVICE  VERSION
443/tcp open  ssl/http Amazon Elastic Load Balancing
| http-security-headers:
|   X_Content_Type_Options: Header not set
|   Referrer_Policy: Header not set
|_  Permissions_Policy: Header not set
Nmap done: 1 IP address (1 host up) scanned in 1.23 seconds
""".lstrip(),
        encoding="utf-8",
    )

    run_tool(
        "tools/parse-nmap.py",
        "--input",
        str(raw),
        "--output",
        str(output),
        "--target-host",
        "app.example.com",
        "--ports",
        "443",
    )
    findings = json.loads(output.read_text(encoding="utf-8"))
    titles = {item["title"] for item in findings}

    assert "Missing X-Content-Type-Options" in titles
    assert "Missing Referrer-Policy" in titles
    assert "Missing Permissions-Policy" in titles


def make_workspace(tmp_path: Path, fake_nmap: Path) -> Path:
    workspace = tmp_path / "workspace"
    (workspace / "config").mkdir(parents=True)
    (workspace / "status").mkdir()
    (workspace / "evidence").mkdir()
    (workspace / "config" / "target.env").write_text(
        '\n'.join(
            [
                'TARGET_BASE_URL="https://app.example.com"',
                'LOGIN_URL="https://app.example.com/login"',
                'TARGET_HOST="app.example.com"',
                'PROFILE="deep"',
            ]
        )
        + '\n',
        encoding="utf-8",
    )
    (workspace / "config" / "tool-paths.env").write_text(f'NMAP_BIN="{fake_nmap}"\n', encoding="utf-8")
    return workspace


def write_fake_nmap(path: Path) -> None:
    path.write_text(
        """#!/usr/bin/env bash
set -Eeuo pipefail
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -oA)
      out="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
[[ -n "${out}" ]] || exit 2
cat > "${out}.nmap" <<'EOF'
Starting Nmap 7.95 ( https://nmap.org )
Nmap scan report for app.example.com (203.0.113.10)
Host is up (0.020s latency).
PORT    STATE SERVICE  VERSION
80/tcp  open  http     awselb/2.0
|_http-title: Did not follow redirect to https://app.example.com/
443/tcp open  ssl/http Amazon Elastic Load Balancing
| http-server-header:
|_  awselb/2.0
| http-security-headers:
|   X-Content-Type-Options: Header not set
|   Referrer-Policy: Header not set
|_  Permissions-Policy: Header not set
| ssl-enum-ciphers:
|_  least strength: A
Nmap done: 1 IP address (1 host up) scanned in 1.23 seconds
EOF
printf '<nmaprun></nmaprun>\n' > "${out}.xml"
printf 'Host: 203.0.113.10 () Ports: 80/open/tcp//http//awselb/2.0/, 443/open/tcp//ssl/http//Amazon Elastic Load Balancing/\n' > "${out}.gnmap"
printf 'fake nmap wrote %s\n' "${out}"
""",
        encoding="utf-8",
    )
    path.chmod(0o755)


def run_phase(workspace: Path, *extra: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", "phases/04-nmap.sh", "--workspace", str(workspace), "--yes", *extra],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )


def test_phase_4_nmap_mocked_rerun_and_clean(tmp_path: Path) -> None:
    fake_nmap = tmp_path / "fake-nmap"
    write_fake_nmap(fake_nmap)
    workspace = make_workspace(tmp_path, fake_nmap)

    first = run_phase(workspace)
    assert "phase-4-nmap starting" in first.stdout
    assert "monitor command: tail -f" in first.stdout
    evidence = workspace / "evidence" / "phase-4-nmap"
    assert (evidence / "nmap-web-latest.nmap").exists()
    assert (evidence / "nmap-web-latest.xml").exists()
    assert (evidence / "nmap-web-latest.gnmap").exists()
    assert (evidence / "nmap-web-console-latest.txt").exists()
    assert (evidence / "nmap-summary.md").exists()
    findings_path = evidence / "nmap-findings.json"
    findings = json.loads(findings_path.read_text(encoding="utf-8"))
    assert any(item["title"] == "TLS cipher least strength A observed" for item in findings)
    assert any(item["title"] == "AWS ELB server header observed" for item in findings)
    assert "STATUS=success" in (workspace / "status" / "phase-4-nmap.status").read_text(encoding="utf-8")
    first_raw = sorted(evidence.glob("nmap-web-[0-9]*T[0-9]*Z.nmap"))
    assert len(first_raw) == 1

    run_phase(workspace)
    second_raw = sorted(evidence.glob("nmap-web-[0-9]*T[0-9]*Z.nmap"))
    assert len(second_raw) >= 2

    run_phase(workspace, "--clean")
    clean_raw = sorted(evidence.glob("nmap-web-[0-9]*T[0-9]*Z.nmap"))
    assert len(clean_raw) == 1
    assert (evidence / "nmap-web-latest.nmap").exists()
    assert (evidence / "nmap-summary.md").exists()
    assert (evidence / "nmap-findings.json").exists()


def nuclei_jsonl_fixture() -> str:
    rows = [
        {
            "template-id": "tls-version",
            "info": {"name": "TLS Version", "severity": "info", "tags": "tls,ssl"},
            "matched-at": "https://app.example.com",
            "extracted-results": ["TLS 1.2 supported"],
        },
        {
            "template-id": "missing-x-frame-options",
            "info": {"name": "Missing X-Frame-Options", "severity": "low", "tags": "headers,misconfig"},
            "matched-at": "https://app.example.com",
            "extracted-results": ["X-Frame-Options header is missing"],
        },
        {
            "template-id": "cors-misconfig",
            "info": {"name": "CORS Misconfiguration", "severity": "medium", "tags": "cors,misconfig"},
            "matched-at": "https://app.example.com",
            "extracted-results": ["Access-Control-Allow-Origin: *"],
        },
        {
            "template-id": "exposed-env-file",
            "info": {"name": "Exposed Environment File", "severity": "high", "tags": "exposure,config"},
            "matched-at": "https://app.example.com/.env",
            "extracted-results": ["SECRET_KEY=redacted"],
        },
        {
            "template-id": "tech-detect:nginx",
            "info": {"name": "Nginx Technology Detection", "severity": "info", "tags": "tech"},
            "matched-at": "https://app.example.com",
            "extracted-results": ["nginx"],
        },
        {
            "template-id": "tech-detect:nginx",
            "info": {"name": "Nginx Technology Detection", "severity": "info", "tags": "tech"},
            "matched-at": "https://app.example.com",
            "extracted-results": ["nginx"],
        },
    ]
    return "\n".join(json.dumps(row) for row in rows) + "\n"


def test_parse_nuclei_classification_rules(tmp_path: Path) -> None:
    raw = tmp_path / "nuclei-results.jsonl"
    output = tmp_path / "nuclei-findings.json"
    raw.write_text(nuclei_jsonl_fixture(), encoding="utf-8")

    run_tool("tools/parse-nuclei.py", "--input", str(raw), "--output", str(output))
    findings = json.loads(output.read_text(encoding="utf-8"))

    def has(title: str, severity: str, status: str, category: str) -> bool:
        return any(
            item["title"] == title
            and item["severity"] == severity
            and item["status"] == status
            and item["category"] == category
            for item in findings
        )

    assert has("TLS Version", "informational", "informational", "tls")
    assert has("Missing X-Frame-Options", "low", "observed", "headers")
    assert has("CORS Misconfiguration", "medium", "needs_review", "cors")
    assert has("Exposed Environment File", "high", "needs_review", "exposure")
    assert has("Nginx Technology Detection", "informational", "informational", "tech")
    assert len(findings) == 5


def test_parse_nuclei_empty_jsonl_output(tmp_path: Path) -> None:
    raw = tmp_path / "empty.jsonl"
    output = tmp_path / "nuclei-findings.json"
    raw.write_text("", encoding="utf-8")

    run_tool("tools/parse-nuclei.py", "--input", str(raw), "--output", str(output))

    assert json.loads(output.read_text(encoding="utf-8")) == []


def make_nuclei_workspace(tmp_path: Path, fake_nuclei: Path) -> Path:
    workspace = tmp_path / "nuclei-workspace"
    (workspace / "config").mkdir(parents=True)
    (workspace / "status").mkdir()
    (workspace / "evidence").mkdir()
    (workspace / "config" / "target.env").write_text(
        "\n".join(
            [
                'TARGET_BASE_URL="https://app.example.com"',
                'LOGIN_URL="https://app.example.com/login"',
                'TARGET_HOST="app.example.com"',
                'PROFILE="safe"',
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    (workspace / "config" / "tool-paths.env").write_text(f'NUCLEI_BIN="{fake_nuclei}"\n', encoding="utf-8")
    return workspace


def write_fake_nuclei(path: Path, help_mode: str = "jsonl-export") -> None:
    if help_mode == "jsonl-export":
        help_text = "  -jle, -jsonl-export string  export jsonl results to file\n  -j, -jsonl  write json lines\n"
    elif help_mode == "jsonl-o":
        help_text = "  -j, -jsonl  write json lines\n  -o string  output file\n"
    elif help_mode == "none":
        help_text = "  -silent  show only results\n"
    else:
        raise ValueError(f"unknown help mode: {help_mode}")
    path.write_text(
        """#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
__HELP_TEXT__EOF
  exit 0
fi
out=""
targets=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|-jsonl-export)
      out="$2"
      shift 2
      ;;
    -l)
      targets="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
[[ -n "${out}" ]] || exit 2
[[ -n "${targets}" && -f "${targets}" ]] || exit 3
printf 'fake nuclei scanning %s\n' "$(cat "${targets}")"
cat > "${out}" <<'EOF'
{"template-id":"missing-x-frame-options","info":{"name":"Missing X-Frame-Options","severity":"low","tags":"headers,misconfig"},"matched-at":"https://app.example.com","extracted-results":["X-Frame-Options header is missing"]}
{"template-id":"tech-detect:nginx","info":{"name":"Nginx Technology Detection","severity":"info","tags":"tech"},"matched-at":"https://app.example.com","extracted-results":["nginx"]}
EOF
""".replace("__HELP_TEXT__", help_text),
        encoding="utf-8",
    )
    path.chmod(0o755)


def run_nuclei_phase(workspace: Path, *extra: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", "phases/05-nuclei.sh", "--workspace", str(workspace), "--yes", *extra],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )


def run_nuclei_phase_unchecked(workspace: Path, *extra: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", "phases/05-nuclei.sh", "--workspace", str(workspace), "--yes", *extra],
        cwd=ROOT,
        check=False,
        text=True,
        capture_output=True,
    )


def test_phase_5_nuclei_mocked_rerun_and_clean(tmp_path: Path) -> None:
    fake_nuclei = tmp_path / "fake-nuclei"
    write_fake_nuclei(fake_nuclei)
    workspace = make_nuclei_workspace(tmp_path, fake_nuclei)

    first = run_nuclei_phase(workspace)
    assert "phase-5-nuclei starting" in first.stdout
    assert "monitor command: tail -f" in first.stdout
    evidence = workspace / "evidence" / "phase-5-nuclei"
    assert (evidence / "nuclei-targets-latest.txt").exists()
    assert (evidence / "nuclei-results-latest.jsonl").exists()
    assert (evidence / "nuclei-console-latest.txt").exists()
    assert (evidence / "nuclei-summary.md").exists()
    findings_path = evidence / "nuclei-findings.json"
    findings = json.loads(findings_path.read_text(encoding="utf-8"))
    assert any(item["title"] == "Missing X-Frame-Options" for item in findings)
    assert any(item["title"] == "Nginx Technology Detection" for item in findings)
    status_text = (workspace / "status" / "phase-5-nuclei.status").read_text(encoding="utf-8")
    assert "STATUS=success" in status_text
    assert "NUCLEI_JSON_MODE=jsonl-export" in status_text
    console_text = (evidence / "nuclei-console-latest.txt").read_text(encoding="utf-8")
    assert "Selected Nuclei JSONL output mode: jsonl-export" in console_text
    assert " -jsonl-export " in console_text
    assert "NUCLEI_JSON_MODE: jsonl-export" in (evidence / "nuclei-summary.md").read_text(encoding="utf-8")
    first_raw = sorted(evidence.glob("nuclei-results-[0-9]*T[0-9]*Z.jsonl"))
    assert len(first_raw) == 1

    run_nuclei_phase(workspace)
    second_raw = sorted(evidence.glob("nuclei-results-[0-9]*T[0-9]*Z.jsonl"))
    assert len(second_raw) >= 2

    run_nuclei_phase(workspace, "--clean")
    clean_raw = sorted(evidence.glob("nuclei-results-[0-9]*T[0-9]*Z.jsonl"))
    assert len(clean_raw) == 1
    assert (evidence / "nuclei-targets-latest.txt").exists()
    assert (evidence / "nuclei-results-latest.jsonl").exists()
    assert (evidence / "nuclei-console-latest.txt").exists()
    assert (evidence / "nuclei-summary.md").exists()
    assert (evidence / "nuclei-findings.json").exists()



def test_phase_5_nuclei_jsonl_dash_o_mode(tmp_path: Path) -> None:
    fake_nuclei = tmp_path / "fake-nuclei-jsonl-o"
    write_fake_nuclei(fake_nuclei, "jsonl-o")
    workspace = make_nuclei_workspace(tmp_path, fake_nuclei)

    run_nuclei_phase(workspace)

    evidence = workspace / "evidence" / "phase-5-nuclei"
    status_text = (workspace / "status" / "phase-5-nuclei.status").read_text(encoding="utf-8")
    console_text = (evidence / "nuclei-console-latest.txt").read_text(encoding="utf-8")
    summary_text = (evidence / "nuclei-summary.md").read_text(encoding="utf-8")
    assert "NUCLEI_JSON_MODE=jsonl-o" in status_text
    assert "Selected Nuclei JSONL output mode: jsonl-o" in console_text
    assert " -jsonl -o " in console_text
    assert "NUCLEI_JSON_MODE: jsonl-o" in summary_text
    assert (evidence / "nuclei-results-latest.jsonl").exists()


def test_phase_5_nuclei_missing_jsonl_support_fails(tmp_path: Path) -> None:
    fake_nuclei = tmp_path / "fake-nuclei-no-jsonl"
    write_fake_nuclei(fake_nuclei, "none")
    workspace = make_nuclei_workspace(tmp_path, fake_nuclei)

    result = run_nuclei_phase_unchecked(workspace)

    assert result.returncode != 0
    assert "Nuclei binary does not appear to support JSONL output required for Phase 5 parsing." in result.stderr
    evidence = workspace / "evidence" / "phase-5-nuclei"
    status_text = (workspace / "status" / "phase-5-nuclei.status").read_text(encoding="utf-8")
    console_text = next(evidence.glob("nuclei-console-[0-9]*T[0-9]*Z.txt")).read_text(encoding="utf-8")
    assert "STATUS=failure" in status_text
    assert "NUCLEI_JSON_MODE=" in status_text
    assert "Nuclei JSONL output mode detection failed" in console_text


def test_parse_zap_classification_and_deduplication(tmp_path: Path) -> None:
    alerts = tmp_path / "zap-alerts.json"
    output = tmp_path / "zap-findings.json"
    alerts.write_text(
        json.dumps(
            {
                "alerts": [
                    {
                        "alert": "Content Security Policy (CSP) Header Not Set / unsafe-inline",
                        "risk": "Medium",
                        "url": "https://app.example.com/login",
                        "evidence": "unsafe-inline",
                        "description": "CSP allows unsafe-inline and is missing form-action.",
                    },
                    {
                        "alert": "Content Security Policy (CSP) Header Not Set / unsafe-inline",
                        "risk": "Medium",
                        "url": "https://app.example.com/login",
                        "evidence": "unsafe-inline",
                        "description": "duplicate",
                    },
                    {
                        "alert": "X-Content-Type-Options Header Missing",
                        "risk": "Low",
                        "url": "https://app.example.com/login",
                        "evidence": "X-Content-Type-Options",
                    },
                    {
                        "alert": "Cookie No HttpOnly Flag",
                        "risk": "Low",
                        "url": "https://app.example.com/login",
                        "evidence": "sessionid",
                    },
                    {
                        "alert": "Modern Web Application",
                        "risk": "Informational",
                        "url": "https://app.example.com/login",
                        "evidence": "The application appears to be a modern web application.",
                    },
                ]
            }
        ),
        encoding="utf-8",
    )

    run_tool("tools/parse-zap.py", "--input", str(alerts), "--output", str(output))
    findings = json.loads(output.read_text(encoding="utf-8"))

    assert len(findings) == 4

    def has(title: str, severity: str, status: str, category: str) -> bool:
        return any(
            item["title"] == title
            and item["severity"] == severity
            and item["status"] == status
            and item["category"] == category
            for item in findings
        )

    assert has("Content Security Policy (CSP) Header Not Set / unsafe-inline", "medium", "needs_review", "csp")
    assert has("X-Content-Type-Options Header Missing", "low", "observed", "headers")
    assert has("Cookie No HttpOnly Flag", "low", "observed", "cookie")
    assert has("Modern Web Application", "informational", "informational", "misc")
