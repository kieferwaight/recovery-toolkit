#!/usr/bin/env bash

# Keep plaintext key material in a protected runtime directory and out of the
# repository, normal logs, and persistent USB root filesystem.

_key_material_runtime_dir() {
  printf '%s\n' "${KEY_MATERIAL_RUNTIME_DIR:-/dev/shm}"
}

_key_material_validate_prefix() {
  [[ "$1" =~ ^[a-zA-Z0-9_.-]+$ ]]
}

create_runtime_key() {
  local prefix="${1:-recovery-key}"
  local size_bytes="${2:-64}"
  local runtime_dir key_file

  _key_material_validate_prefix "${prefix}" || return 1
  [[ "${size_bytes}" =~ ^[1-9][0-9]*$ ]] || return 1
  runtime_dir="$(_key_material_runtime_dir)"
  [[ -d "${runtime_dir}" ]] || return 1
  umask 077
  key_file="$(mktemp "${runtime_dir}/${prefix}.XXXXXX")" || return 1
  if ! dd if=/dev/urandom of="${key_file}" bs="${size_bytes}" count=1 status=none; then
    rm -f "${key_file}"
    return 1
  fi
  chmod 0600 "${key_file}"
  printf '%s\n' "${key_file}"
}

copy_secret_to_runtime() {
  local source="$1"
  local prefix="${2:-recovery-secret}"
  local runtime_dir secret_file

  [[ -f "${source}" ]] || return 1
  _key_material_validate_prefix "${prefix}" || return 1
  runtime_dir="$(_key_material_runtime_dir)"
  [[ -d "${runtime_dir}" ]] || return 1
  umask 077
  secret_file="$(mktemp "${runtime_dir}/${prefix}.XXXXXX")" || return 1
  if ! install -m 0600 "${source}" "${secret_file}"; then
    rm -f "${secret_file}"
    return 1
  fi
  printf '%s\n' "${secret_file}"
}

secret_sha256() {
  local source="$1"
  [[ -f "${source}" ]] || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${source}" | awk '{print $1}'
  else
    shasum -a 256 "${source}" | awk '{print $1}'
  fi
}

cleanup_runtime_secret() {
  local source="$1"
  local runtime_dir
  runtime_dir="$(_key_material_runtime_dir)"
  case "${source}" in
    "${runtime_dir}"/*) rm -f -- "${source}" ;;
    *)
      log_error "Refusing to remove a non-runtime secret path: ${source}"
      return 2
      ;;
  esac
}
