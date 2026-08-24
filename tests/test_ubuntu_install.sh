#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

# shellcheck source=../lib/ubuntu_install.sh
source "${repo_dir}/lib/ubuntu_install.sh"

export HOST_ID='slinky'
export TARGET_DISK='/dev/disk/by-id/wwn-test'
export UBUNTU_INSTALLER_SOURCE='/cdrom'
export UBUNTU_IDENTITY_FILE="${tmp_dir}/identity.env"
export UBUNTU_LUKS_KEY_FILE='/mnt/Vault/recovery-toolkit-vault/hosts/slinky/provisioning/op/luks/luks.key'

cat >"${UBUNTU_IDENTITY_FILE}" <<'EOF'
UBUNTU_USERNAME=operator
UBUNTU_PASSWORD_HASH=$6$rounds=5000$example$hash
UBUNTU_SSH_PUBLIC_KEY=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexample operator
EOF
chmod 0600 "${UBUNTU_IDENTITY_FILE}"

validate_ubuntu_install_profile
yaml="$(render_ubuntu_autoinstall 1073741824 2147483648 0 /run/recovery-luks-key)"
grep -Fq 'autoinstall:' <<<"${yaml}"
grep -Fq 'type: dm_crypt' <<<"${yaml}"
grep -Fq 'preserve: true' <<<"${yaml}"
grep -Fq 'fstype: xfs' <<<"${yaml}"
grep -Fq 'keyfile: /run/recovery-luks-key' <<<"${yaml}"
if grep -Fq 'UBUNTU_PASSWORD_HASH' <<<"${yaml}"; then
  echo 'identity variable name leaked into YAML' >&2
  exit 1
fi
expected_password="\$6\$rounds=5000\$example\$hash"
grep -Fq "password: '${expected_password}'" <<<"${yaml}"
yaml_with_crypt_size="$(render_ubuntu_autoinstall 1073741824 2147483648 3221225472 /run/recovery-luks-key)"
grep -Fq '        size: 3221225472B' <<<"${yaml_with_crypt_size}"
if command -v ruby >/dev/null 2>&1; then
  ruby -e 'require "yaml"; YAML.safe_load(STDIN.read)' <<<"${yaml}" >/dev/null
  ruby -e 'require "yaml"; YAML.safe_load(STDIN.read)' <<<"${yaml_with_crypt_size}" >/dev/null
fi

rm -f "${UBUNTU_IDENTITY_FILE}"
if validate_ubuntu_install_profile >/dev/null 2>&1; then
  echo 'missing identity file unexpectedly accepted' >&2
  exit 1
fi

cat >"${UBUNTU_IDENTITY_FILE}" <<'EOF'
UBUNTU_USERNAME=operator
UBUNTU_PASSWORD_HASH=$6$rounds=5000$example$hash
UBUNTU_SSH_PUBLIC_KEY=$'ssh-ed25519 AAAA\ninvalid'
EOF
chmod 0600 "${UBUNTU_IDENTITY_FILE}"
if validate_ubuntu_install_profile >/dev/null 2>&1; then
  echo 'multiline SSH key unexpectedly accepted' >&2
  exit 1
fi

chmod 0644 "${UBUNTU_IDENTITY_FILE}"
if validate_ubuntu_install_profile >/dev/null 2>&1; then
  echo 'broad identity permissions unexpectedly accepted' >&2
  exit 1
fi

installer_bin="${repo_dir}/bin/install-ubuntu-server"
grep -Fq 'subiquity' "${installer_bin}"
grep -Fq -- '--autoinstall' "${installer_bin}"
grep -Fq 'require_audit_vault' "${installer_bin}"
grep -Fq 'audit_finish' "${installer_bin}"
grep -Fq 'copy_secret_to_runtime' "${installer_bin}"
grep -Fq 'audit_vault_path' "${installer_bin}"
grep -Fq 'secret_sha256' "${installer_bin}"
grep -Fq 'DRY_RUN=1' "${installer_bin}"
if grep -Eq 'reboot|kexec' "${installer_bin}"; then
  echo 'installer command must not reboot or kexec' >&2
  exit 1
fi

printf '%s\n' 'ubuntu installer profile tests: pass'
