# Kali Preflight

Run `sudo ./install.sh` to validate baseline command availability. The installer does not upgrade Kali and does not install packages.

Run the assessment preflight before scanner phases:

```bash
./phases/00-preflight.sh --workspace assessments/<company>/<target>/<run-id>
```

Use `--yes` only when scope and authorization have already been confirmed:

```bash
./phases/00-preflight.sh --workspace assessments/<company>/<target>/<run-id> --yes
```

The preflight phase writes OS details, package health output, tool versions, DNS output, one low-impact login URL header request, a phase status file, and a Markdown summary under the selected workspace. It never runs package updates, package installs, broad scans, crawls, or intrusive checks.

Typical optional tools for future active phases:

- `openssl`
- `curl`
- `nikto`
- `nmap`
- `nuclei`
- `zaproxy`

Install missing tools through your approved Kali package process before enabling active assessment behavior.
