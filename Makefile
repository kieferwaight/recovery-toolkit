.PHONY: all install env symlinks cleanup-legacy-usb-links usb-preflight \
	usb-install usb-vault usb-ssh usb-tailscale usb-optimize usb-overlay \
	packages hooks check test

REPO_DIR := $(CURDIR)

all: install hooks

# Install only host-facing commands. USB changes use the explicit usb-* targets.
install: env symlinks cleanup-legacy-usb-links

env:
	@if [ ! -f .env ]; then \
		echo "==> Creating .env from .env.example"; \
		cp .env.example .env; \
	fi

symlinks:
	@echo "==> Making host command scripts executable..."
	@chmod +x bin/*
	@echo "==> Symlinking host commands into /usr/local/bin..."
	@repo_dir="$(REPO_DIR)"; \
		sudo install -d -m 0755 /usr/local/bin; \
		for script in bin/*; do \
		if [ -f "$$script" ]; then \
			name="$$(basename "$$script")"; \
			sudo ln -sfn "$$repo_dir/$$script" "/usr/local/bin/$$name"; \
			test -L "/usr/local/bin/$$name" && [ "$$(readlink "/usr/local/bin/$$name")" = "$$repo_dir/$$script" ]; \
			echo "Linked host command: /usr/local/bin/$$name"; \
		fi \
	 done

cleanup-legacy-usb-links:
	@repo_dir="$(REPO_DIR)"; \
		for name in optimize-usb setup-overlay-boot setup-ssh setup-tailscale setup-vault; do \
		link="/usr/local/bin/$$name"; \
		old="$$repo_dir/bin/$$name"; \
		if [ -L "$$link" ] && [ "$$(readlink "$$link")" = "$$old" ]; then \
			sudo rm -f "$$link"; \
			echo "Removed stale USB command link: $$link"; \
		fi; \
		done

# Print and validate the running USB/vault identity without changing either.
usb-preflight:
	@echo "==> Inspecting RECOVERY_DISK_UUID/RECOVERY_USB_ROOT_UUID and VAULT_UUID..."
	@sudo env RECOVERY_USB_MAKE_CONTEXT=1 RECOVERY_USB_MAKE_TARGET=$@ \
		bash "$(REPO_DIR)/scripts/usb/preflight"

define RUN_USB_SCRIPT
	@sudo env RECOVERY_USB_MAKE_CONTEXT=1 RECOVERY_USB_MAKE_TARGET=$@ \
		bash "$(REPO_DIR)/scripts/usb/$(1)"
endef

usb-install:
	$(call RUN_USB_SCRIPT,install-packages)

usb-vault:
	$(call RUN_USB_SCRIPT,setup-vault)

usb-ssh:
	$(call RUN_USB_SCRIPT,setup-ssh)

usb-tailscale:
	$(call RUN_USB_SCRIPT,setup-tailscale)

usb-optimize:
	$(call RUN_USB_SCRIPT,optimize-usb)

usb-overlay:
	$(call RUN_USB_SCRIPT,setup-overlay-boot)

# Compatibility spelling; it remains an explicit USB operation.
packages: usb-install

hooks:
	@echo "==> Installing shellcheck pre-commit hook..."
	@mkdir -p .git/hooks
	@printf '#!/usr/bin/env bash\nset -e\nmake check\nmake test\n' > .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit

check:
	@echo "==> Running shellcheck on shell scripts..."
	shellcheck -x -P lib bootstrap.sh bin/* lib/*.sh scripts/usb/*

test:
	@echo "==> Running tool boundary tests..."
	bash ./tests/test_tool_boundary.sh
	@echo "==> Running device guard tests..."
	bash ./tests/test_device_guard.sh
	@echo "==> Running setup command tests..."
	bash ./tests/test_setup_commands.sh
	@echo "==> Running recovery profile tests..."
	bash ./tests/test_recovery_profile.sh
	@echo "==> Running audit tests..."
	bash ./tests/test_audit.sh
	@echo "==> Running secure erase audit contract..."
	bash ./tests/test_secure_erase_audit.sh
	@echo "==> Running disk identity tests..."
	bash ./tests/test_disk_identity.sh
	@echo "==> Running provisioning profile tests..."
	bash ./tests/test_provision_luks.sh
	@echo "==> Running initramfs unlock tests..."
	bash ./tests/test_initramfs_unlock.sh
	@echo "==> Running Ubuntu installer tests..."
	bash ./tests/test_ubuntu_install.sh
