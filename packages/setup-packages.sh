#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_FILE="${SCRIPT_DIR}/base.apt.list"

echo "==> Updating package indices..."
sudo apt-get update

echo "==> Installing rescue tools from ${PACKAGE_FILE}..."
grep -vE '^\s*#' "${PACKAGE_FILE}" | grep -v '^\s*$' | tr '\n' ' ' | xargs sudo apt-get install -y --no-install-recommends

echo "==> Package installation complete."
