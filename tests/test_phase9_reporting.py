import json
import subprocess
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def make_workspace(tmp_path: Path) -> Path:
    workspace = tmp_path / "workspace"
    (workspace / "config").mkdir(parents=True)
    (workspace / "status").mkdir()
    (workspace / "evidence" / "phase-2-headers").mkdir(parents=True)
    (workspace / "evidence" / "phase-3-nikto").mkdir(parents=True)
    (workspace / "evidence" / "phase-4-nmap").mkdir(parents=True)
    (workspace / "evidence" / "phase-5-nuclei").mkdir(parents=True)
    (workspace / "evidence" / "phase-6-zap").mkdir(parents=True)
    (workspace / "evidence" / "phase-7-validation").mkdir(parents=True)
    (workspace / "evidence" / "phase-8-authenticated").mkdir(parents=True)
    (workspace / "config" / "target.env").write_text(
        '\n'.join(
            [
                'TARGET_BASE_URL="https://app.example.com"',
                'TARGET_HOST="app.example.com"',
                'LOGIN_URL="https://app.example.com/login"',
                'PROFILE="safe"',
                'AUTH_MODE="none"',
                'AUTH_ENABLED="false"',
            ]
        )
        + '\n',
        encoding="utf-8",
    )
    (workspace / "config" / "metadata.json").write_text(
        json.dumps(
            {
                "company": "Example Company",
                "engagement": "Example engagement",
                "target": "https://app.example.com",
                "environment": "test",
                "profile": "safe",
                "auth_mode": "none",
                "auth_enabled": False,
                "tester": "Pytest",
                "run_id": "20260515T000000Z",
            }
        ),
        encoding="utf-8",
    )
    (workspace / "config" / "scope.yaml").write_text("target: https://app.example.com\n", encoding="utf-8")
    (workspace / "status" / "phase-7-validation.status").write_text("STATUS=success\nMESSAGE='ok'\n", encoding="utf-8")
    (workspace / "evidence" / "phase-7-validation" / "validation-login-headers-latest.txt").write_text("headers\n", encoding="utf-8")
    (workspace / "evidence" / "phase-7-validation" / "validation-summary.md").write_text("summary\n", encoding="utf-8")
    return workspace


def write_fixture_findings(workspace: Path) -> None:
    validation = [
        {
            "id": "VALIDATION-001",
            "title": "Permissive Content-Security-Policy",
            "severity": "medium",
            "status": "confirmed",
            "source": "phase-7-validation",
            "category": "csp",
            "url": "https://app.example.com/login",
            "evidence": "unsafe-inline, unsafe-eval, and missing form-action were observed.",
            "description": "CSP contains permissive directives.",
            "recommendation": "Tighten CSP directives.",
        },
        {
            "id": "VALIDATION-002",
            "title": "Missing recommended browser security headers",
            "severity": "low",
            "status": "confirmed",
            "source": "phase-7-validation",
            "category": "headers",
            "url": "https://app.example.com/login",
            "evidence": "X-Content-Type-Options, Referrer-Policy, and Permissions-Policy missing.",
            "description": "Browser hardening headers are missing.",
            "recommendation": "Add browser security headers.",
        },
        {
            "id": "VALIDATION-003",
            "title": "HSTS max-age below one-year hardening baseline",
            "severity": "low",
            "status": "confirmed",
            "source": "phase-7-validation",
            "category": "tls",
            "url": "https://app.example.com/login",
            "evidence": "strict-transport-security max-age=15768000.",
            "description": "HSTS max-age is below one year.",
            "recommendation": "Increase max-age after coverage review.",
        },
        {
            "id": "VALIDATION-004",
            "title": "CORS arbitrary origin reflection",
            "severity": "informational",
            "status": "not_observed",
            "source": "phase-7-validation",
            "category": "cors",
            "url": "https://app.example.com/login",
            "evidence": "https://evil.example.com was not reflected.",
            "description": "CORS reflection was not observed.",
            "recommendation": "Continue least privilege CORS.",
        },
        {
            "id": "VALIDATION-005",
            "title": "NULL/anonymous cipher support",
            "severity": "informational",
            "status": "not_confirmed",
            "source": "phase-7-validation",
            "category": "tls",
            "url": "https://app.example.com",
            "evidence": "NULL cipher was not negotiated.",
            "description": "NULL cipher support was not confirmed.",
            "recommendation": "Continue strong TLS configuration.",
        },
        {
            "id": "VALIDATION-006",
            "title": "Login cache protection",
            "severity": "informational",
            "status": "not_observed",
            "source": "phase-7-validation",
            "category": "cache",
            "url": "https://app.example.com/login",
            "evidence": "no-store observed; cache risk not observed.",
            "description": "Login cache risk was not observed.",
            "recommendation": "Continue no-store controls.",
        },
    ]
    (workspace / "evidence" / "phase-7-validation" / "validation-findings.json").write_text(json.dumps(validation), encoding="utf-8")
    (workspace / "evidence" / "phase-2-headers" / "headers-findings.json").write_text(
        json.dumps(
            [
                {"id": "HEADERS-001", "title": "Content-Security-Policy allows unsafe-inline", "severity": "medium", "status": "observed", "source": "phase-2-headers", "category": "csp"},
                {"id": "HEADERS-002", "title": "Missing Referrer-Policy", "severity": "low", "status": "observed", "source": "phase-2-headers", "category": "headers"},
            ]
        ),
        encoding="utf-8",
    )
    (workspace / "evidence" / "phase-3-nikto" / "nikto-findings.json").write_text(json.dumps([{"id": "NIKTO-001", "title": "The X-Content-Type-Options header is not present", "severity": "low", "status": "observed", "source": "phase-3-nikto", "category": "headers"}]), encoding="utf-8")
    (workspace / "evidence" / "phase-4-nmap" / "nmap-findings.json").write_text(json.dumps([{"id": "NMAP-001", "title": "HTTP security header missing", "severity": "low", "status": "observed", "source": "phase-4-nmap", "category": "headers"}]), encoding="utf-8")
    (workspace / "evidence" / "phase-5-nuclei" / "nuclei-findings.json").write_text(json.dumps([{"id": "NUCLEI-001", "title": "CSP unsafe-inline", "severity": "medium", "status": "observed", "source": "phase-5-nuclei", "category": "csp"}]), encoding="utf-8")
    (workspace / "evidence" / "phase-6-zap" / "zap-findings.json").write_text(json.dumps([{"id": "ZAP-001", "title": "CSP: script-src unsafe-inline", "severity": "medium", "status": "needs_review", "source": "phase-6-zap", "category": "csp"}]), encoding="utf-8")
    (workspace / "evidence" / "phase-8-authenticated" / "authenticated-findings.json").write_text(json.dumps([{"id": "AUTH-001", "title": "Authenticated testing not enabled", "severity": "informational", "status": "not_enabled", "source": "phase-8-authenticated", "category": "auth", "evidence": "AUTH_ENABLED=false"}]), encoding="utf-8")


def run_report(workspace: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", "phases/09-reporting.sh", "--workspace", str(workspace), "--yes", *args], cwd=ROOT, text=True, capture_output=True)


def test_phase9_normalizes_and_deduplicates_findings(tmp_path: Path) -> None:
    workspace = make_workspace(tmp_path)
    write_fixture_findings(workspace)
    result = run_report(workspace)
    assert result.returncode == 0, result.stderr + result.stdout

    finals = json.loads((workspace / "reports" / "findings-final.json").read_text(encoding="utf-8"))
    assert [item["title"] for item in finals] == [
        "Permissive Content-Security-Policy",
        "HSTS max-age below one-year hardening baseline",
        "Missing recommended browser security headers",
    ]
    assert [item["severity"] for item in finals] == ["medium", "low", "low"]
    csp = finals[0]
    related_titles = {item["title"] for item in csp["related_sources"]}
    assert "CSP: script-src unsafe-inline" in related_titles
    assert "CSP unsafe-inline" in related_titles
    assert all(item["title"] != "NULL/anonymous cipher support" for item in finals)
    assert all(item["title"] != "CORS arbitrary origin reflection" for item in finals)
    assert all(item["title"] != "Authenticated testing not enabled" for item in finals)
    tech = (workspace / "reports" / "technical-report.md").read_text(encoding="utf-8")
    assert "Authenticated testing was not completed" in tech
    source = json.loads((workspace / "evidence" / "phase-9-reporting" / "source-findings-latest.json").read_text(encoding="utf-8"))
    assert len(source["findings"]) >= 10
    index = json.loads((workspace / "reports" / "evidence-index.json").read_text(encoding="utf-8"))
    assert any(entry["relative_path"] == "reports/findings-final.json" and entry["sha256"] for entry in index)


def test_phase9_clean_removes_only_phase9_outputs(tmp_path: Path) -> None:
    workspace = make_workspace(tmp_path)
    write_fixture_findings(workspace)
    assert run_report(workspace).returncode == 0
    prior = workspace / "evidence" / "phase-7-validation" / "validation-findings.json"
    assert prior.exists()
    result = run_report(workspace, "--clean")
    assert result.returncode == 0, result.stderr + result.stdout
    assert prior.exists()
    assert (workspace / "reports" / "findings-final.json").exists()
    assert (workspace / "evidence" / "phase-9-reporting" / "normalization-notes-latest.md").exists()


def test_phase9_archive_excludes_secret_like_paths_and_reruns(tmp_path: Path) -> None:
    workspace = make_workspace(tmp_path)
    write_fixture_findings(workspace)
    (workspace / "config" / "auth.env").write_text("TOKEN=secret\n", encoding="utf-8")
    (workspace / "evidence" / "phase-8-authenticated" / "session-token.txt").write_text("secret\n", encoding="utf-8")
    (workspace / "evidence" / "phase-8-authenticated" / "browser.har").write_text("har\n", encoding="utf-8")
    (workspace / "evidence" / "phase-8-authenticated" / "cookie-jar.txt").write_text("cookie\n", encoding="utf-8")
    assert run_report(workspace, "--archive").returncode == 0
    second = run_report(workspace, "--archive")
    assert second.returncode == 0, second.stderr + second.stdout
    archives = sorted((workspace / "reports").glob("evidence-package-*.tar.gz"))
    assert archives
    with tarfile.open(archives[-1], "r:gz") as tar:
        names = set(tar.getnames())
    assert "config/metadata.json" in names
    assert "config/scope.yaml" in names
    assert "config/auth.env" not in names
    assert not any("token" in name.lower() or "cookie" in name.lower() or name.lower().endswith(".har") for name in names)
    manifest = json.loads((workspace / "reports" / "archive-manifest-latest.json").read_text(encoding="utf-8"))
    assert "config/auth.env" not in {item["relative_path"] for item in manifest["included"]}


def test_phase9_includes_client_intake_metadata_when_present(tmp_path: Path) -> None:
    workspace = make_workspace(tmp_path)
    write_fixture_findings(workspace)
    (workspace / "config" / "client-intake.yaml").write_text(
        """
engagement:
  client_name: Example Company Reviewed
  engagement_name: Reviewed engagement
  assessment_type: low-impact assessment
  business_owner: Business Owner
  technical_contact: tech@example.com
  security_contact: security@example.com
  report_recipient: reports@example.com
scope:
  target_base_url: https://www.example.com
  testing_window: Weekdays 09:00-17:00 UTC
  rate_limits_or_traffic_constraints: Keep requests low impact
authorization:
  authorization_reference: AUTH-EXAMPLE-001
  authorized_by: Authorized Person
  allowed_testing_types: passive review and low-impact validation
  prohibited_testing_types: destructive testing
authenticated_testing:
  credentials_available: false
  role_testing_required: false
reporting:
  report_classification: Example Confidential
  delivery_format: Markdown
  due_date: 2026-01-10
""".lstrip(),
        encoding="utf-8",
    )

    result = run_report(workspace)
    assert result.returncode == 0, result.stderr + result.stdout

    metadata = json.loads((workspace / "reports" / "report-metadata.json").read_text(encoding="utf-8"))
    intake = metadata["client_intake"]
    assert intake["found"] is True
    assert intake["placeholder_only"] is False
    assert intake["sections"]["engagement"]["client_name"] == "Example Company Reviewed"
    executive = (workspace / "reports" / "executive-summary.md").read_text(encoding="utf-8")
    technical = (workspace / "reports" / "technical-report.md").read_text(encoding="utf-8")
    assert "Example Company Reviewed" in executive
    assert "AUTH-EXAMPLE-001" in technical
    summary = (workspace / "reports" / "report-summary.md").read_text(encoding="utf-8")
    assert "Client intake found: true" in summary
    assert "Client intake appears placeholder-only: false" in summary


def test_phase9_does_not_fail_when_client_intake_missing(tmp_path: Path) -> None:
    workspace = make_workspace(tmp_path)
    write_fixture_findings(workspace)
    (workspace / "config" / "client-intake.yaml").unlink(missing_ok=True)

    result = run_report(workspace)
    assert result.returncode == 0, result.stderr + result.stdout

    metadata = json.loads((workspace / "reports" / "report-metadata.json").read_text(encoding="utf-8"))
    assert metadata["client_intake"]["found"] is False
    summary = (workspace / "reports" / "report-summary.md").read_text(encoding="utf-8")
    assert "Client intake found: false" in summary


def test_phase9_placeholder_client_intake_is_nonfatal(tmp_path: Path) -> None:
    workspace = make_workspace(tmp_path)
    write_fixture_findings(workspace)
    template = ROOT / "templates" / "client-intake.yaml.example"
    (workspace / "config" / "client-intake.yaml").write_text(template.read_text(encoding="utf-8"), encoding="utf-8")

    result = run_report(workspace)
    assert result.returncode == 0, result.stderr + result.stdout

    metadata = json.loads((workspace / "reports" / "report-metadata.json").read_text(encoding="utf-8"))
    assert metadata["client_intake"]["found"] is True
    assert metadata["client_intake"]["placeholder_only"] is True
    summary = (workspace / "reports" / "report-summary.md").read_text(encoding="utf-8")
    assert "Client intake appears placeholder-only: true" in summary
