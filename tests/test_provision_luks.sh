#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/provision_profile.sh
source "${repo_dir}/lib/provision_profile.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

HOST_ID='slinky'
TARGET_DISK='/dev/disk/by-id/usb-test'
EFI_SIZE='1GiB'
BOOT_SIZE='2GiB'
ROOT_VG='ubuntu-vg'
ROOT_LV='ubuntu-lv'
ROOT_FS_LABEL='ubuntu-root'
LUKS_CIPHER='aes-xts-plain64'
LUKS_KEY_SIZE='512'
LUKS_PBKDF='argon2id'
validate_provision_profile || fail 'valid profile rejected'

HOST_ID='bad host'
if validate_provision_profile; then
  fail 'invalid host id accepted'
fi
HOST_ID='slinky'

EFI_SIZE='0GiB'
if validate_provision_profile; then
  fail 'invalid EFI size accepted'
fi
EFI_SIZE='1GiB'

LUKS_CIPHER='aes-cbc-essiv:sha256'
if validate_provision_profile; then
  fail 'unsupported cipher accepted'
fi
LUKS_CIPHER='aes-xts-plain64'

for utility in sgdisk wipefs cryptsetup pvcreate vgcreate lvcreate mkfs.xfs; do
  grep -Fq "${utility}" "${repo_dir}/bin/provision-luks" || fail "dry-run command list omits ${utility}"
done
grep -Fq 'DRY_RUN=1' "${repo_dir}/bin/provision-luks" || fail 'default dry-run missing'
grep -Fq 'require_audit_vault' "${repo_dir}/bin/provision-luks" || fail 'audit gate missing'
grep -Fq 'confirm_destructive' "${repo_dir}/bin/provision-luks" || fail 'destructive confirmation missing'
grep -Fq 'mktemp /dev/shm/recovery-luks-key' "${repo_dir}/bin/provision-luks" || fail 'RAM key path missing'
grep -Fq 'dd if=/dev/urandom' "${repo_dir}/bin/provision-luks" || fail 'CSPRNG key generation missing'
grep -Fq 'luksHeaderBackup' "${repo_dir}/bin/provision-luks" || fail 'header backup missing'
grep -Fq 'sha256sum' "${repo_dir}/bin/provision-luks" || fail 'checksums missing'
grep -Fq 'trap ' "${repo_dir}/bin/provision-luks" || fail 'temporary key cleanup missing'

printf '%s\n' 'provision profile tests: pass'
