#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for script in hdd-secure-erase ssd-secure-erase nvme-secure-erase; do
  path="${repo_dir}/bin/${script}"
  grep -Fq 'source "${SCRIPT_DIR}/../lib/audit.sh"' "${path}" || fail "${script} does not source audit library"
  confirm_line="$(grep -n '^confirm_destructive ' "${path}" | cut -d: -f1)"
  gate_line="$(grep -n '^require_audit_vault$' "${path}" | cut -d: -f1)"
  begin_line="$(grep -n '^audit_begin ' "${path}" | cut -d: -f1)"
  [[ -n "${confirm_line}" && -n "${gate_line}" && -n "${begin_line}" ]] || fail "${script} audit lifecycle is incomplete"
  ((gate_line > confirm_line)) || fail "${script} audits before confirmation"
  ((begin_line > gate_line)) || fail "${script} begins audit before vault gate"
  grep -Fq 'audit_finish "${erase_status}"' "${path}" || fail "${script} does not finish audit"
done

printf '%s\n' 'secure erase audit contract: pass'
