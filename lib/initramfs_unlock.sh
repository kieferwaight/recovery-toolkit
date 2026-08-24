#!/usr/bin/env bash

# Build a restricted Dropbear initramfs unlock configuration from the recovery
# profile. This stays pure shell so tests can verify the generated files without
# touching a running host.

# shellcheck source=recovery_profile.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/recovery_profile.sh"

load_initramfs_unlock_profile() {
  RECOVERY_UNLOCK_KEY="${RECOVERY_UNLOCK_KEY:-}"
  RECOVERY_UNLOCK_KEY_FINGERPRINT="${RECOVERY_UNLOCK_KEY_FINGERPRINT:-}"
  INITRAMFS_DROPBEAR_DIR="${INITRAMFS_DROPBEAR_DIR:-/etc/dropbear-initramfs}"
  INITRAMFS_DROPBEAR_CONFIG="${INITRAMFS_DROPBEAR_CONFIG:-${INITRAMFS_DROPBEAR_DIR}/config}"
  INITRAMFS_DROPBEAR_AUTH_KEYS="${INITRAMFS_DROPBEAR_AUTH_KEYS:-${INITRAMFS_DROPBEAR_DIR}/authorized_keys}"
  export RECOVERY_UNLOCK_KEY RECOVERY_UNLOCK_KEY_FINGERPRINT
  export INITRAMFS_DROPBEAR_DIR INITRAMFS_DROPBEAR_CONFIG INITRAMFS_DROPBEAR_AUTH_KEYS
}

validate_initramfs_unlock_profile() {
  load_recovery_profile
  load_initramfs_unlock_profile
  validate_recovery_profile || return 1
  [[ -n "${RECOVERY_UNLOCK_KEY}" ]] || return 1
  [[ -n "${RECOVERY_UNLOCK_KEY_FINGERPRINT}" ]] || return 1
  [[ -n "${RECOVERY_UNLOCK_KEY}" ]] || return 1
  [[ "${RECOVERY_UNLOCK_KEY}" != *$'\n'* ]] || return 1
  [[ "${RECOVERY_UNLOCK_KEY}" != *$'\r'* ]] || return 1
  [[ "${RECOVERY_UNLOCK_KEY_FINGERPRINT}" =~ ^[[:xdigit:]]{2}(:[[:xdigit:]]{2}){15}$|^[[:xdigit:]]{64}$ ]] || return 1
}

initramfs_unlock_dropbear_config() {
  cat <<EOF
DROPBEAR_OPTIONS="-p ${RECOVERY_HOST_IP}:${RECOVERY_SSH_PORT} -s -j -k -I 60"
EOF
}

initramfs_unlock_authorized_key() {
  local key="$1"
  printf '%s\n' \
    "command=\"cryptroot-unlock\",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty ${key}"
}
