#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/initramfs_unlock.sh
source "${repo_dir}/lib/initramfs_unlock.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

RECOVERY_INTERFACE='enp1s0f0'
RECOVERY_GATEWAY='10.0.40.1'
RECOVERY_HOST_IP='10.0.40.2'
RECOVERY_SUBNET='10.0.40.0/24'
RECOVERY_SSH_PORT='2222'
RECOVERY_UNLOCK_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItestkey recovery'
RECOVERY_UNLOCK_KEY_FINGERPRINT='aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99'
INITRAMFS_DROPBEAR_DIR="${tmp_dir}/dropbear-initramfs"
INITRAMFS_DROPBEAR_CONFIG="${INITRAMFS_DROPBEAR_DIR}/config"
INITRAMFS_DROPBEAR_AUTH_KEYS="${INITRAMFS_DROPBEAR_DIR}/authorized_keys"

validate_initramfs_unlock_profile || fail 'valid unlock profile rejected'

RECOVERY_SSH_PORT='70000'
if validate_initramfs_unlock_profile; then
  fail 'invalid port accepted'
fi
RECOVERY_SSH_PORT='2222'

RECOVERY_UNLOCK_KEY=$'bad\nkey'
if validate_initramfs_unlock_profile; then
  fail 'multiline key accepted'
fi
RECOVERY_UNLOCK_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItestkey recovery'

dropbear_config="$(initramfs_unlock_dropbear_config)"
grep -Fq 'DROPBEAR_OPTIONS="-p 10.0.40.2:2222 -s -j -k -I 60"' <<<"${dropbear_config}" || fail 'dropbear config missing expected options'

forced_key="$(initramfs_unlock_authorized_key "${RECOVERY_UNLOCK_KEY}")"
grep -Fq 'command="cryptroot-unlock"' <<<"${forced_key}" || fail 'forced command missing'
grep -Fq 'no-port-forwarding' <<<"${forced_key}" || fail 'forwarding restriction missing'
grep -Fq "${RECOVERY_UNLOCK_KEY}" <<<"${forced_key}" || fail 'unlock key missing'

printf '%s\n' 'initramfs unlock tests: pass'
