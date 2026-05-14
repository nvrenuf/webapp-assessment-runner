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
    for tool in ("parse-zap.py", "parse-nmap.py", "parse-nuclei.py"):
        output = tmp_path / f"{tool}.json"
        run_tool(f"tools/{tool}", "--output", str(output))
        assert json.loads(output.read_text(encoding="utf-8")) == {"findings": []}


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
