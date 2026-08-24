#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

stub_bin="${tmp_dir}/bin"
host_root="${tmp_dir}/host"
vault_root="${tmp_dir}/vault"
mkdir -p "${stub_bin}" "${host_root}" "${vault_root}"
mkdir -p "${host_root}/etc" "${host_root}/boot"

cat > "${stub_bin}/findmnt" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"SOURCE /"* ]]; then
  printf '%s\n' '/dev/mapper/usb-root'
elif [[ "$*" == *"SOURCE ${VAULT_MOUNTPOINT}"* || "$*" == *"SOURCE --target ${VAULT_MOUNTPOINT}"* ]]; then
  printf '%s\n' '/dev/sdb1'
elif [[ "$*" == *"SOURCE --target ${TEST_HOST_ROOT}"* ]]; then
  printf '%s\n' '/dev/mapper/host-root'
else
  exit 1
fi
EOF
cat > "${stub_bin}/lsblk" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *usb-root*|*sda3*|*/dev/sda) printf '%s\n' '/dev/sda disk' ;;
  *sdb1*|*sdb*) printf '%s\n' '/dev/sdb disk' ;;
  *host-root*|*sdc*) printf '%s\n' '/dev/sdc disk' ;;
  *) exit 1 ;;
esac
EOF
cat > "${stub_bin}/blkid" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *usb-root*) printf '%s\n' 'root-uuid' ;;
  *sdb1*) printf '%s\n' 'vault-uuid' ;;
  *UUID=vault-uuid*) printf '%s\n' '/dev/sdb1' ;;
  *) exit 1 ;;
esac
EOF
cat > "${stub_bin}/mountpoint" <<'EOF'
#!/usr/bin/env bash
[[ "$2" == "${TEST_HOST_ROOT}" || "$2" == "${VAULT_MOUNTPOINT}" ]]
EOF
cat > "${stub_bin}/readlink" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *'/dev/sdb1'* ]]; then
  printf '%s\n' '/dev/sdb1'
else
  /usr/bin/readlink "$@"
fi
EOF
chmod +x "${stub_bin}"/*

PATH="${stub_bin}:${PATH}"
export PATH
RECOVERY_USB_ROOT_UUID='root-uuid'
RECOVERY_DISK_UUID=''
VAULT_UUID='vault-uuid'
VAULT_MOUNTPOINT="${vault_root}"
TEST_HOST_ROOT="${host_root}"
export RECOVERY_USB_ROOT_UUID RECOVERY_DISK_UUID VAULT_UUID VAULT_MOUNTPOINT TEST_HOST_ROOT

# shellcheck source=../lib/common.sh
source "${repo_dir}/lib/common.sh"
# shellcheck source=../lib/device_guard.sh
source "${repo_dir}/lib/device_guard.sh"
# shellcheck source=../lib/usb_context.sh
source "${repo_dir}/lib/usb_context.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

if assert_not_protected_disk '/dev/sda'; then
  fail 'active root disk was accepted'
fi
if assert_not_protected_disk '/dev/sdb'; then
  fail 'vault disk was accepted'
fi
assert_not_protected_disk '/dev/sdc' || fail 'separate host disk was rejected'

if assert_target_root_is_safe '/'; then
  fail 'running root was accepted as a target root'
fi
if assert_target_root_is_safe "${vault_root}"; then
  fail 'vault mount was accepted as a target root'
fi
assert_target_root_is_safe "${host_root}" || fail 'mounted host root was rejected'

if RECOVERY_USB_MAKE_CONTEXT='' RECOVERY_USB_MAKE_TARGET='usb-vault' usb_require_make_context; then
  fail 'direct USB invocation was accepted'
fi
RECOVERY_USB_MAKE_CONTEXT='1'
RECOVERY_USB_MAKE_TARGET='usb-vault'
usb_require_make_context || fail 'Makefile USB context was rejected'

printf '%s\n' 'device and USB context tests: pass'
