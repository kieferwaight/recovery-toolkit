.PHONY: all install packages symlinks env check test hooks

all: install hooks

install: env packages symlinks

env:
	@if [ ! -f .env ]; then \
		echo "==> Creating .env from .env.example"; \
		cp .env.example .env; \
	fi

packages:
	./packages/setup-packages.sh

symlinks:
	@echo "==> Making bin/ scripts executable..."
	@chmod +x bin/*
	@echo "==> Symlinking executables into /usr/local/bin..."
	@repo_dir="$$(pwd)"; \
		sudo install -d -m 0755 /usr/local/bin; \
		for script in bin/*; do \
		if [ -f "$$script" ]; then \
			name="$$(basename "$$script")"; \
			sudo ln -sfn "$$repo_dir/$$script" "/usr/local/bin/$$name"; \
			test -L "/usr/local/bin/$$name" && [ "$$(readlink "/usr/local/bin/$$name")" = "$$repo_dir/$$script" ]; \
			echo "Linked: /usr/local/bin/$$name"; \
		fi \
	done

hooks:
	@echo "==> Installing shellcheck pre-commit hook..."
	@mkdir -p .git/hooks
	@printf '#!/usr/bin/env bash\nset -e\nmake check\n' > .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit

check:
	@echo "==> Running shellcheck on shell scripts..."
	shellcheck -x -P lib bin/* lib/*.sh packages/*.sh bootstrap.sh

test:
	@echo "==> Running setup command tests..."
	./tests/test_setup_commands.sh
	@echo "==> Running recovery profile tests..."
	./tests/test_recovery_profile.sh
	@echo "==> Running audit tests..."
	./tests/test_audit.sh
	@echo "==> Running secure erase audit contract..."
	./tests/test_secure_erase_audit.sh
