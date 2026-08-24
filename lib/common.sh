#!/usr/bin/env bash
set -euo pipefail

# Visual loggers
log_info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

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
