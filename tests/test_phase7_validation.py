import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def make_workspace(tmp_path: Path, fakebin: Path) -> Path:
    workspace = tmp_path / "workspace"
    (workspace / "config").mkdir(parents=True)
    (workspace / "status").mkdir()
    (workspace / "config" / "target.env").write_text(
        "\n".join(
            [
                'TARGET_BASE_URL="https://app.example.test"',
                'TARGET_HOST="app.example.test"',
                'LOGIN_URL="https://app.example.test/login"',
                'PROFILE="test-phase7-no-profile"',
                'AUTH_ENABLED="false"',
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    (workspace / "config" / "tool-paths.env").write_text(
        f'CURL_BIN="{fakebin / "curl"}"\nOPENSSL_BIN="{fakebin / "openssl"}"\n',
        encoding="utf-8",
    )
    return workspace


def write_fake_tools(fakebin: Path) -> None:
    fakebin.mkdir()
    (fakebin / "curl").write_text(
        r'''#!/usr/bin/env bash
set -Eeuo pipefail
headers_file=""
body_file=""
head_only="false"
origin=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -D) headers_file="$2"; shift 2 ;;
    -o) body_file="$2"; shift 2 ;;
    -I|-IL|-LI) head_only="true"; shift ;;
    -H) origin="$2"; shift 2 ;;
    --max-time) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
if [[ "${head_only}" == "true" ]]; then
  printf 'HTTP/2 301\r\nlocation: https://app.example.test/login\r\n\r\nHTTP/2 200\r\ncontent-type: text/html\r\n\r\n'
  exit 0
fi
if [[ -n "${headers_file}" ]]; then
  {
    printf 'HTTP/2 200\r\n'
    printf "content-security-policy: default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; base-uri 'self'; object-src 'none'\r\n"
    printf 'strict-transport-security: max-age=15768000; includeSubDomains\r\n'
    printf 'cache-control: no-store\r\n'
    printf 'x-frame-options: DENY\r\n'
    printf 'vary: Origin\r\n'
    if [[ "${origin}" == "Origin: https://evil.example" ]]; then
      printf 'access-control-allow-origin: https://trusted.example\r\n'
      printf 'access-control-allow-credentials: true\r\n'
    fi
    printf '\r\n'
  } > "${headers_file}"
fi
if [[ -n "${body_file}" && "${body_file}" != "/dev/null" ]]; then
  printf '<html>login</html>\n' > "${body_file}"
fi
''',
        encoding="utf-8",
    )
    (fakebin / "openssl").write_text(
        r'''#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${1:-}" == "s_client" ]]; then
  args=" $* "
  if [[ "${args}" == *" -tls1_3 "* ]]; then
    printf 'New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384\n'
    printf '    Cipher    : TLS_AES_256_GCM_SHA384\n'
  elif [[ "${args}" == *"NULL:eNULL:aNULL"* ]]; then
    printf 'New, (NONE), Cipher is (NONE)\n'
  else
    printf 'New, TLSv1.2, Cipher is ECDHE-RSA-AES128-GCM-SHA256\n'
    printf '    Cipher    : ECDHE-RSA-AES128-GCM-SHA256\n'
  fi
  exit 0
fi
exit 0
''',
        encoding="utf-8",
    )
    os.chmod(fakebin / "curl", 0o755)
    os.chmod(fakebin / "openssl", 0o755)


def run_phase(workspace: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", "phases/07-validation.sh", "--workspace", str(workspace), *args],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )


def load_findings(workspace: Path) -> list[dict[str, str]]:
    path = workspace / "evidence" / "phase-7-validation" / "validation-findings.json"
    return json.loads(path.read_text(encoding="utf-8"))


def finding(findings: list[dict[str, str]], title: str) -> dict[str, str]:
    return next(item for item in findings if item["title"] == title)


def test_phase7_groups_direct_validation_findings(tmp_path: Path) -> None:
    fakebin = tmp_path / "fakebin"
    write_fake_tools(fakebin)
    workspace = make_workspace(tmp_path, fakebin)

    result = run_phase(workspace, "--yes", "--verbose")

    assert result.returncode == 0, result.stderr + result.stdout
    findings = load_findings(workspace)

    csp = finding(findings, "Permissive Content-Security-Policy")
    assert csp["severity"] == "medium"
    assert csp["status"] == "confirmed"
    assert "unsafe-inline" in csp["evidence"]
    assert "unsafe-eval" in csp["evidence"]
    assert "form-action directive is missing" in csp["evidence"]

    headers = finding(findings, "Missing recommended browser security headers")
    assert headers["severity"] == "low"
    assert headers["status"] == "confirmed"
    assert "X-Content-Type-Options" in headers["evidence"]
    assert "Referrer-Policy" in headers["evidence"]
    assert "Permissions-Policy" in headers["evidence"]

    cors = finding(findings, "CORS arbitrary origin reflection")
    assert cors["severity"] == "informational"
    assert cors["status"] == "not_observed"
    assert "https://evil.example was not reflected" in cors["evidence"]

    hsts = finding(findings, "HSTS max-age below one-year hardening baseline")
    assert hsts["severity"] == "low"
    assert hsts["status"] == "confirmed"
    assert "15768000" in hsts["evidence"]

    cache = finding(findings, "Login cache protection")
    assert cache["severity"] == "informational"
    assert cache["status"] == "not_observed"
    assert not any(item["category"] == "cache" and item["severity"] == "medium" for item in findings)

    null_cipher = finding(findings, "NULL/anonymous cipher support")
    assert null_cipher["severity"] == "informational"
    assert null_cipher["status"] == "not_confirmed"
    assert "Cipher is (NONE)" in null_cipher["evidence"]

    assert (workspace / "evidence" / "phase-7-validation" / "validation-summary.md").exists()
    assert (workspace / "evidence" / "phase-7-validation" / "validation-login-headers-latest.txt").exists()
    status = (workspace / "status" / "phase-7-validation.status").read_text(encoding="utf-8")
    assert "STATUS=success" in status
    assert "PHASE_RUN_ID=" in status


def test_phase7_clean_removes_outputs_and_rerun_succeeds(tmp_path: Path) -> None:
    fakebin = tmp_path / "fakebin"
    write_fake_tools(fakebin)
    workspace = make_workspace(tmp_path, fakebin)
    out = workspace / "evidence" / "phase-7-validation"
    out.mkdir(parents=True)
    for name in [
        "validation-login-headers-20260515T000000Z.txt",
        "validation-console-latest.txt",
        "validation-summary.md",
        "validation-findings.json",
    ]:
        (out / name).write_text("old", encoding="utf-8")

    first = run_phase(workspace, "--clean")
    second = run_phase(workspace)

    assert first.returncode == 0, first.stderr + first.stdout
    assert second.returncode == 0, second.stderr + second.stdout
    assert not (out / "validation-login-headers-20260515T000000Z.txt").exists()
    assert (out / "validation-findings.json").exists()
    assert (out / "validation-console-latest.txt").read_text(encoding="utf-8") != "old"
