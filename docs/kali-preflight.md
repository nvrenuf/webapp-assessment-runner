# Kali Preflight

Run `./install.sh --check-only` to validate baseline command availability without modifying the system:

```bash
./install.sh --check-only
```

Run `sudo ./install.sh --install-deps` to install missing apt packages where possible:

```bash
sudo ./install.sh --install-deps
```

The installer does not run `apt update`, `apt upgrade`, or `apt full-upgrade`.

Run the assessment preflight before scanner phases:

```bash
./phases/00-preflight.sh --workspace assessments/<company>/<target>/<run-id>
```

Use `--yes` only when scope and authorization have already been confirmed:

```bash
./phases/00-preflight.sh --workspace assessments/<company>/<target>/<run-id> --yes
```

The preflight phase writes OS details, package health output, tool versions, DNS output, one low-impact login URL header request, a phase status file, and a Markdown summary under the selected workspace. It never runs package updates, package installs, broad scans, crawls, or intrusive checks.

Required tools:

- `bash`
- `curl`
- `openssl`
- `nmap`
- `nikto`
- `nuclei`
- `jq`
- `python3`

Flexible tools:

- `testssl` or `testssl.sh`
- `zaproxy`
- `/usr/share/zaproxy/zap.sh`
- `owasp-zap`

Install missing tools through your approved Kali package process before enabling active assessment behavior.
