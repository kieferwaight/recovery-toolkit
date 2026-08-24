#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${repo_dir}/lib/common.sh"
# shellcheck source=../lib/audit.sh
source "${repo_dir}/lib/audit.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

expect_failure() {
  if "$@"; then
    fail "expected failure: $*"
  fi
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
VAULT_MOUNTPOINT="${tmp_dir}/mount"
VAULT_SUBDIR="recovery-toolkit-vault"
VAULT_UUID="11111111-1111-4111-8111-111111111111"
mkdir -p "${VAULT_MOUNTPOINT}"
target="${tmp_dir}/fake-target"
touch "${target}"

findmnt() {
  if [[ "$*" == *"--target ${tmp_dir}/mount"* ]]; then
    printf '%s\n' '/dev/fake-vault'
  else
    command findmnt "$@"
  fi
}

mountpoint() {
  [[ "$*" == *"${tmp_dir}/mount"* ]]
}

readlink() {
  if [[ "$*" == *"/dev/disk/by-uuid/${VAULT_UUID}"* || "$*" == *'/dev/fake-vault'* ]]; then
    printf '%s\n' '/dev/fake-vault'
  else
    command readlink "$@"
  fi
}

udevadm() {
  cat <<'EOF'
ID_MODEL=Test Disk
ID_SERIAL=TEST-SERIAL-001
ID_WWN=wwn-0x1234
ID_PATH=pci-0000:00:14.0-usb-0:1:1.0-scsi-0:0:0:0
ID_BUS=usb
EOF
}

blockdev() {
  printf '%s\n' '2147483648'
}

blkid() {
  printf '%s\n' '22222222-2222-4222-8222-222222222222'
}

unset VAULT_UUID
expect_failure require_audit_vault
VAULT_UUID="11111111-1111-4111-8111-111111111111"

VAULT_MOUNTPOINT="${tmp_dir}/not-mounted"
mkdir -p "${VAULT_MOUNTPOINT}"
expect_failure require_audit_vault
VAULT_MOUNTPOINT="${tmp_dir}/mount"

require_audit_vault
target_metadata="$(audit_target_identity "${target}")"
grep -Fq 'serial=TEST-SERIAL-001' <<<"${target_metadata}" || fail 'serial missing'
grep -Fq 'wwn=wwn-0x1234' <<<"${target_metadata}" || fail 'wwn missing'

audit_begin 'test-inspection' "${target}" "${target_metadata}"
[[ -f "${AUDIT_RECORD}" ]] || fail 'audit record missing'
grep -Fq 'status=planned' "${AUDIT_RECORD}" || fail 'planned status missing'
grep -Fq 'action=test-inspection' "${AUDIT_RECORD}" || fail 'action missing'
grep -Fq "target=${target}" "${AUDIT_RECORD}" || fail 'target missing'
if grep -Eqi 'PRIVATE KEY|SECRET|PASSWORD|TOKEN' "${AUDIT_RECORD}"; then
  fail 'secret-like content escaped into audit record'
fi

audit_finish 0
grep -Fq 'status=completed' "${AUDIT_RECORD}" || fail 'completed status missing'

audit_begin 'test-failure' "${target}" "${target_metadata}"
audit_finish 7
grep -Fq 'status=failed' "${AUDIT_RECORD}" || fail 'failed status missing'

printf '%s\n' 'audit tests: pass'
