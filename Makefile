.PHONY: test shell-syntax python-check

SHELL_SCRIPTS := install.sh init-assessment.sh assess.sh status.sh report.sh $(wildcard phases/*.sh) $(wildcard lib/*.sh)
PYTHON_TOOLS := $(wildcard tools/*.py)

test: shell-syntax python-check
	bash tests/test_shell_syntax.sh
	pytest

shell-syntax:
	bash -n $(SHELL_SCRIPTS)

python-check:
	python3 -m py_compile $(PYTHON_TOOLS)
