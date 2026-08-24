.PHONY: all packages symlinks env check test hooks

all: env packages symlinks hooks

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
	@for script in bin/*; do \
		if [ -f "$$script" ]; then \
			sudo ln -sf "$$(pwd)/$$script" "/usr/local/bin/$$(basename $$script)"; \
			echo "Linked: /usr/local/bin/$$(basename $$script)"; \
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
