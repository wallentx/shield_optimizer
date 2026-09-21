#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT_DIR/Shield-Optimizer.sh"

SHIELD_OPTIMIZER_TEST_MODE=1
export SHIELD_OPTIMIZER_TEST_MODE

# shellcheck disable=SC1090,SC1091
source "$SCRIPT"

failures=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  failures=$((failures + 1))
}

pass() {
  printf 'ok - %s\n' "$1"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local name="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$name"
  else
    fail "$name: expected [$expected], got [$actual]"
  fi
}

assert_true() {
  local name="$1"
  shift
  if "$@"; then
    pass "$name"
  else
    fail "$name"
  fi
}

assert_false() {
  local name="$1"
  shift
  if "$@"; then
    fail "$name"
  else
    pass "$name"
  fi
}

assert_eq "Alert" "$(sho_style red "Alert")" "style is plain when stdout is not a TTY"
assert_eq "Alert" "$(NO_COLOR=1 TERM=xterm SHO_FORCE_COLOR=1 sho_style red "Alert")" "NO_COLOR disables forced color"
assert_eq $'\033[31mAlert\033[0m' "$(NO_COLOR='' TERM=xterm SHO_FORCE_COLOR=1 sho_style red "Alert")" "forced color emits ANSI red"

assert_true "valid package accepts normal package id" sho_is_valid_package "com.google.android.tvlauncher"
assert_true "valid package accepts uppercase vendor segment from catalog" sho_is_valid_package "com.Funimation.FunimationNow.androidtv"
assert_false "valid package rejects shell metacharacter" sho_is_valid_package "com.example.app;reboot"
assert_false "valid package rejects single segment framework token" sho_is_valid_package "android"
assert_false "valid package rejects leading digit segment" sho_is_valid_package "com.1bad.app"

assert_eq "never" "$(sho_safety_kind "com.android.systemui")" "safety blocks System UI"
assert_eq "caution" "$(sho_safety_kind "com.android.providers.tv")" "safety warns for TV provider"
assert_eq "safe" "$(sho_safety_kind "com.example.unlisted")" "safety defaults unlisted package to safe"

assert_eq "shield" "$(sho_detect_device_type "NVIDIA" "Shield Android TV" "mdarcy" "NVIDIA")" "detects Shield by brand"
assert_eq "shield" "$(sho_detect_device_type "" "" "foster" "")" "detects Shield by codename"
assert_eq "googletv" "$(sho_detect_device_type "onn" "Onn 4K Pro" "ott_xxx" "Amlogic")" "detects Google TV by Onn/Amlogic"
assert_eq "googletv" "$(sho_detect_device_type "Google" "Chromecast" "sabrina" "Google")" "detects Google TV by Chromecast"
assert_eq "firetv" "$(sho_detect_device_type "Amazon" "Fire TV Stick" "aftmm" "Amazon")" "detects Fire TV"
assert_eq "androidtv" "$(sho_detect_device_type "Generic" "Android TV Box" "rk3328" "Generic")" "detects generic Android TV"
assert_eq "unknown" "$(sho_detect_device_type "Generic" "Generic TV Box" "rk3328" "Generic")" "detects unknown device"

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/shield-optimizer-test.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT
mkdir -p "$tmp_root/snapshots"
touch "$tmp_root/snapshots/good.json"
touch "$tmp_root/outside.json"

assert_true "snapshot path allows file inside snapshot root" sho_snapshot_path_allowed "$tmp_root/snapshots" "$tmp_root/snapshots/good.json"
assert_false "snapshot path rejects sibling outside snapshot root" sho_snapshot_path_allowed "$tmp_root/snapshots" "$tmp_root/outside.json"
assert_false "snapshot path rejects traversal outside snapshot root" sho_snapshot_path_allowed "$tmp_root/snapshots" "$tmp_root/snapshots/../outside.json"

if command -v jq >/dev/null 2>&1; then
  assert_eq "true" "$(sho_load_catalog "shield" | jq -r 'any(.[]; .package == "com.nvidia.stats")')" "Shield catalog includes Shield-specific app"
  assert_eq "false" "$(sho_load_catalog "unknown" | jq -r 'any(.[]; .package == "com.nvidia.stats")')" "Unknown catalog excludes Shield-specific app"
else
  printf 'skip - catalog merge tests need jq\n'
fi

if (( failures > 0 )); then
  printf '%d test(s) failed\n' "$failures" >&2
  exit 1
fi

printf 'all tests passed\n'
