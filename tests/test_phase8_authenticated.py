import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def make_workspace(tmp_path: Path, auth_mode: str = "none", auth_enabled: str = "false") -> Path:
    workspace = tmp_path / "workspace"
    (workspace / "config").mkdir(parents=True)
    (workspace / "status").mkdir()
    (workspace / "config" / "target.env").write_text(
        "\n".join(
            [
                'TARGET_BASE_URL="https://app.example.com"',
                'TARGET_HOST="app.example.com"',
                'LOGIN_URL="https://app.example.com/login"',
                'PROFILE="test-phase8-no-profile"',
                f'AUTH_MODE="{auth_mode}"',
                f'AUTH_ENABLED="{auth_enabled}"',
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    return workspace


def write_placeholder_auth_env(workspace: Path) -> None:
    (workspace / "config" / "auth.env").write_text(
        "\n".join(
            [
                'AUTH_LOGIN_METHOD="manual|cookie|header|browser|future"',
                'AUTH_USERNAME_PLACEHOLDER="required"',
                'AUTH_PASSWORD_PLACEHOLDER="required"',
                'AUTH_TEST_USER_1="placeholder"',
                'AUTH_TEST_USER_2="placeholder"',
                'AUTH_TEST_TENANT_1="placeholder"',
                'AUTH_TEST_TENANT_2="placeholder"',
                'AUTH_SESSION_COOKIE_PLACEHOLDER="placeholder"',
                'AUTH_CSRF_TOKEN_PLACEHOLDER="placeholder"',
                'AUTH_BEARER_TOKEN_PLACEHOLDER="placeholder"',
                'AUTH_NOTES="placeholder only; do not store real secrets"',
            ]
        )
        + "\n",
        encoding="utf-8",
    )


def run_phase(workspace: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", "phases/08-authenticated.sh", "--workspace", str(workspace), *args],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )


def load_readiness(workspace: Path) -> dict:
    path = workspace / "evidence" / "phase-8-authenticated" / "auth-readiness-latest.json"
    return json.loads(path.read_text(encoding="utf-8"))


def load_findings(workspace: Path) -> list[dict[str, str]]:
    path = workspace / "evidence" / "phase-8-authenticated" / "authenticated-findings.json"
    return json.loads(path.read_text(encoding="utf-8"))


def test_phase8_auth_none_creates_not_enabled_readiness_and_finding(tmp_path: Path) -> None:
    workspace = make_workspace(tmp_path, auth_mode="none", auth_enabled="false")

    result = run_phase(workspace)

    assert result.returncode == 0, result.stderr + result.stdout
    readiness = load_readiness(workspace)
    assert readiness["readiness"] == "not_enabled"
    findings = load_findings(workspace)
    assert findings[0]["title"] == "Authenticated testing not enabled"
    assert findings[0]["severity"] == "informational"
    assert findings[0]["status"] == "not_enabled"
    status = (workspace / "status" / "phase-8-authenticated.status").read_text(encoding="utf-8")
    assert "STATUS=success" in status
    assert "AUTH_READINESS=not_enabled" in status


def test_phase8_placeholder_missing_auth_env_creates_needs_input_finding(tmp_path: Path) -> None:
    workspace = make_workspace(tmp_path, auth_mode="placeholder", auth_enabled="true")

    result = run_phase(workspace)

    assert result.returncode == 0, result.stderr + result.stdout
    readiness = load_readiness(workspace)
    assert readiness["readiness"] == "missing_auth_env"
    findings = load_findings(workspace)
    assert findings[0]["title"] == "Authenticated testing configuration missing"
    assert findings[0]["severity"] == "low"
    assert findings[0]["status"] == "needs_input"


def test_phase8_placeholder_auth_env_creates_placeholder_ready(tmp_path: Path) -> None:
    workspace = make_workspace(tmp_path, auth_mode="placeholder", auth_enabled="true")
    write_placeholder_auth_env(workspace)

    result = run_phase(workspace, "--verbose")

    assert result.returncode == 0, result.stderr + result.stdout
    readiness = load_readiness(workspace)
    assert readiness["readiness"] == "placeholder_ready"
    findings = load_findings(workspace)
    assert findings[0]["title"] == "Authenticated testing scaffold ready"
    assert findings[0]["severity"] == "informational"
    assert findings[0]["status"] == "observed"
    assert (workspace / "evidence" / "phase-8-authenticated" / "auth-checklist-latest.md").exists()
    assert (workspace / "evidence" / "phase-8-authenticated" / "auth-notes-latest.md").exists()


def test_phase8_possible_real_secret_lists_names_only_never_values(tmp_path: Path) -> None:
    workspace = make_workspace(tmp_path, auth_mode="placeholder", auth_enabled="true")
    secret_value = "a" * 64
    write_placeholder_auth_env(workspace)
    with (workspace / "config" / "auth.env").open("a", encoding="utf-8") as auth_env:
        auth_env.write(f'AUTH_CUSTOM_HEADER="{secret_value}"\n')

    result = run_phase(workspace)

    assert result.returncode == 0, result.stderr + result.stdout
    readiness = load_readiness(workspace)
    assert readiness["readiness"] == "unsafe_secret_detected"
    assert readiness["warning_variables"] == ["AUTH_CUSTOM_HEADER"]
    findings_text = (workspace / "evidence" / "phase-8-authenticated" / "authenticated-findings.json").read_text(
        encoding="utf-8"
    )
    summary_text = (workspace / "evidence" / "phase-8-authenticated" / "authenticated-summary.md").read_text(
        encoding="utf-8"
    )
    console_text = (workspace / "evidence" / "phase-8-authenticated" / "auth-console-latest.txt").read_text(
        encoding="utf-8"
    )
    assert "AUTH_CUSTOM_HEADER" in findings_text
    assert secret_value not in findings_text
    assert secret_value not in summary_text
    assert secret_value not in console_text


def test_phase8_clean_removes_outputs_and_rerun_succeeds(tmp_path: Path) -> None:
    workspace = make_workspace(tmp_path, auth_mode="placeholder", auth_enabled="true")
    write_placeholder_auth_env(workspace)
    out = workspace / "evidence" / "phase-8-authenticated"
    out.mkdir(parents=True)
    for name in [
        "auth-readiness-20260515T000000Z.json",
        "auth-checklist-20260515T000000Z.md",
        "auth-notes-20260515T000000Z.md",
        "auth-console-20260515T000000Z.txt",
        "auth-readiness-latest.json",
        "auth-checklist-latest.md",
        "auth-notes-latest.md",
        "auth-console-latest.txt",
        "authenticated-summary.md",
        "authenticated-findings.json",
    ]:
        (out / name).write_text("old", encoding="utf-8")

    first = run_phase(workspace, "--clean")
    second = run_phase(workspace)

    assert first.returncode == 0, first.stderr + first.stdout
    assert second.returncode == 0, second.stderr + second.stdout
    assert not (out / "auth-readiness-20260515T000000Z.json").exists()
    assert not (out / "auth-checklist-20260515T000000Z.md").exists()
    assert not (out / "auth-notes-20260515T000000Z.md").exists()
    assert (out / "authenticated-findings.json").exists()
    assert (out / "auth-console-latest.txt").read_text(encoding="utf-8") != "old"
