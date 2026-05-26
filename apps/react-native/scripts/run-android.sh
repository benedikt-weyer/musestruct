#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
workspace_root="$(cd "$project_root/../.." && pwd)"
android_dir="$project_root/android"

resolve_dev_server_port() {
  local arg
  local next_is_port_value=0

  for arg in "$@"; do
    if [[ "$next_is_port_value" -eq 1 ]]; then
      printf '%s\n' "$arg"
      return 0
    fi

    case "$arg" in
      --port)
        next_is_port_value=1
        ;;
      --port=*)
        printf '%s\n' "${arg#--port=}"
        return 0
        ;;
    esac
  done

  printf '8081\n'
}

resolve_react_native_cli() {
  local cli_path

  for cli_path in \
    "$project_root/node_modules/.bin/react-native" \
    "$workspace_root/node_modules/.bin/react-native"
  do
    if [[ -x "$cli_path" ]]; then
      printf '%s\n' "$cli_path"
      return 0
    fi
  done

  return 1
}

is_port_in_use() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    ss -ltn | awk -v port=":$port" '$4 ~ port"$" { found=1 } END { exit found ? 0 : 1 }'
    return $?
  fi

  return 1
}

ensure_adb_reverse() {
  local port="$1"

  if ! command -v adb >/dev/null 2>&1; then
    return 0
  fi

  if ! adb get-state >/dev/null 2>&1; then
    return 0
  fi

  adb reverse "tcp:$port" "tcp:$port" >/dev/null
}

is_physical_android_device() {
  if ! command -v adb >/dev/null 2>&1; then
    return 1
  fi

  if ! adb get-state >/dev/null 2>&1; then
    return 1
  fi

  [[ "$(adb shell getprop ro.kernel.qemu 2>/dev/null | tr -d '\r')" != "1" ]]
}

has_dev_server_ip_override() {
  local arg

  for arg in "$@"; do
    if [[ "$arg" == *reactNativeDevServerIp=* ]]; then
      return 0
    fi
  done

  return 1
}

resolve_sdk_root() {
  if [[ -n "${ANDROID_HOME:-}" && -d "${ANDROID_HOME}" ]]; then
    printf '%s\n' "$ANDROID_HOME"
    return 0
  fi

  if [[ -n "${ANDROID_SDK_ROOT:-}" && -d "${ANDROID_SDK_ROOT}" ]]; then
    printf '%s\n' "$ANDROID_SDK_ROOT"
    return 0
  fi

  if command -v adb >/dev/null 2>&1; then
    local adb_bin sdk_root
    adb_bin="$(command -v adb)"
    sdk_root="$(dirname "$(dirname "$adb_bin")")"

    if [[ -d "$sdk_root/platforms" ]]; then
      printf '%s\n' "$sdk_root"
      return 0
    fi
  fi

  return 1
}

sdk_root="$(resolve_sdk_root || true)"
react_native_cli="$(resolve_react_native_cli || true)"
dev_server_port="$(resolve_dev_server_port "$@")"

if [[ -z "$sdk_root" ]]; then
  echo "Android SDK location not found. Set ANDROID_HOME or ANDROID_SDK_ROOT, or ensure adb is on PATH." >&2
  exit 1
fi

if [[ ! -x "$react_native_cli" ]]; then
  echo "React Native CLI not found at $react_native_cli. Run npm install first." >&2
  exit 1
fi

cat > "$android_dir/local.properties" <<EOF
sdk.dir=$sdk_root
EOF

export ANDROID_HOME="${ANDROID_HOME:-$sdk_root}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$sdk_root}"

cd "$project_root"

run_android_args=(run-android "$@")

ensure_adb_reverse "$dev_server_port"

if is_port_in_use "$dev_server_port"; then
  run_android_args+=(--no-packager)
fi

if is_physical_android_device && ! has_dev_server_ip_override "$@"; then
  run_android_args+=(--extra-params "-PreactNativeDevServerIp=localhost")
fi

exec "$react_native_cli" "${run_android_args[@]}"