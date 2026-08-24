#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/disk_identity.sh
source "${repo_dir}/lib/disk_identity.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
target="${tmp_dir}/target"
touch "${target}"

udevadm() {
  cat <<'EOF'
ID_MODEL=Test Disk
ID_SERIAL=TEST-SERIAL-001
ID_WWN=wwn-0x1234
ID_PATH=pci-0000:00:14.0-usb-0:1:1.0-scsi-0:0:0:0
ID_BUS=usb
EOF
}

lsblk() {
  printf '%s\n' 'gpt'
}

blkid() {
  printf '%s\n' '33333333-3333-4333-8333-333333333333'
}

blockdev() {
  case "$*" in
    *getsize64*) printf '%s\n' '2147483648' ;;
    *getss*) printf '%s\n' '512' ;;
  esac
}

metadata="$(disk_identity "${target}")"
grep -Fq 'serial=TEST-SERIAL-001' <<<"${metadata}" || fail 'serial missing'
grep -Fq 'wwn=wwn-0x1234' <<<"${metadata}" || fail 'wwn missing'
grep -Fq 'partition_table=gpt' <<<"${metadata}" || fail 'partition table missing'
grep -Fq 'size_bytes=2147483648' <<<"${metadata}" || fail 'size missing'

fingerprint="$(disk_identity_fingerprint "${metadata}")"
[[ "${fingerprint}" =~ ^[[:xdigit:]]{64}$ ]] || fail 'invalid identity fingerprint'

udevadm() {
  printf '%s\n' 'ID_MODEL=Test Disk' 'ID_SERIAL=TEST-SERIAL-001'
}
if disk_identity "${target}" >/dev/null 2>&1; then
  fail 'identity without WWN unexpectedly succeeded'
fi

printf '%s\n' 'disk identity tests: pass'
