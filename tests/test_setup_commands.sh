#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains() {
  local file=$1
  local text=$2

  grep -Fq -- "$text" "$file"
}

assert_contains "${repo_dir}/scripts/usb/setup-ssh" "KEYS_URL=\"\${GITHUB_KEYS_URL:-https://github.com/kieferwaight.keys}\""
assert_contains "${repo_dir}/scripts/usb/setup-ssh" 'grep -Fqx --'
assert_contains "${repo_dir}/scripts/usb/setup-ssh" 'systemctl enable --now'
assert_contains "${repo_dir}/scripts/usb/setup-tailscale" 'https://tailscale.com/install.sh'
assert_contains "${repo_dir}/scripts/usb/setup-tailscale" 'tailscale up --qr=false --timeout=10s'
assert_contains "${repo_dir}/scripts/usb/setup-tailscale" 'login'
assert_contains "${repo_dir}/.env.example" 'VAULT_UUID=""'
assert_contains "${repo_dir}/.env.example" 'VAULT_MOUNTPOINT="/mnt/Vault"'
assert_contains "${repo_dir}/.env.example" 'VAULT_SUBDIR="recovery-toolkit-vault"'
assert_contains "${repo_dir}/scripts/usb/setup-vault" 'systemd-escape --path --suffix=mount'
assert_contains "${repo_dir}/scripts/usb/setup-vault" 'ID_FS_UUID'
assert_contains "${repo_dir}/scripts/usb/setup-vault" 'BindsTo='
assert_contains "${repo_dir}/scripts/usb/setup-vault" 'noatime,lazytime,nosuid,nodev'
assert_contains "${repo_dir}/lib/common.sh" 'recovery_profile.sh'
assert_contains "${repo_dir}/lib/common.sh" 'lsblk -sno NAME,TYPE'
for usb_script in optimize-usb setup-overlay-boot setup-ssh setup-tailscale setup-vault install-packages; do
  assert_contains "${repo_dir}/scripts/usb/${usb_script}" 'usb_require_make_context'
done
if grep -Fq '/etc/fstab' "${repo_dir}/scripts/usb/setup-vault"; then
  echo "vault setup must not use fstab" >&2
  exit 1
fi
assert_contains "${repo_dir}/README.md" "- \`setup-ssh\`, \`setup-tailscale\` - USB maintenance targets invoked through \`make usb-*\`"
assert_contains "${repo_dir}/scripts/usb/optimize-usb" 'backup_dir="/root/recovery-toolkit-optimization-'
assert_contains "${repo_dir}/scripts/usb/optimize-usb" 'apt-get purge -y snapd'
assert_contains "${repo_dir}/scripts/usb/optimize-usb" 'vm.dirty_background_bytes = 67108864'
assert_contains "${repo_dir}/scripts/usb/optimize-usb" 'tmpfs /var/cache/apt'
assert_contains "${repo_dir}/scripts/usb/optimize-usb" 'tmpfs /var/lib/apt/lists'
assert_contains "${repo_dir}/scripts/usb/optimize-usb" '60-usb-scheduler.rules'
assert_contains "${repo_dir}/scripts/usb/optimize-usb" 'ATTR{queue/read_ahead_kb}="1024"'
assert_contains "${repo_dir}/scripts/usb/optimize-usb" 'systemctl mask --now'
assert_contains "${repo_dir}/scripts/usb/optimize-usb" 'commit=60'
if grep -Fq 'systemctl mask' "${repo_dir}/scripts/usb/optimize-usb"; then
  if grep -Fq 'thermald.service' "${repo_dir}/scripts/usb/optimize-usb"; then
    echo "optimizer must not mask thermald" >&2
    exit 1
  fi
fi
if grep -Eq 'data=writeback|force-unsafe-io|min_free_kbytes' "${repo_dir}/scripts/usb/optimize-usb"; then
  echo "optimizer must not enable unreviewed unsafe I/O settings" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
had_env=false
[[ -f "${repo_dir}/.env" ]] && had_env=true
trap 'rm -rf "${tmp_dir}"; if [[ "${had_env}" == false ]]; then rm -f "${repo_dir}/.env"; fi' EXIT
if [[ "${had_env}" == false ]]; then
  printf '%s\n' \
    'RECOVERY_USB_ROOT_UUID="root-uuid"' \
    'VAULT_UUID="vault-uuid"' \
    'VAULT_MOUNTPOINT="/mnt/Vault"' > "${repo_dir}/.env"
fi
stub_bin="${tmp_dir}/bin"
mkdir -p "${stub_bin}"

cat > "${stub_bin}/sshd" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "${stub_bin}/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "${stub_bin}/getent" <<'EOF'
#!/usr/bin/env bash
printf '%s:x:%s:%s::%s:/bin/bash\n' "${SUDO_USER}" "$(id -u "${SUDO_USER}")" "$(id -g "${SUDO_USER}")" "${TEST_USER_HOME}"
EOF
cat > "${stub_bin}/curl" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then
    shift
    cat "${TEST_PUBLIC_KEY_FILE}" > "$1"
    exit 0
  fi
  shift
done
EOF
cat > "${stub_bin}/findmnt" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"SOURCE /"* ]]; then
  printf '%s\n' '/dev/mapper/usb-root'
elif [[ "$*" == *'--target /mnt/Vault'* || "$*" == *'SOURCE /mnt/Vault'* ]]; then
  printf '%s\n' '/dev/sdb1'
else
  exit 1
fi
EOF
cat > "${stub_bin}/lsblk" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *usb-root*|*/dev/sda) printf '%s\n' '/dev/sda disk' ;;
  *sdb1*|*sdb*) printf '%s\n' '/dev/sdb disk' ;;
  *) exit 1 ;;
esac
EOF
cat > "${stub_bin}/blkid" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *usb-root*) printf '%s\n' 'root-uuid' ;;
  *UUID=vault-uuid*) printf '%s\n' '/dev/sdb1' ;;
  *sdb1*) printf '%s\n' 'vault-uuid' ;;
  *) exit 1 ;;
esac
EOF
cat > "${stub_bin}/mountpoint" <<'EOF'
#!/usr/bin/env bash
[[ "$2" == '/mnt/Vault' ]]
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

ssh-keygen -q -t ed25519 -N '' -f "${tmp_dir}/test-key"
TEST_USER_HOME="${tmp_dir}/home"
mkdir -p "${TEST_USER_HOME}"

authorized_keys="${tmp_dir}/authorized_keys"
installed_bin="${tmp_dir}/installed-bin"
mkdir -p "${installed_bin}"
if sudo env PATH="${stub_bin}:${PATH}" \
  RECOVERY_USB_MAKE_CONTEXT='' RECOVERY_USB_MAKE_TARGET=usb-ssh \
  bash "${repo_dir}/scripts/usb/setup-ssh" >/dev/null 2>&1; then
  echo 'direct USB setup invocation was accepted' >&2
  exit 1
fi
ln -s "${repo_dir}/scripts/usb/setup-ssh" "${installed_bin}/setup-ssh"
sudo env PATH="${stub_bin}:${PATH}" \
  SUDO_USER="${USER}" AUTHORIZED_KEYS_FILE="${authorized_keys}" \
  TEST_PUBLIC_KEY_FILE="${tmp_dir}/test-key.pub" TEST_USER_HOME="${TEST_USER_HOME}" \
  RECOVERY_USB_MAKE_CONTEXT=1 RECOVERY_USB_MAKE_TARGET=usb-ssh \
  RECOVERY_USB_ROOT_UUID=root-uuid VAULT_UUID=vault-uuid VAULT_MOUNTPOINT=/mnt/Vault \
  bash "${repo_dir}/scripts/usb/setup-ssh" >/dev/null
sudo env PATH="${stub_bin}:${PATH}" \
  SUDO_USER="${USER}" AUTHORIZED_KEYS_FILE="${authorized_keys}" \
  TEST_PUBLIC_KEY_FILE="${tmp_dir}/test-key.pub" TEST_USER_HOME="${TEST_USER_HOME}" \
  RECOVERY_USB_MAKE_CONTEXT=1 RECOVERY_USB_MAKE_TARGET=usb-ssh \
  RECOVERY_USB_ROOT_UUID=root-uuid VAULT_UUID=vault-uuid VAULT_MOUNTPOINT=/mnt/Vault \
  bash "${installed_bin}/setup-ssh" >/dev/null

[[ "$(wc -l < "${authorized_keys}")" -eq 1 ]]

cat > "${stub_bin}/tailscale" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "status" ]]; then
  printf '%s\n' '{"BackendState":"NeedsLogin"}'
  exit 0
fi
if [[ "$1" == "up" ]]; then
  printf '%s\n' 'To authenticate, visit: https://login.tailscale.com/a/test-auth'
  exit 1
fi
exit 0
EOF
chmod +x "${stub_bin}/tailscale"

tailscale_output="$(sudo env PATH="${stub_bin}:${PATH}" \
  RECOVERY_USB_MAKE_CONTEXT=1 RECOVERY_USB_MAKE_TARGET=usb-tailscale \
  RECOVERY_USB_ROOT_UUID=root-uuid VAULT_UUID=vault-uuid VAULT_MOUNTPOINT=/mnt/Vault \
  bash "${repo_dir}/scripts/usb/setup-tailscale")"
grep -Fq 'https://login.tailscale.com/a/test-auth' <<<"${tailscale_output}"

cat > "${stub_bin}/tailscale" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "status" ]]; then
  printf '%s\n' '{"BackendState":"Running"}'
  exit 0
fi
printf 'tailscale up should not run when already authenticated\n' >&2
exit 1
EOF
chmod +x "${stub_bin}/tailscale"

tailscale_output="$(sudo env PATH="${stub_bin}:${PATH}" \
  RECOVERY_USB_MAKE_CONTEXT=1 RECOVERY_USB_MAKE_TARGET=usb-tailscale \
  RECOVERY_USB_ROOT_UUID=root-uuid VAULT_UUID=vault-uuid VAULT_MOUNTPOINT=/mnt/Vault \
  bash "${repo_dir}/scripts/usb/setup-tailscale")"
grep -Fq 'already authenticated and running' <<<"${tailscale_output}"

echo "setup command contract: pass"
