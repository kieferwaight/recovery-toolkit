#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

host_commands='inspect-disk hdd-secure-erase nvme-secure-erase provision-luks setup-initramfs-unlock ssd-secure-erase install-ubuntu-server'
usb_commands='optimize-usb setup-overlay-boot setup-ssh setup-tailscale setup-vault'

for command in ${host_commands}; do
  [[ -f "${repo_dir}/bin/${command}" ]] || fail "missing host command: ${command}"
done
for command in ${usb_commands}; do
  [[ -f "${repo_dir}/scripts/usb/${command}" ]] || fail "missing USB script: ${command}"
  [[ ! -e "${repo_dir}/bin/${command}" ]] || fail "USB command remains in bin: ${command}"
  [[ ! -x "${repo_dir}/scripts/usb/${command}" ]] || fail "USB script is directly executable: ${command}"
done
for command in preflight install-packages; do
  [[ -f "${repo_dir}/scripts/usb/${command}" ]] || fail "missing USB support script: ${command}"
  [[ ! -x "${repo_dir}/scripts/usb/${command}" ]] || fail "USB support script is directly executable: ${command}"
done

makefile="${repo_dir}/Makefile"
grep -Fq 'usb-preflight' "${makefile}" || fail 'Makefile lacks usb-preflight target'
grep -Fq 'usb-install' "${makefile}" || fail 'Makefile lacks usb-install target'
grep -Fq 'RECOVERY_DISK_UUID' "${makefile}" || fail 'Makefile does not display the USB root UUID'
grep -Fq 'VAULT_UUID' "${makefile}" || fail 'Makefile does not display the vault UUID'
grep -Fq 'for script in bin/*' "${makefile}" || fail 'install loop is not host-only'
! grep -Fq 'for script in scripts/usb/*' "${makefile}" || fail 'USB scripts must not be installed'
grep -Fq 'install: env symlinks cleanup-legacy-usb-links' "${makefile}" || fail 'install target includes USB setup'
grep -Fq -- '--target-root' "${repo_dir}/README.md" || fail 'README lacks host target-root workflow'

printf '%s\n' 'tool boundary contract: pass'
