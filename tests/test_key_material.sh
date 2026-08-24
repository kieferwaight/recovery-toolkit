#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

# shellcheck source=../lib/common.sh
source "${repo_dir}/lib/common.sh"
# shellcheck source=../lib/key_material.sh
source "${repo_dir}/lib/key_material.sh"
# shellcheck source=../lib/audit.sh
source "${repo_dir}/lib/audit.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

KEY_MATERIAL_RUNTIME_DIR="${tmp_dir}/runtime"
LOG_DIR="${tmp_dir}/logs"
mkdir -p "${KEY_MATERIAL_RUNTIME_DIR}" "${LOG_DIR}"
secret_file="${tmp_dir}/secret"
printf '%s\n' 'fixture-secret-content' > "${secret_file}"

generated_key="$(create_runtime_key 'fixture-key' 64)" || fail 'runtime key creation failed'
[[ -f "${generated_key}" ]] || fail 'runtime key was not created'
[[ "$(stat -c '%a' "${generated_key}" 2>/dev/null || stat -f '%Lp' "${generated_key}")" == 600 ]] || fail 'runtime key mode is not 0600'
[[ "$(wc -c < "${generated_key}")" -eq 64 ]] || fail 'runtime key has incorrect size'

staged_secret="$(copy_secret_to_runtime "${secret_file}" 'fixture-copy')" || fail 'secret staging failed'
[[ -f "${staged_secret}" ]] || fail 'staged secret was not created'
[[ "$(cat "${staged_secret}")" == 'fixture-secret-content' ]] || fail 'staged secret contents changed'
[[ "$(stat -c '%a' "${staged_secret}" 2>/dev/null || stat -f '%Lp' "${staged_secret}")" == 600 ]] || fail 'staged secret mode is not 0600'
secret_hash="$(secret_sha256 "${staged_secret}")"
[[ "${secret_hash}" =~ ^[[:xdigit:]]{64}$ ]] || fail 'secret checksum is invalid'
log_info "staged secret checksum ${secret_hash}"
if grep -R -Fq 'fixture-secret-content' "${LOG_DIR}"; then
  fail 'plaintext secret escaped into logs'
fi

cleanup_runtime_secret "${generated_key}"
cleanup_runtime_secret "${staged_secret}"
[[ ! -e "${generated_key}" && ! -e "${staged_secret}" ]] || fail 'runtime secret cleanup failed'

AUDIT_ROOT="${tmp_dir}/audit"
mkdir -p "${AUDIT_ROOT}"
event_path="$(audit_vault_path 'hosts/test/events/key.env')" || fail 'valid vault path rejected'
[[ "${event_path}" == "${AUDIT_ROOT}/hosts/test/events/key.env" ]] || fail 'vault path was not rooted under AUDIT_ROOT'
if audit_vault_path '/tmp/escape'; then
  fail 'absolute vault path accepted'
fi
if audit_vault_path '../escape'; then
  fail 'parent traversal vault path accepted'
fi

audit_record_event 'hosts/test/events/key.env' $'event=staged\nchecksum=fixture' || fail 'vault event write failed'
[[ "$(stat -c '%a' "${event_path}" 2>/dev/null || stat -f '%Lp' "${event_path}")" == 600 ]] || fail 'vault event mode is not 0600'
grep -Fq 'event=staged' "${event_path}" || fail 'vault event content missing'

printf '%s\n' 'key material tests: pass'
