#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/recovery_profile.sh
source "${repo_dir}/lib/recovery_profile.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

expect_success() {
  "$@" || fail "expected success: $*"
}

expect_failure() {
  if "$@"; then
    fail "expected failure: $*"
  fi
}

RECOVERY_INTERFACE="enp1s0f0"
RECOVERY_GATEWAY="10.0.40.1"
RECOVERY_HOST_IP="10.0.40.2"
RECOVERY_SUBNET="10.0.40.0/24"
RECOVERY_SSH_PORT="2222"
RECOVERY_CLIENT_CIDR="10.0.50.0/24"
validate_recovery_profile

RECOVERY_HOST_IP="10.0.41.2"
expect_failure validate_recovery_profile
RECOVERY_HOST_IP="10.0.40.2"

RECOVERY_GATEWAY="10.0.41.1"
expect_failure validate_recovery_profile
RECOVERY_GATEWAY="10.0.40.1"

RECOVERY_SSH_PORT="65536"
expect_failure validate_recovery_profile
RECOVERY_SSH_PORT="2222"

RECOVERY_CLIENT_CIDR="10.0.40.0/33"
expect_failure validate_recovery_profile
RECOVERY_CLIENT_CIDR=""

unset RECOVERY_INTERFACE
expect_failure validate_recovery_profile

printf '%s\n' 'recovery profile tests: pass'
