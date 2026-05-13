# Troubleshooting

## Workspace Missing

Run `./init-assessment.sh` first and pass the generated path to `--workspace`.

## Permission Errors

Assessment phases should not require root. If a phase asks for root, treat that as a bug unless it is `install.sh`.

## Empty Reports

The foundation uses parser and report stubs. Empty normalized findings are expected until active parsers and evidence inputs are added.

## Secrets

Never paste credentials into terminal output, logs, reports, examples, or Git-tracked files.
