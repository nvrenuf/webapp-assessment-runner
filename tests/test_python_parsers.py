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
    for tool in ("parse-zap.py", "parse-nuclei.py"):
        output = tmp_path / f"{tool}.json"
        run_tool(f"tools/{tool}", "--output", str(output))
        assert json.loads(output.read_text(encoding="utf-8")) == {"findings": []}

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
                "+ Target URL: https://app.example.test/login",
                "+ The X-Content-Type-Options header is not present.",
                "+ Permissions-Policy header is not present.",
                "+ Referrer-Policy header is not present.",
                "+ Uncommon header 'Refresh' found, with contents: 0; url=/next",
                "+ Server banner changed from 'awselb/2.0' to 'private'",
                "+ SSL Certificate Subject Wildcard *.example.test",
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
        "login=https://app.example.test/login",
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
Nmap scan report for app.example.test (203.0.113.10)
Host is up (0.020s latency).
PORT    STATE SERVICE  VERSION
80/tcp  open  http     awselb/2.0
|_http-title: Did not follow redirect to https://app.example.test/
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
        "app.example.test",
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


def make_workspace(tmp_path: Path, fake_nmap: Path) -> Path:
    workspace = tmp_path / "workspace"
    (workspace / "config").mkdir(parents=True)
    (workspace / "status").mkdir()
    (workspace / "evidence").mkdir()
    (workspace / "config" / "target.env").write_text(
        '\n'.join(
            [
                'TARGET_BASE_URL="https://app.example.test"',
                'LOGIN_URL="https://app.example.test/login"',
                'TARGET_HOST="app.example.test"',
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
Nmap scan report for app.example.test (203.0.113.10)
Host is up (0.020s latency).
PORT    STATE SERVICE  VERSION
80/tcp  open  http     awselb/2.0
|_http-title: Did not follow redirect to https://app.example.test/
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
