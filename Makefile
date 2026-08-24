.PHONY: all packages symlinks check test

all: packages symlinks

packages:
	./packages/setup-packages.sh

symlinks:
	@echo "==> Symlinking executables into /usr/local/bin..."
	@for script in bin/*; do \
		if [ -f "$$script" ]; then \
			sudo ln -sf "$$(pwd)/$$script" "/usr/local/bin/$$(basename $$script)"; \
			echo "Linked: /usr/local/bin/$$(basename $$script)"; \
		fi \
	done

check:
	@echo "==> Running shellcheck on shell scripts..."
	shellcheck bin/* lib/*.sh packages/*.sh
