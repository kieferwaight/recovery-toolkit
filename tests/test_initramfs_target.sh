#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)"
tmp_dir="$(mktemp -d)"
had_env=false
if [[ -f "$repo_dir/.env" ]]; then
  had_env=true
fi
trap 'rm -rf "$tmp_dir"; if [[ "$had_env" == false ]]; then rm -f "$repo_dir/.env"; fi' EXIT

host_root="$tmp_dir/host"
vault_root="$tmp_dir/vault"
unmounted_root="$tmp_dir/unmounted"
active_root="$tmp_dir/active"
stub_bin="$tmp_dir/bin"
mkdir -p "$host_root/etc" "$host_root/boot" "$vault_root" "$unmounted_root" "$active_root" "$stub_bin"
chroot_log="$tmp_dir/chroot.log"

cat > "$stub_bin/findmnt" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"SOURCE /"* ]]; then
  printf '%s\n' '/dev/mapper/usb-root'
elif [[ "$*" == *"SOURCE --target $TEST_HOST_ROOT"* ]]; then
  printf '%s\n' '/dev/mapper/host-root'
elif [[ "$*" == *"SOURCE --target $TEST_ACTIVE_ROOT"* ]]; then
  printf '%s\n' '/dev/mapper/usb-root'
elif [[ "$*" == *"SOURCE --target $TEST_VAULT_ROOT"* ]]; then
  printf '%s\n' '/dev/sdb1'
else
  exit 1
fi
EOF
cat > "$stub_bin/lsblk" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *usb-root*) printf '%s\n' '/dev/sda disk' ;;
  *host-root*|*sdc*) printf '%s\n' '/dev/sdc disk' ;;
  *sdb1*|*sdb*) printf '%s\n' '/dev/sdb disk' ;;
  *) exit 1 ;;
esac
EOF
cat > "$stub_bin/blkid" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *usb-root*) printf '%s\n' 'root-uuid' ;;
  *UUID=vault-uuid*) printf '%s\n' '/dev/sdb1' ;;
  *sdb1*) printf '%s\n' 'vault-uuid' ;;
  *) exit 1 ;;
esac
EOF
cat > "$stub_bin/mountpoint" <<'EOF'
#!/usr/bin/env bash
[[ "$2" == "$TEST_HOST_ROOT" || "$2" == "$TEST_ACTIVE_ROOT" || "$2" == "$TEST_VAULT_ROOT" ]]
EOF
cat > "$stub_bin/readlink" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  */dev/sdb1*) printf '%s\n' '/dev/sdb1' ;;
  *) /usr/bin/readlink "$@" ;;
esac
EOF
cat > "$stub_bin/chroot" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$CHROOT_LOG"
exit 0
EOF
chmod +x "$stub_bin"/*

export PATH="$stub_bin:$PATH"
export TEST_HOST_ROOT="$host_root"
export TEST_ACTIVE_ROOT="$active_root"
export TEST_VAULT_ROOT="$vault_root"
export CHROOT_LOG="$chroot_log"
export RECOVERY_USB_ROOT_UUID='root-uuid'
export VAULT_UUID='vault-uuid'
export VAULT_MOUNTPOINT="$vault_root"
export RECOVERY_INTERFACE='enp1s0f0'
export RECOVERY_GATEWAY='10.0.40.1'
export RECOVERY_HOST_IP='10.0.40.2'
export RECOVERY_SUBNET='10.0.40.0/24'
export RECOVERY_SSH_PORT='2222'
export RECOVERY_UNLOCK_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItestkey recovery'
export RECOVERY_UNLOCK_KEY_FINGERPRINT='aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99'
export INITRAMFS_DROPBEAR_DIR='/etc/dropbear-initramfs'
export INITRAMFS_DROPBEAR_CONFIG='/etc/dropbear-initramfs/config'
export INITRAMFS_DROPBEAR_AUTH_KEYS='/etc/dropbear-initramfs/authorized_keys'

# shellcheck source=../lib/common.sh
source "$repo_dir/lib/common.sh"
# shellcheck source=../lib/device_guard.sh
source "$repo_dir/lib/device_guard.sh"
# shellcheck source=../lib/initramfs_unlock.sh
source "$repo_dir/lib/initramfs_unlock.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

initramfs_unlock_target_paths "$host_root" || fail 'valid target root rejected'
[[ "$TARGET_INITRAMFS_DROPBEAR_DIR" == "$host_root/etc/dropbear-initramfs" ]] || fail 'target path escaped root'
if initramfs_unlock_target_paths '/'; then
  fail 'running root accepted'
fi
if initramfs_unlock_target_paths "$vault_root"; then
  fail 'vault root accepted'
fi
if initramfs_unlock_target_paths "$unmounted_root"; then
  fail 'unmounted target accepted'
fi
if initramfs_unlock_target_paths "$active_root"; then
  fail 'active USB target accepted'
fi

install_initramfs_unlock_target "$host_root" || fail 'target initramfs install failed'
[[ -f "$host_root/etc/dropbear-initramfs/config" ]] || fail 'target Dropbear config missing'
[[ -f "$host_root/etc/dropbear-initramfs/authorized_keys" ]] || fail 'target authorized keys missing'
grep -Fq 'DROPBEAR_OPTIONS="-p 10.0.40.2:2222 -s -j -k -I 60"' "$host_root/etc/dropbear-initramfs/config" || fail 'target Dropbear config incorrect'
grep -Fq 'command="cryptroot-unlock"' "$host_root/etc/dropbear-initramfs/authorized_keys" || fail 'forced command missing'
grep -Fq 'no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty' "$host_root/etc/dropbear-initramfs/authorized_keys" || fail 'SSH restrictions missing'
grep -Fq "$host_root update-initramfs -u -k all" "$chroot_log" || fail 'target initramfs was not rebuilt through chroot'
[[ ! -e '/etc/dropbear-initramfs/config' ]] || fail 'running USB config was modified'

if [[ "$had_env" == false ]]; then
  printf '%s\n' \
    "RECOVERY_USB_ROOT_UUID=\"root-uuid\"" \
    "VAULT_UUID=\"vault-uuid\"" \
    "VAULT_MOUNTPOINT=\"$vault_root\"" \
    "RECOVERY_INTERFACE=\"enp1s0f0\"" \
    "RECOVERY_GATEWAY=\"10.0.40.1\"" \
    "RECOVERY_HOST_IP=\"10.0.40.2\"" \
    "RECOVERY_SUBNET=\"10.0.40.0/24\"" \
    "RECOVERY_SSH_PORT=\"2222\"" \
    "RECOVERY_UNLOCK_KEY=\"$RECOVERY_UNLOCK_KEY\"" \
    "RECOVERY_UNLOCK_KEY_FINGERPRINT=\"$RECOVERY_UNLOCK_KEY_FINGERPRINT\"" > "$repo_dir/.env"
fi
dry_run_output="$(sudo env PATH="$stub_bin:$PATH" \
  TEST_HOST_ROOT="$host_root" TEST_ACTIVE_ROOT="$active_root" TEST_VAULT_ROOT="$vault_root" \
  bash "$repo_dir/bin/setup-initramfs-unlock" --target-root "$host_root")" || fail 'target-root dry-run failed'
grep -Fq "target_root=$host_root" <<<"$dry_run_output" || fail 'dry-run omitted target root'
grep -Fq 'Dry run only' <<<"$dry_run_output" || fail 'dry-run mutation warning missing'

grep -Fq -- '--target-root' "$repo_dir/bin/setup-initramfs-unlock" || fail 'target-root option missing'
grep -Fq 'chroot' "$repo_dir/lib/initramfs_unlock.sh" || fail 'host initramfs library lacks chroot'
if grep -Eq '^[[:space:]]*update-initramfs' "$repo_dir/bin/setup-initramfs-unlock"; then
  fail 'command can update the running USB initramfs directly'
fi

printf '%s\n' 'target initramfs tests: pass'
