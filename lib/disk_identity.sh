#!/usr/bin/env bash

_disk_identity_clean() {
  local value="$1"
  value="${value//$'\r'/ }"
  value="${value//$'\n'/ }"
  value="${value//$'\t'/ }"
  printf '%s' "${value}"
}

_disk_identity_property() {
  local properties="$1"
  local property="$2"
  awk -F= -v property="${property}" '$1 == property { sub(/^[^=]*=/, ""); print; exit }' <<<"${properties}"
}

disk_identity() {
  local target="$1"
  local properties model serial wwn path bus size sector table fs_uuid
  [[ -e "${target}" ]] || return 1
  properties="$(udevadm info --query=property --name="${target}")" || return 1
  model="$(_disk_identity_property "${properties}" ID_MODEL)"
  serial="$(_disk_identity_property "${properties}" ID_SERIAL)"
  wwn="$(_disk_identity_property "${properties}" ID_WWN)"
  path="$(_disk_identity_property "${properties}" ID_PATH)"
  bus="$(_disk_identity_property "${properties}" ID_BUS)"
  size="$(blockdev --getsize64 "${target}")" || return 1
  sector="$(blockdev --getss "${target}")" || return 1
  table="$(lsblk -dn -o PTTYPE "${target}" 2>/dev/null || true)"
  fs_uuid="$(blkid -s UUID -o value "${target}" 2>/dev/null || true)"

  [[ -n "${serial}" && -n "${wwn}" ]] || return 1
  printf 'device=%s\n' "$(_disk_identity_clean "${target}")"
  printf 'model=%s\n' "$(_disk_identity_clean "${model}")"
  printf 'serial=%s\n' "$(_disk_identity_clean "${serial}")"
  printf 'wwn=%s\n' "$(_disk_identity_clean "${wwn}")"
  printf 'path=%s\n' "$(_disk_identity_clean "${path}")"
  printf 'transport=%s\n' "$(_disk_identity_clean "${bus}")"
  printf 'size_bytes=%s\n' "$(_disk_identity_clean "${size}")"
  printf 'sector_size=%s\n' "$(_disk_identity_clean "${sector}")"
  printf 'partition_table=%s\n' "$(_disk_identity_clean "${table}")"
  printf 'filesystem_uuid=%s\n' "$(_disk_identity_clean "${fs_uuid}")"
}

disk_identity_value() {
  local metadata="$1"
  local key="$2"
  awk -F= -v key="${key}" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' <<<"${metadata}"
}

disk_identity_fingerprint() {
  local metadata="$1"
  printf '%s\n' "${metadata}" | sha256sum | awk '{print $1}'
}
