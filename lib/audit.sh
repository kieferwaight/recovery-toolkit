#!/usr/bin/env bash

_audit_clean() {
  local value="$1"
  value="${value//$'\r'/ }"
  value="${value//$'\n'/ }"
  value="${value//$'\t'/ }"
  printf '%s' "${value}"
}

_audit_property() {
  local properties="$1"
  local property="$2"
  awk -F= -v property="${property}" '$1 == property { sub(/^[^=]*=/, ""); print; exit }' <<<"${properties}"
}

require_audit_vault() {
  local vault_device mounted_device audit_root probe
  [[ -n "${VAULT_UUID:-}" ]] || {
    log_error 'Audit vault UUID is not configured.'
    return 1
  }
  [[ "${VAULT_UUID}" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]] || {
    log_error 'Audit vault UUID is invalid.'
    return 1
  }
  [[ -d "${VAULT_MOUNTPOINT:-}" ]] || {
    log_error 'Audit vault mountpoint does not exist.'
    return 1
  }
  mountpoint -q "${VAULT_MOUNTPOINT}" || {
    log_error 'Audit vault is not mounted.'
    return 1
  }

  vault_device="$(readlink -f "/dev/disk/by-uuid/${VAULT_UUID}")"
  mounted_device="$(findmnt -n -o SOURCE --target "${VAULT_MOUNTPOINT}")"
  mounted_device="$(readlink -f "${mounted_device}")"
  [[ -n "${vault_device}" && "${vault_device}" == "${mounted_device}" ]] || {
    log_error 'Audit vault mount does not match the configured UUID.'
    return 1
  }

  audit_root="${VAULT_MOUNTPOINT}/${VAULT_SUBDIR:-recovery-toolkit-vault}"
  mkdir -p "${audit_root}/hosts"
  probe="${audit_root}/.audit-write-test.$$"
  printf '%s\n' 'audit-write-test' >"${probe}" || {
    log_error 'Audit vault is not writable.'
    return 1
  }
  rm -f "${probe}"
  AUDIT_ROOT="${audit_root}"
  export AUDIT_ROOT
}

audit_target_identity() {
  local target="$1"
  local properties model serial wwn path bus size fs_uuid
  [[ -e "${target}" ]] || {
    log_error "Audit target does not exist: ${target}"
    return 1
  }
  properties="$(udevadm info --query=property --name="${target}")" || return 1
  model="$(_audit_property "${properties}" ID_MODEL)"
  serial="$(_audit_property "${properties}" ID_SERIAL)"
  wwn="$(_audit_property "${properties}" ID_WWN)"
  path="$(_audit_property "${properties}" ID_PATH)"
  bus="$(_audit_property "${properties}" ID_BUS)"
  size="$(blockdev --getsize64 "${target}")" || return 1
  fs_uuid="$(blkid -s UUID -o value "${target}" 2>/dev/null || true)"

  [[ -n "${serial}" || -n "${wwn}" ]] || {
    log_error "Audit target has no stable serial or WWN: ${target}"
    return 1
  }
  printf 'device=%s\n' "$(_audit_clean "${target}")"
  printf 'model=%s\n' "$(_audit_clean "${model}")"
  printf 'serial=%s\n' "$(_audit_clean "${serial}")"
  printf 'wwn=%s\n' "$(_audit_clean "${wwn}")"
  printf 'path=%s\n' "$(_audit_clean "${path}")"
  printf 'bus=%s\n' "$(_audit_clean "${bus}")"
  printf 'size_bytes=%s\n' "$(_audit_clean "${size}")"
  printf 'filesystem_uuid=%s\n' "$(_audit_clean "${fs_uuid}")"
}

audit_begin() {
  local action="$1"
  local target="$2"
  local metadata="$3"
  local host_id operation_id record_tmp
  [[ -n "${AUDIT_ROOT:-}" ]] || require_audit_vault || return 1
  host_id="${AUDIT_HOST_ID:-$(hostname -s)}"
  operation_id="$(date -u '+%Y%m%dT%H%M%SZ')-$$-${RANDOM}"
  AUDIT_OPERATION_ID="${operation_id}"
  AUDIT_RECORD="${AUDIT_ROOT}/hosts/${host_id}/${operation_id}.log"
  mkdir -p "$(dirname "${AUDIT_RECORD}")"
  record_tmp="${AUDIT_RECORD}.tmp.$$"
  {
    printf 'operation_id=%s\n' "${operation_id}"
    printf 'host=%s\n' "$(_audit_clean "${host_id}")"
    printf 'started_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'action=%s\n' "$(_audit_clean "${action}")"
    printf 'target=%s\n' "$(_audit_clean "${target}")"
    printf '%s\n' "${metadata}"
    printf 'status=planned\n'
  } >"${record_tmp}" && mv -f "${record_tmp}" "${AUDIT_RECORD}"
  export AUDIT_OPERATION_ID AUDIT_RECORD
}

audit_finish() {
  local exit_status="$1"
  local status
  [[ "${exit_status}" =~ ^[0-9]+$ ]] || return 1
  [[ -n "${AUDIT_RECORD:-}" && -f "${AUDIT_RECORD}" ]] || return 1
  if ((exit_status == 0)); then
    status='completed'
  else
    status='failed'
  fi
  {
    printf 'finished_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'exit_status=%s\n' "${exit_status}"
    printf 'status=%s\n' "${status}"
  } >>"${AUDIT_RECORD}"
}

audit_vault_path() {
  local relative="$1"
  [[ -n "${AUDIT_ROOT:-}" ]] || return 1
  [[ "${relative}" != /* && "${relative}" != *$'\n'* && "${relative}" != *$'\r'* ]] || return 1
  case "/${relative}/" in
    */../*|*/./*) return 1 ;;
  esac
  printf '%s/%s\n' "${AUDIT_ROOT%/}" "${relative}"
}

audit_record_event() {
  local relative="$1"
  local contents="$2"
  local destination temporary

  destination="$(audit_vault_path "${relative}")" || return 1
  mkdir -p "$(dirname "${destination}")"
  temporary="${destination}.tmp.$$"
  umask 077
  if ! printf '%s\n' "${contents}" >"${temporary}"; then
    rm -f "${temporary}"
    return 1
  fi
  chmod 0600 "${temporary}"
  mv -f "${temporary}" "${destination}"
}
