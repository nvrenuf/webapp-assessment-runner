import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def make_workspace(tmp_path: Path, extra_config: str = "") -> Path:
    workspace = tmp_path / "workspace"
    (workspace / "config").mkdir(parents=True)
    (workspace / "status").mkdir()
    (workspace / "evidence" / "phase-6-zap").mkdir(parents=True)
    (workspace / "config" / "target.env").write_text(
        "\n".join(
            [
                'TARGET_BASE_URL="https://app.example.com"',
                'TARGET_HOST="app.example.com"',
                'LOGIN_URL="https://app.example.com/login"',
                'PROFILE="test-zap-no-profile"',
                'AUTH_ENABLED="false"',
            ]
        )
        + "\n"
        + extra_config
        + "\n",
        encoding="utf-8",
    )
    return workspace


def run_phase(workspace: Path, *args: str) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["PYTHON_BIN"] = env.get("PYTHON_BIN", "python3")
    return subprocess.run(
        ["bash", "phases/06-zap-passive.sh", "--workspace", str(workspace), *args],
        cwd=ROOT,
        text=True,
        capture_output=True,
        env=env,
    )


def test_zap_clean_removes_phase_6_outputs(tmp_path: Path) -> None:
    workspace = make_workspace(tmp_path, "ZAP_ACTIVE_SCAN=true")
    out = workspace / "evidence" / "phase-6-zap"
    for name in [
        "zap-daemon-console-20260515T000000Z.txt",
        "zap-version-latest.json",
        "zap-summary.md",
        "zap-findings.json",
    ]:
        (out / name).write_text("old", encoding="utf-8")
    pid = workspace / "status" / "phase-6-zap.pid"
    pid.write_text("999999", encoding="utf-8")

    result = run_phase(workspace, "--clean")

    assert result.returncode != 0
    assert "ZAP active scan is not implemented or allowed in Phase 6" in result.stderr
    assert not any((out / name).exists() for name in ["zap-daemon-console-20260515T000000Z.txt", "zap-version-latest.json", "zap-summary.md", "zap-findings.json"])
    assert not pid.exists()


def test_zap_active_scan_enabled_fails_clearly(tmp_path: Path) -> None:
    workspace = make_workspace(tmp_path, "ZAP_ACTIVE_SCAN=true")
    result = run_phase(workspace)
    assert result.returncode != 0
    assert "ZAP active scan is not implemented or allowed in Phase 6" in result.stderr


def test_zap_ajax_spider_enabled_fails_clearly(tmp_path: Path) -> None:
    workspace = make_workspace(tmp_path, "ZAP_AJAX_SPIDER=true")
    result = run_phase(workspace)
    assert result.returncode != 0
    assert "ZAP AJAX spider is reserved for a later authenticated/deep implementation" in result.stderr
