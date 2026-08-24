#!/usr/bin/env bash
# Bootstraps a fresh Ubuntu install onto the recovery USB.
# Intended to be run with: curl -fsSL https://raw.githubusercontent.com/kieferwaight/recovery-toolkit/main/bootstrap.sh | sudo bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "[-] bootstrap.sh must be run as root (re-run with sudo)." >&2
  exit 1
fi

REPO_URL="https://github.com/kieferwaight/recovery-toolkit.git"
export INSTALL_DIR="/opt/recovery-toolkit"
REAL_USER="${SUDO_USER:-${USER}}"

# Keep debconf from popping up keyboard-layout / service-restart prompts.
export DEBIAN_FRONTEND=noninteractive

# Update mirrors and grab core dev tools
apt-get update && apt-get upgrade -y
apt-get install -y --no-install-recommends \
  git curl make tree jq shellcheck glow

# Setup dir
mkdir -p "${INSTALL_DIR}"
groupadd -f -r toolkit
usermod -aG toolkit "${REAL_USER}"
chown -R root:toolkit "${INSTALL_DIR}"
chmod -R u=rwX,g=rwX,o=rX "${INSTALL_DIR}"
find "${INSTALL_DIR}" -type d -exec chmod g+s {} +

# Configure Git
sudo -u "${REAL_USER}" git config --global user.name "Kiefer Waight"
sudo -u "${REAL_USER}" git config --global user.email "kwaight@users.noreply.github.com"
sudo -u "${REAL_USER}" git config --global init.defaultBranch main
git config --global --add safe.directory "${INSTALL_DIR}"

if [[ -d "${INSTALL_DIR}/.git" ]]; then
  if git -C "${INSTALL_DIR}" remote get-url origin >/dev/null 2>&1; then
    git -C "${INSTALL_DIR}" remote set-url origin "${REPO_URL}"
  else
    git -C "${INSTALL_DIR}" remote add origin "${REPO_URL}"
  fi
  git -C "${INSTALL_DIR}" pull --ff-only
else
  git clone "${REPO_URL}" "${INSTALL_DIR}"
fi
chown -R root:toolkit "${INSTALL_DIR}"

cd "${INSTALL_DIR}"

# Generate .env from the example on first run, then make everything executable.
if [[ ! -f .env && -f .env.example ]]; then
  cp .env.example .env
fi
chmod +x bootstrap.sh bin/*

make install
make usb-install
