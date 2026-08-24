#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains() {
  local file=$1
  local text=$2

  grep -Fq -- "$text" "$file"
}

assert_contains "${repo_dir}/bin/setup-ssh" "KEYS_URL=\"\${GITHUB_KEYS_URL:-https://github.com/kieferwaight.keys}\""
assert_contains "${repo_dir}/bin/setup-ssh" 'grep -Fqx --'
assert_contains "${repo_dir}/bin/setup-ssh" 'systemctl enable --now'
assert_contains "${repo_dir}/bin/setup-tailscale" 'https://tailscale.com/install.sh'
assert_contains "${repo_dir}/bin/setup-tailscale" 'tailscale up --qr=false --timeout=10s'
assert_contains "${repo_dir}/bin/setup-tailscale" 'login'
assert_contains "${repo_dir}/.env.example" 'VAULT_UUID=""'
assert_contains "${repo_dir}/.env.example" 'VAULT_MOUNTPOINT="/mnt/Vault"'
assert_contains "${repo_dir}/.env.example" 'VAULT_SUBDIR="recovery-toolkit-vault"'
assert_contains "${repo_dir}/bin/setup-vault" 'systemd-escape --path --suffix=mount'
assert_contains "${repo_dir}/bin/setup-vault" 'ID_FS_UUID'
assert_contains "${repo_dir}/bin/setup-vault" 'BindsTo='
assert_contains "${repo_dir}/bin/setup-vault" 'noatime,lazytime,nosuid,nodev'
assert_contains "${repo_dir}/lib/common.sh" 'recovery_profile.sh'
assert_contains "${repo_dir}/lib/common.sh" 'lsblk -sno NAME,TYPE'
if grep -Fq '/etc/fstab' "${repo_dir}/bin/setup-vault"; then
  echo "vault setup must not use fstab" >&2
  exit 1
fi
assert_contains "${repo_dir}/README.md" "- \`setup-ssh\` - enables SSH and authorizes GitHub public keys"
assert_contains "${repo_dir}/README.md" "- \`setup-tailscale\` - installs and authorizes Tailscale"
assert_contains "${repo_dir}/bin/optimize-usb" 'backup_dir="/root/recovery-toolkit-optimization-'
assert_contains "${repo_dir}/bin/optimize-usb" 'apt-get purge -y snapd'
assert_contains "${repo_dir}/bin/optimize-usb" 'vm.dirty_background_bytes = 67108864'
assert_contains "${repo_dir}/bin/optimize-usb" 'tmpfs /var/cache/apt'
assert_contains "${repo_dir}/bin/optimize-usb" 'tmpfs /var/lib/apt/lists'
assert_contains "${repo_dir}/bin/optimize-usb" '60-usb-scheduler.rules'
assert_contains "${repo_dir}/bin/optimize-usb" 'ATTR{queue/read_ahead_kb}="1024"'
assert_contains "${repo_dir}/bin/optimize-usb" 'systemctl mask --now'
assert_contains "${repo_dir}/bin/optimize-usb" 'commit=60'
if grep -Fq 'systemctl mask' "${repo_dir}/bin/optimize-usb"; then
  if grep -Fq 'thermald.service' "${repo_dir}/bin/optimize-usb"; then
    echo "optimizer must not mask thermald" >&2
    exit 1
  fi
fi
if grep -Eq 'data=writeback|force-unsafe-io|min_free_kbytes' "${repo_dir}/bin/optimize-usb"; then
  echo "optimizer must not enable unreviewed unsafe I/O settings" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
had_env=false
[[ -f "${repo_dir}/.env" ]] && had_env=true
trap 'rm -rf "${tmp_dir}"; if [[ "${had_env}" == false ]]; then rm -f "${repo_dir}/.env"; fi' EXIT
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
chmod +x "${stub_bin}"/*

ssh-keygen -q -t ed25519 -N '' -f "${tmp_dir}/test-key"
TEST_USER_HOME="${tmp_dir}/home"
mkdir -p "${TEST_USER_HOME}"

authorized_keys="${tmp_dir}/authorized_keys"
installed_bin="${tmp_dir}/installed-bin"
mkdir -p "${installed_bin}"
ln -s "${repo_dir}/bin/setup-ssh" "${installed_bin}/setup-ssh"
sudo env PATH="${stub_bin}:${PATH}" \
  SUDO_USER="${USER}" AUTHORIZED_KEYS_FILE="${authorized_keys}" \
  TEST_PUBLIC_KEY_FILE="${tmp_dir}/test-key.pub" TEST_USER_HOME="${TEST_USER_HOME}" \
  "${repo_dir}/bin/setup-ssh" >/dev/null
sudo env PATH="${stub_bin}:${PATH}" \
  SUDO_USER="${USER}" AUTHORIZED_KEYS_FILE="${authorized_keys}" \
  TEST_PUBLIC_KEY_FILE="${tmp_dir}/test-key.pub" TEST_USER_HOME="${TEST_USER_HOME}" \
  "${installed_bin}/setup-ssh" >/dev/null

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

tailscale_output="$(sudo env PATH="${stub_bin}:${PATH}" "${repo_dir}/bin/setup-tailscale")"
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

tailscale_output="$(sudo env PATH="${stub_bin}:${PATH}" "${repo_dir}/bin/setup-tailscale")"
grep -Fq 'already authenticated and running' <<<"${tailscale_output}"

echo "setup command contract: pass"
