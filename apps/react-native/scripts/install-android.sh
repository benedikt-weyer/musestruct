#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
android_dir="$project_root/android"
gradle_wrapper="$android_dir/gradlew"

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

if [[ -z "$sdk_root" ]]; then
  echo "Android SDK location not found. Set ANDROID_HOME or ANDROID_SDK_ROOT, or ensure adb is on PATH." >&2
  exit 1
fi

if [[ ! -x "$gradle_wrapper" ]]; then
  echo "Gradle wrapper not found at $gradle_wrapper." >&2
  exit 1
fi

cat > "$android_dir/local.properties" <<EOF
sdk.dir=$sdk_root
EOF

export ANDROID_HOME="${ANDROID_HOME:-$sdk_root}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$sdk_root}"

cd "$android_dir"

exec "$gradle_wrapper" app:installRelease "$@"