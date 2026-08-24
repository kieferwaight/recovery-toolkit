#!/usr/bin/env bash

# Build a restricted Dropbear initramfs unlock configuration from the recovery
# profile. This stays pure shell so tests can verify the generated files without
# touching a running host.

# shellcheck source=recovery_profile.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/recovery_profile.sh"

if ! declare -F assert_target_root_is_safe >/dev/null 2>&1; then
  # shellcheck source=device_guard.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/device_guard.sh"
fi

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

initramfs_unlock_target_paths() {
  local target_root="$1"
  load_initramfs_unlock_profile
  [[ "${INITRAMFS_DROPBEAR_DIR}" == /* && "${INITRAMFS_DROPBEAR_DIR}" != *$'\n'* ]] || {
    log_error 'Initramfs Dropbear directory must be an absolute path without newlines.'
    return 1
  }
  assert_target_root_is_safe "${target_root}" || return $?
  TARGET_ROOT="${target_root%/}"
  TARGET_INITRAMFS_DROPBEAR_DIR="${TARGET_ROOT}${INITRAMFS_DROPBEAR_DIR}"
  TARGET_INITRAMFS_DROPBEAR_CONFIG="${TARGET_ROOT}${INITRAMFS_DROPBEAR_CONFIG}"
  TARGET_INITRAMFS_DROPBEAR_AUTH_KEYS="${TARGET_ROOT}${INITRAMFS_DROPBEAR_AUTH_KEYS}"
  export TARGET_ROOT TARGET_INITRAMFS_DROPBEAR_DIR
  export TARGET_INITRAMFS_DROPBEAR_CONFIG TARGET_INITRAMFS_DROPBEAR_AUTH_KEYS
}

install_initramfs_unlock_target() {
  local target_root="$1"
  local config_tmp auth_keys_tmp
  initramfs_unlock_target_paths "${target_root}" || return $?
  install -d -m 0700 "${TARGET_INITRAMFS_DROPBEAR_DIR}"
  umask 077
  config_tmp="$(mktemp "${TARGET_INITRAMFS_DROPBEAR_DIR}/.config.XXXXXX")" || return 1
  auth_keys_tmp="$(mktemp "${TARGET_INITRAMFS_DROPBEAR_DIR}/.authorized_keys.XXXXXX")" || {
    rm -f "${config_tmp}"
    return 1
  }
  initramfs_unlock_dropbear_config >"${config_tmp}"
  initramfs_unlock_authorized_key "${RECOVERY_UNLOCK_KEY}" >"${auth_keys_tmp}"
  chmod 0600 "${config_tmp}" "${auth_keys_tmp}"
  mv -f "${config_tmp}" "${TARGET_INITRAMFS_DROPBEAR_CONFIG}" || {
    rm -f "${config_tmp}" "${auth_keys_tmp}"
    return 1
  }
  mv -f "${auth_keys_tmp}" "${TARGET_INITRAMFS_DROPBEAR_AUTH_KEYS}" || {
    rm -f "${auth_keys_tmp}"
    return 1
  }
  if ! chroot "${TARGET_ROOT}" update-initramfs -u -k all; then
    rm -f "${config_tmp}" "${auth_keys_tmp}"
    return 1
  fi
  TARGET_INITRAMFS_DEPLOYMENT_CHECKSUM="$(
    sha256sum "${TARGET_INITRAMFS_DROPBEAR_CONFIG}" "${TARGET_INITRAMFS_DROPBEAR_AUTH_KEYS}" \
      | sha256sum | awk '{print $1}'
  )"
  export TARGET_INITRAMFS_DEPLOYMENT_CHECKSUM
}
