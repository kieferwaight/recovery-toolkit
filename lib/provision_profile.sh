#!/usr/bin/env bash

load_provision_profile() {
  HOST_ID="${HOST_ID:-}"
  TARGET_DISK="${TARGET_DISK:-}"
  EFI_SIZE="${EFI_SIZE:-1GiB}"
  BOOT_SIZE="${BOOT_SIZE:-2GiB}"
  ROOT_VG="${ROOT_VG:-ubuntu-vg}"
  ROOT_LV="${ROOT_LV:-ubuntu-lv}"
  ROOT_FS_LABEL="${ROOT_FS_LABEL:-ubuntu-root}"
  LUKS_CIPHER="${LUKS_CIPHER:-aes-xts-plain64}"
  LUKS_KEY_SIZE="${LUKS_KEY_SIZE:-512}"
  LUKS_PBKDF="${LUKS_PBKDF:-argon2id}"
  export HOST_ID TARGET_DISK EFI_SIZE BOOT_SIZE ROOT_VG ROOT_LV
  export ROOT_FS_LABEL LUKS_CIPHER LUKS_KEY_SIZE LUKS_PBKDF
}

_valid_storage_size() {
  [[ "$1" =~ ^[1-9][0-9]*(MiB|GiB|TiB)$ ]]
}

_valid_name() {
  [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}$ ]]
}

validate_provision_profile() {
  load_provision_profile
  [[ "${HOST_ID}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}$ ]] || return 1
  [[ -n "${TARGET_DISK}" ]] || return 1
  _valid_storage_size "${EFI_SIZE}" || return 1
  _valid_storage_size "${BOOT_SIZE}" || return 1
  _valid_name "${ROOT_VG}" || return 1
  _valid_name "${ROOT_LV}" || return 1
  _valid_name "${ROOT_FS_LABEL}" || return 1
  [[ "${LUKS_CIPHER}" == 'aes-xts-plain64' ]] || return 1
  [[ "${LUKS_KEY_SIZE}" == '512' ]] || return 1
  [[ "${LUKS_PBKDF}" == 'argon2id' ]] || return 1
}
