# Methodology

This runner is designed for repeatable, low-impact web application assessment workflows on Kali Linux.

Current implementation:

- Creates per-company, per-target, per-run workspaces.
- Keeps reusable framework code separate from engagement evidence.
- Writes all evidence, logs, reports, and status files under the selected workspace.
- Provides stub phases for TLS, headers, Nikto, Nmap, Nuclei, ZAP passive checks, validation, and authenticated testing.

Future active checks must preserve the safety model:

- No brute force, denial of service, race testing, fuzzing, or intrusive defaults.
- No broad port scanning by default.
- No credentials in logs or Git.
- Scanner output is reviewed evidence, not automatic confirmation.
