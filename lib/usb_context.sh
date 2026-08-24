#!/usr/bin/env bash

# USB mutation guard. This is an accident-prevention boundary, not a claim
# that environment variables are an authorization mechanism.

if ! declare -F active_root_source >/dev/null 2>&1; then
  # shellcheck source=device_guard.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/device_guard.sh"
fi

_usb_expected_root_uuid() {
  printf '%s\n' "${RECOVERY_USB_ROOT_UUID:-${RECOVERY_DISK_UUID:-}}"
}

usb_context_report() {
  local root_source root_uuid root_disk vault_source vault_disk vault_uuid
  root_source="$(active_root_source)" || {
    log_error 'Could not resolve the running USB root source.'
    return 2
  }
  root_uuid="$(blkid -s UUID -o value "${root_source}" 2>/dev/null || true)"
  root_disk="$(physical_disk_for_source "${root_source}")" || {
    log_error "Could not resolve the physical disk backing ${root_source}."
    return 2
  }
  printf 'usb_root_source=%s\n' "${root_source}"
  printf 'usb_root_uuid=%s\n' "${root_uuid:-unknown}"
  printf 'usb_root_disk=%s\n' "${root_disk}"

  vault_uuid="${VAULT_UUID:-}"
  if [[ -z "${vault_uuid}" ]]; then
    printf '%s\n' 'vault_uuid=not-configured'
    return 0
  fi
  vault_source="$(_configured_vault_source 2>/dev/null || true)"
  if [[ -n "${vault_source}" ]]; then
    vault_disk="$(physical_disk_for_source "${vault_source}")" || {
      log_error "Could not resolve the physical disk backing vault ${vault_source}."
      return 2
    }
    printf 'vault_source=%s\n' "${vault_source}"
    printf 'vault_uuid=%s\n' "$(blkid -s UUID -o value "${vault_source}" 2>/dev/null || printf '%s' unknown)"
    printf 'vault_disk=%s\n' "${vault_disk}"
    [[ "${vault_disk}" != "${root_disk}" ]] || {
      log_error 'Configured vault UUID resolves to the running USB root disk.'
      return 2
    }
    if mountpoint -q "${VAULT_MOUNTPOINT:-/mnt/Vault}"; then
      local mounted_source
      mounted_source="$(findmnt -n -o SOURCE --target "${VAULT_MOUNTPOINT:-/mnt/Vault}" 2>/dev/null || true)"
      [[ "$(readlink -f "${mounted_source}")" == "${vault_source}" ]] || {
        log_error 'Configured vault mount does not match VAULT_UUID.'
        return 2
      }
    fi
  else
    printf 'vault_source=%s\n' "${vault_source} (not present)"
  fi
}

usb_validate_context() {
  local target="${1:-}"
  local root_uuid expected_root_uuid vault_source

  usb_context_report || return $?
  root_uuid="$(blkid -s UUID -o value "$(active_root_source)" 2>/dev/null || true)"
  expected_root_uuid="$(_usb_expected_root_uuid)"
  if [[ -n "${expected_root_uuid}" && "${root_uuid}" != "${expected_root_uuid}" ]]; then
    log_error "USB root UUID mismatch: detected ${root_uuid:-unknown}, expected ${expected_root_uuid}."
    return 2
  fi

  vault_source="$(_configured_vault_source 2>/dev/null || true)"
  if [[ "${target}" == 'usb-vault' && -z "${vault_source}" ]]; then
    log_error "Vault device is required for USB target ${target}."
    return 1
  fi
}

usb_require_make_context() {
  local target="${RECOVERY_USB_MAKE_TARGET:-}"
  case " ${RECOVERY_USB_MAKE_TARGETS:-usb-preflight usb-install usb-vault usb-ssh usb-tailscale usb-optimize usb-overlay} " in
    *" ${target} "*) ;;
    *) log_error "USB script requires an allowlisted Makefile target."; return 2 ;;
  esac
  [[ "${RECOVERY_USB_MAKE_CONTEXT:-}" == 1 ]] || {
    log_error 'USB maintenance must be invoked through the Makefile.'
    return 2
  }
  usb_validate_context "${target}"
}
