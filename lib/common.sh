#!/usr/bin/env bash
set -euo pipefail

# Resolve the repo root regardless of which script sourced this file.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${REPO_ROOT}/data/logs"

# Load ${REPO_ROOT}/.env, generating it from .env.example on first run.
load_env() {
  local env_file="${REPO_ROOT}/.env"
  local env_example="${REPO_ROOT}/.env.example"

  if [[ ! -f "${env_file}" && -f "${env_example}" ]]; then
    cp "${env_example}" "${env_file}"
  fi

  if [[ -f "${env_file}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${env_file}"
    set +a
  fi
}

# Visual loggers. When invoked from a script name, also append to an
# auditable per-script log file under data/logs/ for later review.
_log_script_name() { basename "${0:-toolkit}"; }

_log_to_file() {
  mkdir -p "${LOG_DIR}"
  local log_file
  log_file="${LOG_DIR}/$(_log_script_name).log"
  echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $*" >> "${log_file}"
}

log_info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; _log_to_file "[INFO] $*"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; _log_to_file "[WARN] $*"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; _log_to_file "[ERROR] $*"; }

# Guard: Ensure root privileges
require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log_error "This script must be executed with sudo/root privileges."
    exit 1
  fi
}

# Guard: Identify USB root disk and refuse execution against it
assert_not_boot_disk() {
  local target="$1"
  
  # Resolve symlinks (e.g., /dev/disk/by-id/...)
  local real_target
  real_target="$(readlink -f "${target}")"

  # Find the underlying parent disk for the current root filesystem
  local root_src
  root_src="$(findmnt -n -o SOURCE /)"
  local boot_disk
  boot_disk="/dev/$(lsblk -no pkname "${root_src}" | head -n 1)"

  if [[ -z "${boot_disk}" || "${boot_disk}" == "/dev/" ]]; then
    # Fallback if root is directly on a non-partitioned block
    boot_disk="${root_src}"
  fi

  if [[ "${real_target}" == "${boot_disk}"* ]]; then
    log_error "Safety violation: Target ${real_target} is the active boot USB (${boot_disk})!"
    exit 2
  fi
}

# Guard: Explicit destructive prompt
confirm_destructive() {
  local target="$1"
  local prompt_word="NUKE"

  log_warn "Target disk: ${target}"
  lsblk "${target}" || true
  echo ""
  read -rp "Type '${prompt_word}' to permanently destroy all data on ${target}: " response
  if [[ "${response}" != "${prompt_word}" ]]; then
    log_info "Operation canceled by user."
    exit 0
  fi
}

# Guard: Ensure the target block device actually exists
assert_block_device() {
  local target="$1"
  if [[ ! -b "${target}" ]]; then
    log_error "Target ${target} is not a valid block device."
    exit 1
  fi
}

# Report whether a disk is rotational (1) or flash-based (0)
is_rotational() {
  local target="$1"
  local base
  base="$(basename "$(readlink -f "${target}")")"
  base="$(lsblk -no pkname "/dev/${base}" 2>/dev/null || echo "${base}")"
  cat "/sys/block/${base}/queue/rotational" 2>/dev/null || echo 1
}

