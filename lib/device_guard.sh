#!/usr/bin/env bash

# Resolve block-device ancestry before any host-facing command inspects or
# mutates a disk. Callers must source common.sh first for logging and config.

active_root_source() {
  local source root_uuid candidate
  source="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
  if [[ -n "${source}" && "${source}" != overlay && "${source}" != aufs ]]; then
    printf '%s\n' "${source}"
    return 0
  fi

  root_uuid="${RECOVERY_USB_ROOT_UUID:-${RECOVERY_DISK_UUID:-}}"
  [[ -n "${root_uuid}" ]] || return 1
  candidate="/dev/disk/by-uuid/${root_uuid}"
  [[ -e "${candidate}" ]] || return 1
  readlink -f "${candidate}"
}

physical_disk_for_source() {
  local source="$1"
  local disk

  [[ -n "${source}" ]] || return 1
  disk="$(lsblk -sno NAME,TYPE "${source}" 2>/dev/null \
    | awk '$2 == "disk" { print $1; exit }')"
  [[ -n "${disk}" ]] || return 1
  case "${disk}" in
    /dev/*) printf '%s\n' "${disk}" ;;
    *) printf '/dev/%s\n' "${disk}" ;;
  esac
}

protected_disk_for_source() {
  physical_disk_for_source "$1"
}

_configured_vault_source() {
  local vault_uuid="${VAULT_UUID:-}"
  [[ -n "${vault_uuid}" ]] || return 1
  local source="/dev/disk/by-uuid/${vault_uuid}"
  if [[ -e "${source}" ]]; then
    readlink -f "${source}"
    return 0
  fi
  blkid -t "UUID=${vault_uuid}" -o device 2>/dev/null || return 1
}

assert_not_protected_disk() {
  local target="$1"
  local target_disk root_source root_disk vault_source vault_disk

  target_disk="$(physical_disk_for_source "${target}")" || {
    log_error "Could not resolve a physical disk for target ${target}."
    return 2
  }
  root_source="$(active_root_source)" || {
    log_error 'Could not resolve the physical disk backing the active root.'
    return 2
  }
  root_disk="$(protected_disk_for_source "${root_source}")" || {
    log_error "Could not resolve a physical disk for active root ${root_source}."
    return 2
  }
  if [[ "${target_disk}" == "${root_disk}" ]]; then
    log_error "Safety violation: target ${target_disk} backs the active root (${root_source})."
    return 2
  fi

  if vault_source="$(_configured_vault_source)"; then
    vault_disk="$(protected_disk_for_source "${vault_source}")" || {
      log_error "Could not resolve a physical disk for vault ${vault_source}."
      return 2
    }
    if [[ "${target_disk}" == "${vault_disk}" ]]; then
      log_error "Safety violation: target ${target_disk} is the configured vault disk."
      return 2
    fi
  fi
}

assert_target_root_is_safe() {
  local target_root="$1"
  local source target_disk

  [[ "${target_root}" == /* && "${target_root}" != '/' ]] || {
    log_error 'Host target root must be an absolute path other than /.'
    return 2
  }
  [[ -d "${target_root}" ]] || {
    log_error "Host target root does not exist: ${target_root}"
    return 1
  }
  if [[ -n "${VAULT_MOUNTPOINT:-}" && "${target_root%/}" == "${VAULT_MOUNTPOINT%/}" ]]; then
    log_error 'Host target root cannot be the configured vault mount.'
    return 2
  fi
  mountpoint -q "${target_root}" || {
    log_error "Host target root is not a mountpoint: ${target_root}"
    return 1
  }
  source="$(findmnt -n -o SOURCE --target "${target_root}" 2>/dev/null || true)"
  [[ -n "${source}" && "${source}" != overlay && "${source}" != aufs ]] || {
    log_error "Host target root has no block-backed mount source: ${target_root}"
    return 2
  }
  target_disk="$(physical_disk_for_source "${source}")" || {
    log_error "Could not resolve the physical disk backing host target ${target_root}."
    return 2
  }
  assert_not_protected_disk "${target_disk}" || return $?
  [[ -d "${target_root}/etc" && -d "${target_root}/boot" ]] || {
    log_error "Host target root lacks the expected etc/ and boot/ directories."
    return 1
  }
}
