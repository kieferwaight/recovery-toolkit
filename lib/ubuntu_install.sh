#!/usr/bin/env bash

# Profile and render the host Ubuntu Server autoinstall handoff. LUKS key
# contents stay in the vault-backed key file; YAML contains only its runtime path.

# shellcheck source=provision_profile.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/provision_profile.sh"

load_ubuntu_install_profile() {
  UBUNTU_INSTALLER_SOURCE="${UBUNTU_INSTALLER_SOURCE:-/cdrom}"
  UBUNTU_IDENTITY_FILE="${UBUNTU_IDENTITY_FILE:-}"
  UBUNTU_LUKS_KEY_FILE="${UBUNTU_LUKS_KEY_FILE:-}"
  UBUNTU_USERNAME="${UBUNTU_USERNAME:-}"
  UBUNTU_PASSWORD_HASH="${UBUNTU_PASSWORD_HASH:-}"
  UBUNTU_SSH_PUBLIC_KEY="${UBUNTU_SSH_PUBLIC_KEY:-}"
  export UBUNTU_INSTALLER_SOURCE UBUNTU_IDENTITY_FILE UBUNTU_LUKS_KEY_FILE
  export UBUNTU_USERNAME UBUNTU_PASSWORD_HASH UBUNTU_SSH_PUBLIC_KEY
}

_ubuntu_absolute_single_line() {
  [[ "$1" == /* ]] || return 1
  [[ "$1" != *$'\n'* && "$1" != *$'\r'* ]] || return 1
}

_ubuntu_identity_value() {
  local key="$1"
  awk -F= -v key="${key}" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' \
    "${UBUNTU_IDENTITY_FILE}"
}

load_ubuntu_identity_file() {
  [[ -f "${UBUNTU_IDENTITY_FILE}" ]] || return 1
  UBUNTU_USERNAME="$(_ubuntu_identity_value UBUNTU_USERNAME)"
  UBUNTU_PASSWORD_HASH="$(_ubuntu_identity_value UBUNTU_PASSWORD_HASH)"
  UBUNTU_SSH_PUBLIC_KEY="$(_ubuntu_identity_value UBUNTU_SSH_PUBLIC_KEY)"
  export UBUNTU_USERNAME UBUNTU_PASSWORD_HASH UBUNTU_SSH_PUBLIC_KEY
}

validate_ubuntu_identity() {
  local mode
  [[ -f "${UBUNTU_IDENTITY_FILE}" ]] || return 1
  mode="$(stat -c '%a' "${UBUNTU_IDENTITY_FILE}" 2>/dev/null || stat -f '%Lp' "${UBUNTU_IDENTITY_FILE}" 2>/dev/null)"
  [[ "${mode}" == '600' ]] || return 1
  load_ubuntu_identity_file || return 1
  [[ "${UBUNTU_USERNAME}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || return 1
  [[ "${UBUNTU_PASSWORD_HASH}" == \$* ]] || return 1
  [[ "${UBUNTU_PASSWORD_HASH}" != *[[:space:]]* ]] || return 1
  [[ "${UBUNTU_PASSWORD_HASH}" != *\'* ]] || return 1
  [[ "${UBUNTU_SSH_PUBLIC_KEY}" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+)[[:space:]][^[:space:]]+([[:space:]][^\'\"$'\r\n']*)?$ ]] || return 1
}

validate_ubuntu_install_profile() {
  load_provision_profile
  load_ubuntu_install_profile
  validate_provision_profile || return 1
  _ubuntu_absolute_single_line "${UBUNTU_INSTALLER_SOURCE}" || return 1
  _ubuntu_absolute_single_line "${UBUNTU_IDENTITY_FILE}" || return 1
  _ubuntu_absolute_single_line "${UBUNTU_LUKS_KEY_FILE}" || return 1
  validate_ubuntu_identity || return 1
}

_ubuntu_yaml_quote() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf "'%s'" "${value}"
}

render_ubuntu_autoinstall() {
  local efi_size_bytes="$1"
  local boot_size_bytes="$2"
  local crypt_size_bytes="$3"
  local keyfile="$4"
  local crypt_partition_size=''

  _ubuntu_absolute_single_line "${keyfile}" || return 1
  [[ "${efi_size_bytes}" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ "${boot_size_bytes}" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ "${crypt_size_bytes}" =~ ^[0-9]+$ ]] || return 1
  if ((crypt_size_bytes > 0)); then
    crypt_partition_size="        size: ${crypt_size_bytes}B
"
  fi

  cat <<EOF
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: $(_ubuntu_yaml_quote "${HOST_ID}")
    username: $(_ubuntu_yaml_quote "${UBUNTU_USERNAME}")
    password: $(_ubuntu_yaml_quote "${UBUNTU_PASSWORD_HASH}")
  ssh:
    install-server: true
    authorized-keys:
      - $(_ubuntu_yaml_quote "${UBUNTU_SSH_PUBLIC_KEY}")
  packages:
    - dropbear-initramfs
    - cryptsetup-initramfs
    - xfsprogs
  storage:
    swap:
      size: 0
    config:
      - type: disk
        id: disk0
        path: $(_ubuntu_yaml_quote "${TARGET_DISK}")
        ptable: gpt
        preserve: true
        grub_device: true
      - type: partition
        id: disk0-part1
        device: disk0
        number: 1
        size: ${efi_size_bytes}B
        flag: boot
        preserve: true
      - type: format
        id: disk0-part1-fs
        volume: disk0-part1
        fstype: fat32
        label: EFI
      - type: mount
        id: disk0-part1-mount
        device: disk0-part1-fs
        path: /boot/efi
      - type: partition
        id: disk0-part2
        device: disk0
        number: 2
        size: ${boot_size_bytes}B
        preserve: true
      - type: format
        id: disk0-part2-fs
        volume: disk0-part2
        fstype: ext4
        label: BOOT
      - type: mount
        id: disk0-part2-mount
        device: disk0-part2-fs
        path: /boot
      - type: partition
        id: disk0-part3
        device: disk0
        number: 3
${crypt_partition_size}        preserve: true
      - type: dm_crypt
        id: cryptroot
        volume: disk0-part3
        dm_name: $(_ubuntu_yaml_quote "recovery-${HOST_ID}-luks")
        keyfile: ${keyfile}
        preserve: true
      - type: lvm_volgroup
        id: root-vg
        name: $(_ubuntu_yaml_quote "${ROOT_VG}")
        devices:
          - cryptroot
        preserve: true
      - type: lvm_partition
        id: root-lv
        name: $(_ubuntu_yaml_quote "${ROOT_LV}")
        volgroup: root-vg
        size: -1
        preserve: true
      - type: format
        id: root-fs
        volume: root-lv
        fstype: xfs
        label: $(_ubuntu_yaml_quote "${ROOT_FS_LABEL}")
        preserve: true
      - type: mount
        id: root-mount
        device: root-fs
        path: /
  shutdown: poweroff
EOF
}
