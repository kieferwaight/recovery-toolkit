#!/usr/bin/env bash

# Load profile values without forcing unrelated toolkit commands to configure
# initramfs networking.
load_recovery_profile() {
  RECOVERY_INTERFACE="${RECOVERY_INTERFACE:-}"
  RECOVERY_GATEWAY="${RECOVERY_GATEWAY:-}"
  RECOVERY_HOST_IP="${RECOVERY_HOST_IP:-}"
  RECOVERY_SUBNET="${RECOVERY_SUBNET:-}"
  RECOVERY_SSH_PORT="${RECOVERY_SSH_PORT:-2222}"
  RECOVERY_CLIENT_CIDR="${RECOVERY_CLIENT_CIDR:-}"
  export RECOVERY_INTERFACE RECOVERY_GATEWAY RECOVERY_HOST_IP
  export RECOVERY_SUBNET RECOVERY_SSH_PORT RECOVERY_CLIENT_CIDR
}

_valid_ipv4() {
  local address="$1"
  local octet
  IFS=. read -r -a octets <<< "${address}"
  [[ "${#octets[@]}" -eq 4 ]] || return 1
  for octet in "${octets[@]}"; do
    [[ "${octet}" =~ ^[0-9]{1,3}$ ]] || return 1
    ((10#${octet} <= 255)) || return 1
  done
}

_valid_cidr24() {
  local cidr="$1"
  local address
  [[ "${cidr}" == */24 ]] || return 1
  address="${cidr%/24}"
  _valid_ipv4 "${address}" || return 1
  IFS=. read -r -a octets <<< "${address}"
  [[ "${octets[3]}" -eq 0 ]] || return 1
}

_same_cidr24() {
  local left="$1"
  local right="$2"
  IFS=. read -r -a left_octets <<< "${left}"
  IFS=. read -r -a right_octets <<< "${right}"
  [[ "${left_octets[0]}" -eq "${right_octets[0]}" \
    && "${left_octets[1]}" -eq "${right_octets[1]}" \
    && "${left_octets[2]}" -eq "${right_octets[2]}" ]]
}

validate_recovery_profile() {
  load_recovery_profile
  [[ -n "${RECOVERY_INTERFACE}" ]] || return 1
  [[ -n "${RECOVERY_GATEWAY}" ]] || return 1
  [[ -n "${RECOVERY_HOST_IP}" ]] || return 1
  [[ -n "${RECOVERY_SUBNET}" ]] || return 1
  _valid_ipv4 "${RECOVERY_GATEWAY}" || return 1
  _valid_ipv4 "${RECOVERY_HOST_IP}" || return 1
  _valid_cidr24 "${RECOVERY_SUBNET}" || return 1

  local subnet_address="${RECOVERY_SUBNET%/24}"
  _same_cidr24 "${RECOVERY_GATEWAY}" "${subnet_address}" || return 1
  _same_cidr24 "${RECOVERY_HOST_IP}" "${subnet_address}" || return 1
  [[ "${RECOVERY_GATEWAY}" != "${RECOVERY_HOST_IP}" ]] || return 1
  [[ "${RECOVERY_HOST_IP##*.}" -gt 0 && "${RECOVERY_HOST_IP##*.}" -lt 255 ]] || return 1
  [[ "${RECOVERY_SSH_PORT}" =~ ^[0-9]+$ ]] || return 1
  ((RECOVERY_SSH_PORT >= 1 && RECOVERY_SSH_PORT <= 65535)) || return 1

  if [[ -n "${RECOVERY_CLIENT_CIDR}" ]]; then
    _valid_cidr24 "${RECOVERY_CLIENT_CIDR}" || return 1
  fi
}

validate_recovery_interface() {
  validate_recovery_profile || return 1
  [[ -d "/sys/class/net/${RECOVERY_INTERFACE}" ]]
}
