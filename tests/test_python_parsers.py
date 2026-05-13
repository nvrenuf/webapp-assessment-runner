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
    for tool in ("parse-zap.py", "parse-nikto.py", "parse-nmap.py", "parse-nuclei.py"):
        output = tmp_path / f"{tool}.json"
        run_tool(f"tools/{tool}", "--output", str(output))
        assert json.loads(output.read_text(encoding="utf-8")) == {"findings": []}


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
