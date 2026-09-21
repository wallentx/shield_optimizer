#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SHO_VERSION="0.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOME_DIR="${HOME:-$SCRIPT_DIR}"
DATA_DIR="${SHIELD_OPTIMIZER_DATA_DIR:-${XDG_DATA_HOME:-$HOME_DIR/.local/share}/ShieldOptimizer}"
SNAPSHOT_DIR="${SHIELD_OPTIMIZER_SNAPSHOT_DIR:-$DATA_DIR/snapshots}"

ADB_BIN=""
CURRENT_DEVICE=""
SHO_SUBNET=""
SHO_ACTION="menu"

sho_color_enabled() {
  [[ "${NO_COLOR:-}" == "" ]] || return 1
  [[ "${TERM:-}" != "dumb" ]] || return 1
  [[ "${SHO_FORCE_COLOR:-}" == "1" || -t 1 ]]
}

sho_color_code() {
  case "$1" in
    reset) printf '0' ;;
    bold) printf '1' ;;
    dim) printf '2' ;;
    cyan) printf '36' ;;
    green) printf '32' ;;
    yellow) printf '33' ;;
    red) printf '31' ;;
    magenta) printf '35' ;;
    white) printf '37' ;;
    *) return 1 ;;
  esac
}

sho_style() {
  local style="$1"
  local code
  shift || true
  if sho_color_enabled && code="$(sho_color_code "$style")"; then
    printf '\033[%sm%s\033[0m' "$code" "$*"
  else
    printf '%s' "$*"
  fi
}

sho_box_line() {
  sho_style cyan "+----------------------------------------------------------------------+"
  printf '\n'
}

sho_box_row() {
  local text="$1"
  local style="${2:-white}"
  local row
  printf -v row "| %-68.68s |" "$text"
  sho_style "$style" "$row"
  printf '\n'
}

sho_menu_header() {
  local title="$1"
  local subtitle="${2:-}"
  printf '\n'
  sho_box_line
  sho_box_row "$title" bold
  if [[ -n "$subtitle" ]]; then
    sho_box_row "$subtitle" dim
  fi
  sho_box_line
}

sho_menu_item() {
  local key="$1"
  local label="$2"
  local hint="${3:-}"
  local tone="${4:-normal}"
  local label_cell styled_key styled_label styled_hint

  styled_key="$(sho_style cyan "$(printf '%2s)' "$key")")"
  printf -v label_cell '%-34.34s' "$label"
  case "$tone" in
    success) styled_label="$(sho_style green "$label_cell")" ;;
    warn) styled_label="$(sho_style yellow "$label_cell")" ;;
    danger) styled_label="$(sho_style red "$label_cell")" ;;
    dim) styled_label="$(sho_style dim "$label_cell")" ;;
    *) styled_label="$label_cell" ;;
  esac
  styled_hint=""
  if [[ -n "$hint" ]]; then
    styled_hint="$(sho_style dim "$hint")"
  fi
  printf '  %s %s %s\n' "$styled_key" "$styled_label" "$styled_hint"
}

sho_info() {
  printf '%s %s\n' "$(sho_style green "OK")" "$*"
}

sho_warn() {
  printf '%s %s\n' "$(sho_style yellow "WARN:")" "$*" >&2
}

sho_error() {
  printf '%s %s\n' "$(sho_style red "ERROR:")" "$*" >&2
}

sho_pause() {
  local _
  printf '\n%s' "$(sho_style dim "Press Enter to continue...")"
  read -r _ || true
}

sho_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

sho_trim_cr() {
  tr -d '\r'
}

sho_usage() {
  printf 'Shield-Optimizer.sh %s - Bash Android TV optimizer for Linux and Termux\n\n' "$SHO_VERSION"
  cat <<'USAGE'

Usage:
  ./Shield-Optimizer.sh                 Start interactive menu
  ./Shield-Optimizer.sh --check-deps     List missing required/optional tools
  ./Shield-Optimizer.sh --list-devices   List ADB devices
  ./Shield-Optimizer.sh --subnet A.B.C   Use subnet for network scan
  ./Shield-Optimizer.sh --help           Show this help

Required dependencies:
  bash, adb, jq, coreutils-style tools: awk, basename, cat, date, dirname, grep, mkdir, mktemp, sed, tr

Optional helpers:
  ip, ping, timeout, nc

The script never installs dependencies. If a required tool is missing, it prints
the missing tool list and exits before running optimizer actions.
USAGE
}

sho_resolve_adb() {
  local candidate
  if [[ -n "${SHIELD_OPTIMIZER_ADB:-}" ]]; then
    if [[ -x "$SHIELD_OPTIMIZER_ADB" ]]; then
      printf '%s\n' "$SHIELD_OPTIMIZER_ADB"
      return 0
    fi
    return 1
  fi

  for candidate in "$SCRIPT_DIR/platform-tools/adb" "$SCRIPT_DIR/adb"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if command -v adb >/dev/null 2>&1; then
    command -v adb
    return 0
  fi

  return 1
}

sho_refresh_adb() {
  ADB_BIN="$(sho_resolve_adb || true)"
}

sho_missing_required_tools() {
  local missing=()
  local adb_path
  local tool

  if [[ -z "${BASH_VERSION:-}" ]]; then
    missing+=("bash")
  fi

  adb_path="$(sho_resolve_adb || true)"
  if [[ -z "$adb_path" ]]; then
    missing+=("adb (or set SHIELD_OPTIMIZER_ADB=/path/to/adb)")
  fi

  for tool in jq awk basename cat date dirname grep mkdir mktemp sed tr; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done

  printf '%s\n' "${missing[@]}"
}

sho_missing_optional_tools() {
  local missing=()
  local tool
  for tool in ip ping timeout nc; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done
  printf '%s\n' "${missing[@]}"
}

sho_check_dependencies() {
  local required optional
  sho_refresh_adb
  required="$(sho_missing_required_tools)"
  optional="$(sho_missing_optional_tools)"

  if [[ -n "$required" ]]; then
    sho_error "Missing required dependencies:"
    printf '%s\n' "$required" | sed 's/^/  - /' >&2
  else
    sho_info "Required dependencies: OK"
    sho_info "adb: $ADB_BIN"
  fi

  if [[ -n "$optional" ]]; then
    sho_warn "Missing optional helpers:"
    printf '%s\n' "$optional" | sed 's/^/  - /' >&2
  else
    sho_info "Optional helpers: OK"
  fi

  [[ -z "$required" ]]
}

sho_require_dependencies() {
  if ! sho_check_dependencies; then
    exit 1
  fi
}

sho_parse_args() {
  while (($# > 0)); do
    case "$1" in
      --help|-h)
        SHO_ACTION="help"
        ;;
      --check-deps)
        SHO_ACTION="check-deps"
        ;;
      --list-devices)
        SHO_ACTION="list-devices"
        ;;
      --subnet)
        shift
        if (($# == 0)); then
          sho_error "--subnet requires a value like 192.168.1"
          exit 2
        fi
        SHO_SUBNET="$1"
        ;;
      --subnet=*)
        SHO_SUBNET="${1#--subnet=}"
        ;;
      *)
        sho_error "Unknown argument: $1"
        sho_usage
        exit 2
        ;;
    esac
    shift
  done
}

sho_adb_raw() {
  "$ADB_BIN" "$@"
}

sho_adb() {
  if [[ -n "$CURRENT_DEVICE" ]]; then
    "$ADB_BIN" -s "$CURRENT_DEVICE" "$@"
  else
    "$ADB_BIN" "$@"
  fi
}

sho_adb_shell() {
  sho_adb shell "$@" 2>&1 | sho_trim_cr
}

sho_shell_ok() {
  local output="$1"
  [[ "$output" != *"Exception"* && "$output" != *"Error:"* && "$output" != *"Unknown package"* ]]
}

sho_device_serials() {
  sho_adb_raw devices | awk 'NR > 1 && $2 == "device" { print $1 }'
}

sho_list_devices() {
  sho_adb_raw start-server >/dev/null
  local devices
  devices="$(sho_adb_raw devices | sho_trim_cr)"
  if [[ -z "$devices" ]]; then
    sho_info "No ADB output."
    return 0
  fi
  printf '%s\n' "$devices"
}

sho_restart_adb() {
  sho_info "Restarting ADB server..."
  sho_adb_raw kill-server >/dev/null 2>&1 || true
  sho_adb_raw start-server
}

sho_prompt() {
  local prompt="$1"
  local value=""
  read -r -p "$(sho_style cyan "$prompt")" value || true
  printf '%s' "$value"
}

sho_confirm() {
  local prompt="$1"
  local default="${2:-n}"
  local suffix answer
  case "$default" in
    y|Y) suffix="[Y/n]" ;;
    *) suffix="[y/N]" ;;
  esac
  read -r -p "$prompt $suffix " answer || answer=""
  answer="$(sho_lower "$answer")"
  if [[ -z "$answer" ]]; then
    answer="$(sho_lower "$default")"
  fi
  [[ "$answer" == "y" || "$answer" == "yes" ]]
}

sho_is_valid_package() {
  local package="${1:-}"
  [[ "$package" =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$ ]]
}

sho_is_valid_setting_key() {
  local key="${1:-}"
  [[ "$key" =~ ^[A-Za-z0-9_\.]+$ ]]
}

sho_shell_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

sho_write_setting() {
  local namespace="$1"
  local key="$2"
  local value="${3:-}"
  local cmd output

  if [[ ! "$namespace" =~ ^(global|secure|system)$ ]]; then
    sho_error "Invalid settings namespace: $namespace"
    return 1
  fi
  if ! sho_is_valid_setting_key "$key"; then
    sho_error "Invalid settings key: $key"
    return 1
  fi

  if [[ -z "$value" ]]; then
    cmd="settings delete $namespace $key"
  else
    cmd="settings put $namespace $key $(sho_shell_quote "$value")"
  fi

  output="$(sho_adb_shell "$cmd" || true)"
  if sho_shell_ok "$output"; then
    [[ -n "$output" ]] && printf '%s\n' "$output"
    return 0
  fi
  sho_error "$output"
  return 1
}

sho_safety_kind() {
  case "${1:-}" in
    android|\
    com.android.systemui|\
    com.android.settings|\
    com.android.tv.settings|\
    com.android.providers.settings|\
    com.android.shell|\
    com.android.packageinstaller|\
    com.google.android.packageinstaller|\
    com.android.permissioncontroller|\
    com.google.android.permissioncontroller|\
    com.android.externalstorage|\
    com.android.providers.media|\
    com.android.providers.downloads|\
    com.android.providers.downloads.ui|\
    com.android.bluetooth|\
    com.android.bluetoothmidiservice|\
    com.android.inputdevices|\
    com.android.keychain|\
    com.android.certinstaller|\
    com.google.android.gms|\
    com.google.android.gsf|\
    com.google.android.gsf.login|\
    com.google.android.ext.services|\
    com.android.location.fused|\
    com.android.providers.calendar|\
    com.android.providers.contacts|\
    com.google.android.inputmethod.latin|\
    com.google.android.leanbackkeyboard|\
    com.android.inputmethod.latin)
      printf 'never\n'
      ;;
    com.android.providers.tv|\
    com.google.android.tts|\
    com.google.android.katniss|\
    com.google.android.speech.pumpkin|\
    com.google.android.apps.mediashell|\
    com.android.vending|\
    com.google.android.feedback|\
    com.android.printspooler)
      printf 'caution\n'
      ;;
    *)
      printf 'safe\n'
      ;;
  esac
}

sho_safety_reason() {
  case "${1:-}" in
    android) printf 'The Android framework. Disabling bricks the device.\n' ;;
    com.android.systemui) printf 'System UI. Disabling makes the device unusable.\n' ;;
    com.android.settings) printf 'Settings app. Disabling removes your recovery surface.\n' ;;
    com.android.tv.settings) printf 'TV Settings. Never disable.\n' ;;
    com.android.providers.settings) printf 'Settings provider. Disabling breaks settings persistence.\n' ;;
    com.android.shell) printf 'Shell is required for ADB.\n' ;;
    com.android.packageinstaller|com.google.android.packageinstaller) printf 'Package Installer is required for future installs.\n' ;;
    com.android.permissioncontroller|com.google.android.permissioncontroller) printf 'Permission Controller is required for runtime permissions.\n' ;;
    com.android.externalstorage) printf 'External Storage provider is required for file access.\n' ;;
    com.android.providers.media) printf 'Media provider is required for media discovery.\n' ;;
    com.android.providers.downloads|com.android.providers.downloads.ui) printf 'Downloads provider is required for app downloads.\n' ;;
    com.android.bluetooth|com.android.bluetoothmidiservice) printf 'Bluetooth is required by many TV remotes.\n' ;;
    com.android.inputdevices) printf 'Input subsystem is required by remotes and keyboards.\n' ;;
    com.android.keychain|com.android.certinstaller) printf 'Certificate/keychain services are required for sign-in and DRM.\n' ;;
    com.google.android.gms|com.google.android.gsf|com.google.android.gsf.login) printf 'Google base services are required by Google TV builds and many apps.\n' ;;
    com.google.android.ext.services) printf 'Android extension services are required by notifications and ranking.\n' ;;
    com.android.location.fused) printf 'Fused Location is required by location-aware apps.\n' ;;
    com.android.providers.calendar|com.android.providers.contacts) printf 'Provider required by sign-in/account sync flows.\n' ;;
    com.google.android.inputmethod.latin|com.google.android.leanbackkeyboard|com.android.inputmethod.latin) printf 'Keyboard/IME. Disabling can remove text input.\n' ;;
    com.android.providers.tv) printf 'Live Channels provider. Disabling breaks Watch Next and Live Channels rows.\n' ;;
    com.google.android.tts) printf 'Text-to-Speech. Disabling breaks accessibility readers.\n' ;;
    com.google.android.katniss) printf 'Google app/Assistant. Disabling kills voice search and remote mic flows.\n' ;;
    com.google.android.speech.pumpkin) printf 'Speech Services. Disabling can break voice dictation and mic search.\n' ;;
    com.google.android.apps.mediashell) printf 'Chromecast Built-in. Disabling removes casting to this device.\n' ;;
    com.android.vending) printf 'Play Store. Disabling removes the normal install path.\n' ;;
    com.google.android.feedback) printf 'Crash feedback. Recoverable, but disables crash reports.\n' ;;
    com.android.printspooler) printf 'Print Spooler. Usually unused on TV but recoverable.\n' ;;
    *) printf 'No special safety rule.\n' ;;
  esac
}

sho_is_never_disable() {
  [[ "$(sho_safety_kind "$1")" == "never" ]]
}

sho_detect_device_type() {
  local brand model device manufacturer
  brand="$(sho_lower "${1:-}")"
  model="$(sho_lower "${2:-}")"
  device="$(sho_lower "${3:-}")"
  manufacturer="$(sho_lower "${4:-}")"

  if [[ "$brand" == "nvidia" || "$manufacturer" == "nvidia" || "$model" == *shield* ]]; then
    printf 'shield\n'
    return 0
  fi

  case "$device" in
    foster|darcy|mdarcy|sif)
      printf 'shield\n'
      return 0
      ;;
  esac

  if [[ "$brand" == "onn" || "$brand" == "google" || "$manufacturer" == "google" || "$manufacturer" == "amlogic" ]]; then
    printf 'googletv\n'
    return 0
  fi

  if [[ "$model" == *onn* || "$model" == *chromecast* || "$model" == *sabrina* || "$model" == *boreal* ]]; then
    printf 'googletv\n'
    return 0
  fi

  if [[ "$device" == ott_* || "$device" == "sabrina" || "$device" == "boreal" ]]; then
    printf 'googletv\n'
    return 0
  fi

  if [[ "$brand" == "amazon" || "$manufacturer" == "amazon" || "$model" == *"fire tv"* || "$device" == aft* ]]; then
    printf 'firetv\n'
    return 0
  fi

  if [[ "$model" == *"android tv"* ]]; then
    printf 'androidtv\n'
    return 0
  fi

  printf 'unknown\n'
}

sho_device_type_label() {
  case "$1" in
    shield) printf 'Nvidia Shield\n' ;;
    googletv) printf 'Google TV\n' ;;
    firetv) printf 'Fire TV\n' ;;
    androidtv) printf 'Android TV\n' ;;
    *) printf 'Unknown\n' ;;
  esac
}

sho_shield_friendly_model() {
  case "$(sho_lower "${1:-}")" in
    mdarcy) printf 'Shield TV Pro (2019)\n' ;;
    sif) printf 'Shield TV (2019 Tube)\n' ;;
    darcy) printf 'Shield TV (2017)\n' ;;
    foster) printf 'Shield TV (2015)\n' ;;
    "") printf 'Shield TV\n' ;;
    *) printf 'Shield TV (%s)\n' "$1" ;;
  esac
}

sho_getprop() {
  local key="$1"
  sho_adb_shell getprop "$key" | sed -n '1p'
}

sho_get_setting() {
  local namespace="$1"
  local key="$2"
  sho_adb_shell settings get "$namespace" "$key" | sed -n '1p'
}

sho_collect_profile_tsv() {
  local friendly brand model device manufacturer release sdk build board dtype display_model
  friendly="$(sho_get_setting global device_name || true)"
  [[ "$friendly" == "null" ]] && friendly=""
  brand="$(sho_getprop ro.product.brand || true)"
  model="$(sho_getprop ro.product.model || true)"
  device="$(sho_getprop ro.product.device || true)"
  manufacturer="$(sho_getprop ro.product.manufacturer || true)"
  release="$(sho_getprop ro.build.version.release || true)"
  sdk="$(sho_getprop ro.build.version.sdk || true)"
  build="$(sho_getprop ro.build.id || true)"
  board="$(sho_getprop ro.board.platform || true)"
  dtype="$(sho_detect_device_type "$brand" "$model" "$device" "$manufacturer")"
  display_model="$model"
  if [[ "$dtype" == "shield" ]]; then
    display_model="$(sho_shield_friendly_model "$device")"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$friendly" "$brand" "$display_model" "$device" "$manufacturer" "$release" "$sdk" "$build" "$board" "$dtype"
}

sho_show_device_profile() {
  sho_require_device
  local profile friendly brand model device manufacturer release sdk build board dtype
  profile="$(sho_collect_profile_tsv)"
  IFS=$'\t' read -r friendly brand model device manufacturer release sdk build board dtype <<<"$profile"
  printf '\nDevice profile for %s\n' "$CURRENT_DEVICE"
  printf '  Name:          %s\n' "${friendly:-"(unset)"}"
  printf '  Type:          %s\n' "$(sho_device_type_label "$dtype")"
  printf '  Brand:         %s\n' "${brand:-unknown}"
  printf '  Model:         %s\n' "${model:-unknown}"
  printf '  Device:        %s\n' "${device:-unknown}"
  printf '  Manufacturer:  %s\n' "${manufacturer:-unknown}"
  printf '  Android:       %s (SDK %s)\n' "${release:-unknown}" "${sdk:-unknown}"
  printf '  Build:         %s\n' "${build:-unknown}"
  printf '  Board:         %s\n' "${board:-unknown}"
}

sho_catalog_path_for_device() {
  case "$1" in
    shield) printf '%s\n' "$SCRIPT_DIR/v2/data/app-lists/shield.json" ;;
    googletv) printf '%s\n' "$SCRIPT_DIR/v2/data/app-lists/googletv.json" ;;
    *) return 1 ;;
  esac
}

sho_load_catalog() {
  local device_type="${1:-unknown}"
  local common="$SCRIPT_DIR/v2/data/app-lists/common.json"
  local specific=""

  if [[ ! -f "$common" ]]; then
    sho_error "Missing app list: $common"
    return 1
  fi

  specific="$(sho_catalog_path_for_device "$device_type" 2>/dev/null || true)"
  if [[ -n "$specific" && ! -f "$specific" ]]; then
    sho_error "Missing app list: $specific"
    return 1
  fi

  if [[ -n "$specific" ]]; then
    jq -s '
      def dedup:
        reduce .[] as $item ([];
          if any(.[]; .package == $item.package) then . else . + [$item] end
        );
      .[0] as $common |
      .[1] as $specific |
      ($specific | map(.package)) as $overrides |
      ([ $common[] | select(.package as $pkg | ($overrides | index($pkg) | not)) ] + $specific) | dedup
    ' "$common" "$specific"
  else
    jq '
      reduce .[] as $item ([];
        if any(.[]; .package == $item.package) then . else . + [$item] end
      )
    ' "$common"
  fi
}

sho_catalog_tsv() {
  local device_type="$1"
  sho_load_catalog "$device_type" | jq -r '
    .[] |
    [
      .package,
      .name,
      .method,
      .risk,
      (.default_optimize | tostring),
      (.default_restore | tostring),
      (.play_store | tostring),
      (.defunct | tostring),
      (.optimize_description // ""),
      (.restore_description // "")
    ] | @tsv
  '
}

sho_effective_method() {
  local method="$1"
  local play_store="$2"
  local defunct="$3"
  if [[ "$method" == "uninstall" && "$play_store" != "true" && "$defunct" != "true" ]]; then
    printf 'disable\n'
  else
    printf '%s\n' "$method"
  fi
}

sho_require_device() {
  if [[ -n "$CURRENT_DEVICE" ]]; then
    return 0
  fi
  sho_choose_device
}

sho_choose_device() {
  local devices=()
  local serial choice idx
  mapfile -t devices < <(sho_device_serials)

  if ((${#devices[@]} == 0)); then
    sho_warn "No authorized ADB devices found."
    sho_info "Use Network Scan, Connect IP, or authorize USB debugging on the device."
    return 1
  fi

  if ((${#devices[@]} == 1)); then
    CURRENT_DEVICE="${devices[0]}"
    sho_info "Selected device: $CURRENT_DEVICE"
    return 0
  fi

  printf '\nConnected devices:\n'
  idx=1
  for serial in "${devices[@]}"; do
    printf '  %d) %s\n' "$idx" "$serial"
    idx=$((idx + 1))
  done

  choice="$(sho_prompt "Select device number: ")"
  if [[ ! "$choice" =~ ^[0-9]+$ || "$choice" -lt 1 || "$choice" -gt "${#devices[@]}" ]]; then
    sho_warn "Invalid selection."
    return 1
  fi
  CURRENT_DEVICE="${devices[$((choice - 1))]}"
  sho_info "Selected device: $CURRENT_DEVICE"
}

sho_adb_connect() {
  local target="$1"
  if [[ "$target" != *:* ]]; then
    target="$target:5555"
  fi
  sho_info "Connecting to $target..."
  sho_adb_raw connect "$target" | sho_trim_cr
}

sho_detect_local_subnet() {
  local src
  if command -v ip >/dev/null 2>&1; then
    src="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}' || true)"
    if [[ "$src" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.[0-9]+$ ]]; then
      printf '%s.%s.%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
      return 0
    fi
  fi
  return 1
}

sho_network_scan() {
  local subnet="$SHO_SUBNET"
  local host ip target output

  if [[ -z "$subnet" ]]; then
    subnet="$(sho_detect_local_subnet || true)"
  fi
  if [[ -z "$subnet" ]]; then
    subnet="$(sho_prompt "Subnet prefix (example 192.168.1): ")"
  fi
  if [[ ! "$subnet" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    sho_warn "Invalid subnet prefix: $subnet"
    return 1
  fi

  sho_info "Scanning $subnet.1-254 for ADB over TCP. This can take a while."
  for ((host = 1; host <= 254; host++)); do
    ip="$subnet.$host"
    if command -v ping >/dev/null 2>&1; then
      ping -c 1 -W 1 "$ip" >/dev/null 2>&1 || continue
    fi
    target="$ip:5555"
    if command -v timeout >/dev/null 2>&1; then
      output="$(timeout 3 "$ADB_BIN" connect "$target" 2>&1 | sho_trim_cr || true)"
    else
      output="$("$ADB_BIN" connect "$target" 2>&1 | sho_trim_cr || true)"
    fi
    if [[ "$output" == *"connected"* || "$output" == *"already connected"* ]]; then
      printf '%s\n' "$output"
    fi
  done
}

sho_package_installed() {
  local package="$1"
  sho_adb shell pm path "$package" >/dev/null 2>&1
}

sho_package_disabled() {
  local package="$1"
  sho_adb_shell pm list packages -d | sed 's/^package://' | grep -Fxq "$package"
}

sho_apply_package_action() {
  local package="$1"
  local method="$2"
  local kind output

  if ! sho_is_valid_package "$package"; then
    sho_warn "Skipping invalid package name: $package"
    return 1
  fi

  kind="$(sho_safety_kind "$package")"
  if [[ "$kind" == "never" ]]; then
    sho_warn "Refusing to modify $package: $(sho_safety_reason "$package")"
    return 1
  fi

  if [[ "$kind" == "caution" ]]; then
    sho_warn "$package: $(sho_safety_reason "$package")"
    sho_confirm "Continue with $package?" n || return 1
  fi

  case "$method" in
    disable)
      output="$(sho_adb_shell pm disable-user --user 0 "$package" || true)"
      ;;
    uninstall)
      output="$(sho_adb_shell pm uninstall --user 0 "$package" || true)"
      ;;
    *)
      sho_warn "Unknown method '$method' for $package"
      return 1
      ;;
  esac

  printf '%s\n' "${output:-ok}"
  sho_shell_ok "$output"
}

sho_restore_package() {
  local package="$1"
  local output

  if ! sho_is_valid_package "$package"; then
    sho_warn "Skipping invalid package name: $package"
    return 1
  fi

  if sho_package_installed "$package"; then
    output="$(sho_adb_shell pm enable "$package" || true)"
  else
    output="$(sho_adb_shell cmd package install-existing "$package" || true)"
  fi

  printf '%s\n' "${output:-ok}"
  sho_shell_ok "$output"
}

sho_get_device_type() {
  local profile
  profile="$(sho_collect_profile_tsv)"
  awk -F '\t' '{print $10}' <<<"$profile"
}

sho_show_catalog() {
  sho_require_device
  local dtype idx package name method risk default_optimize default_restore play_store defunct opt_desc restore_desc effective
  dtype="$(sho_get_device_type)"
  printf '\nCatalog for %s (%s)\n' "$CURRENT_DEVICE" "$(sho_device_type_label "$dtype")"
  printf '%-4s %-42s %-45s %-10s %-8s %-7s\n' "#" "Name" "Package" "Method" "Risk" "Default"
  printf '%s\n' "---- ------------------------------------------ --------------------------------------------- ---------- -------- -------"
  idx=1
  while IFS=$'\t' read -r package name method risk default_optimize default_restore play_store defunct opt_desc restore_desc; do
    effective="$(sho_effective_method "$method" "$play_store" "$defunct")"
    printf '%-4d %-42.42s %-45.45s %-10s %-8s %-7s\n' "$idx" "$name" "$package" "$effective" "$risk" "$default_optimize"
    idx=$((idx + 1))
  done < <(sho_catalog_tsv "$dtype")
}

sho_run_optimize() {
  sho_require_device
  local dtype package name method risk default_optimize default_restore play_store defunct opt_desc restore_desc effective default_prompt answer
  local changed=0 skipped=0 failed=0

  dtype="$(sho_get_device_type)"
  printf '\nOptimize catalog for %s (%s)\n' "$CURRENT_DEVICE" "$(sho_device_type_label "$dtype")"
  sho_warn "Actions are reversible when possible. Never-disable packages are refused."

  while IFS=$'\t' read -r package name method risk default_optimize default_restore play_store defunct opt_desc restore_desc; do
    effective="$(sho_effective_method "$method" "$play_store" "$defunct")"
    if ! sho_package_installed "$package"; then
      skipped=$((skipped + 1))
      continue
    fi
    if sho_package_disabled "$package"; then
      skipped=$((skipped + 1))
      continue
    fi

    printf '\n%s\n' "$name"
    printf '  Package: %s\n' "$package"
    printf '  Method:  %s\n' "$effective"
    printf '  Risk:    %s\n' "$risk"
    [[ -n "$opt_desc" ]] && printf '  Note:    %s\n' "$opt_desc"

    default_prompt="n"
    [[ "$default_optimize" == "true" ]] && default_prompt="y"
    if sho_confirm "Apply optimization?" "$default_prompt"; then
      if sho_apply_package_action "$package" "$effective"; then
        changed=$((changed + 1))
      else
        failed=$((failed + 1))
      fi
    else
      skipped=$((skipped + 1))
    fi
  done < <(sho_catalog_tsv "$dtype")

  printf '\nOptimize complete: changed=%d skipped=%d failed=%d\n' "$changed" "$skipped" "$failed"
}

sho_run_restore() {
  sho_require_device
  local dtype package name method risk default_optimize default_restore play_store defunct opt_desc restore_desc default_prompt
  local changed=0 skipped=0 failed=0

  dtype="$(sho_get_device_type)"
  printf '\nRestore catalog for %s (%s)\n' "$CURRENT_DEVICE" "$(sho_device_type_label "$dtype")"

  while IFS=$'\t' read -r package name method risk default_optimize default_restore play_store defunct opt_desc restore_desc; do
    printf '\n%s\n' "$name"
    printf '  Package: %s\n' "$package"
    [[ -n "$restore_desc" ]] && printf '  Note:    %s\n' "$restore_desc"

    default_prompt="n"
    [[ "$default_restore" == "true" ]] && default_prompt="y"
    if sho_confirm "Restore this package?" "$default_prompt"; then
      if sho_restore_package "$package"; then
        changed=$((changed + 1))
      else
        failed=$((failed + 1))
      fi
    else
      skipped=$((skipped + 1))
    fi
  done < <(sho_catalog_tsv "$dtype")

  printf '\nRestore complete: changed=%d skipped=%d failed=%d\n' "$changed" "$skipped" "$failed"
}

sho_health_report() {
  sho_require_device
  printf '\n=== Shield Optimizer Health Report ===\n'
  printf 'Device: %s\n' "$CURRENT_DEVICE"
  sho_show_device_profile

  printf '\n--- Launcher / HOME handlers ---\n'
  sho_adb_shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME || true

  printf '\n--- Display ---\n'
  sho_adb_shell wm size || true
  sho_adb_shell wm density || true
  sho_adb_shell dumpsys display | sed -n '1,40p' || true

  printf '\n--- Storage ---\n'
  sho_adb_shell df -h /data || true

  printf '\n--- Memory ---\n'
  sho_adb_shell dumpsys meminfo | sed -n '1,35p' || true

  printf '\n--- Thermal ---\n'
  sho_adb_shell dumpsys thermalservice | sed -n '1,80p' || true

  printf '\n--- Audio ---\n'
  sho_adb_shell dumpsys audio | sed -n '1,80p' || true

  printf '\n--- Disabled packages ---\n'
  sho_adb_shell pm list packages -d | sed 's/^package://'
}

sho_report_all_devices() {
  local previous="$CURRENT_DEVICE"
  local devices=()
  local serial
  mapfile -t devices < <(sho_device_serials)
  if ((${#devices[@]} == 0)); then
    sho_warn "No authorized devices found."
    return 1
  fi
  for serial in "${devices[@]}"; do
    CURRENT_DEVICE="$serial"
    sho_health_report
  done
  CURRENT_DEVICE="$previous"
}

sho_launcher_menu() {
  sho_require_device
  local choice component package stock_packages package_installed
  while true; do
    sho_menu_header "Launcher Tools" "HOME handler and stock launcher controls"
    sho_menu_item "1" "Show HOME handlers" "current resolver"
    sho_menu_item "2" "Set default HOME activity" "package/.Activity"
    sho_menu_item "3" "Disable stock launcher" "guarded action" danger
    sho_menu_item "4" "Enable stock launchers" "recovery"
    sho_menu_item "0" "Back" "" dim
    choice="$(sho_prompt "Choice: ")"
    case "$choice" in
      1)
        sho_adb_shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME || true
        ;;
      2)
        component="$(sho_prompt "HOME component (package/.Activity): ")"
        if [[ -z "$component" || "$component" != */* ]]; then
          sho_warn "Expected component format package/.Activity"
        else
          sho_adb_shell cmd package set-home-activity "$component" || true
        fi
        ;;
      3)
        stock_packages="com.google.android.tvlauncher com.google.android.apps.tv.launcherx com.android.tv.launcher com.amazon.tv.launcher"
        sho_warn "Only do this after a custom launcher is installed and set as HOME."
        sho_confirm "Continue to choose stock launcher to disable?" n || continue
        for package in $stock_packages; do
          package_installed="no"
          sho_package_installed "$package" && package_installed="yes"
          printf '  %-45s installed=%s\n' "$package" "$package_installed"
        done
        package="$(sho_prompt "Package to disable: ")"
        if [[ -n "$package" ]]; then
          sho_apply_package_action "$package" disable || true
        fi
        ;;
      4)
        for package in com.google.android.tvlauncher com.google.android.apps.tv.launcherx com.android.tv.launcher com.amazon.tv.launcher; do
          sho_restore_package "$package" || true
        done
        ;;
      0) return 0 ;;
      *) sho_warn "Invalid choice." ;;
    esac
  done
}

sho_install_apk() {
  sho_require_device
  local apk
  apk="$(sho_prompt "Path to APK: ")"
  if [[ ! -f "$apk" ]]; then
    sho_warn "APK not found: $apk"
    return 1
  fi
  sho_adb install -r "$apk"
}

sho_show_tweaks() {
  sho_require_device
  printf '\nCurrent tweak settings:\n'
  printf '  hdmi_control_enabled:                  %s\n' "$(sho_get_setting global hdmi_control_enabled || true)"
  printf '  hdmi_control_auto_wakeup_enabled:      %s\n' "$(sho_get_setting global hdmi_control_auto_wakeup_enabled || true)"
  printf '  hdmi_control_auto_device_off_enabled:  %s\n' "$(sho_get_setting global hdmi_control_auto_device_off_enabled || true)"
  printf '  hdmi_system_audio_control_enabled:     %s\n' "$(sho_get_setting global hdmi_system_audio_control_enabled || true)"
  printf '  match_content_frame_rate:              %s\n' "$(sho_get_setting secure match_content_frame_rate || true)"
  printf '  long_press_timeout:                    %s\n' "$(sho_get_setting secure long_press_timeout || true)"
  printf '  window_animation_scale:                %s\n' "$(sho_get_setting global window_animation_scale || true)"
  printf '  transition_animation_scale:            %s\n' "$(sho_get_setting global transition_animation_scale || true)"
  printf '  animator_duration_scale:               %s\n' "$(sho_get_setting global animator_duration_scale || true)"
  printf '  background_process_limit:              %s\n' "$(sho_get_setting global background_process_limit || true)"
  printf '\nDisplay scaling:\n'
  sho_adb_shell wm size || true
  sho_adb_shell wm density || true
}

sho_set_animation_scale() {
  local value="$1"
  sho_write_setting global window_animation_scale "$value"
  sho_write_setting global transition_animation_scale "$value"
  sho_write_setting global animator_duration_scale "$value"
}

sho_set_cec() {
  local value="$1"
  sho_write_setting global hdmi_control_enabled "$value"
  sho_write_setting global hdmi_control_auto_wakeup_enabled "$value"
  sho_write_setting global hdmi_control_auto_device_off_enabled "$value"
  sho_write_setting global hdmi_system_audio_control_enabled "$value"
}

sho_set_display_scaling() {
  local preset="$1"
  case "$preset" in
    uhd)
      sho_adb_shell "wm size 3839x2160; wm density 640" || true
      ;;
    fhd)
      sho_adb_shell "wm size 1920x1080; wm density 320" || true
      ;;
    reset)
      sho_adb_shell "wm size reset; wm density reset" || true
      ;;
  esac
}

sho_tweaks_menu() {
  sho_require_device
  local choice value
  while true; do
    sho_menu_header "Tweaks" "Display, animation, HDMI-CEC, and Android TV settings"
    sho_menu_item "1" "Show current settings" "read only"
    sho_menu_item "2" "Animations optimized" "0.5x" success
    sho_menu_item "3" "Animations default" "1.0x"
    sho_menu_item "4" "Enable HDMI-CEC controls" "TV/device sync"
    sho_menu_item "5" "Disable HDMI-CEC controls" "TV/device sync" warn
    sho_menu_item "6" "Match frame rate: Never" "secure setting"
    sho_menu_item "7" "Match frame rate: Seamless" "secure setting"
    sho_menu_item "8" "Match frame rate: Always" "secure setting"
    sho_menu_item "9" "Long-press HOME timeout" "milliseconds"
    sho_menu_item "10" "Background process limit" "0-4 or reset"
    sho_menu_item "11" "Display scaling: 4K" "3839x2160 / 640"
    sho_menu_item "12" "Display scaling: 1080p" "1920x1080 / 320"
    sho_menu_item "13" "Display scaling: reset" "device default"
    sho_menu_item "0" "Back" "" dim
    choice="$(sho_prompt "Choice: ")"
    case "$choice" in
      1) sho_show_tweaks ;;
      2) sho_set_animation_scale "0.5" ;;
      3) sho_set_animation_scale "1.0" ;;
      4) sho_set_cec "1" ;;
      5) sho_set_cec "0" ;;
      6) sho_write_setting secure match_content_frame_rate "0" ;;
      7) sho_write_setting secure match_content_frame_rate "1" ;;
      8) sho_write_setting secure match_content_frame_rate "2" ;;
      9)
        value="$(sho_prompt "Long-press timeout in ms (example 500): ")"
        if [[ "$value" =~ ^[0-9]+$ ]]; then
          sho_write_setting secure long_press_timeout "$value"
        else
          sho_warn "Expected number."
        fi
        ;;
      10)
        value="$(sho_prompt "Background process limit (empty resets, 0-4 set limit): ")"
        if [[ -z "$value" || "$value" =~ ^[0-4]$ ]]; then
          sho_write_setting global background_process_limit "$value"
        else
          sho_warn "Expected empty or 0-4."
        fi
        ;;
      11) sho_set_display_scaling uhd ;;
      12) sho_set_display_scaling fhd ;;
      13) sho_set_display_scaling reset ;;
      0) return 0 ;;
      *) sho_warn "Invalid choice." ;;
    esac
  done
}

sho_snapshot_path_allowed() {
  local root="$1"
  local path="$2"
  local root_real path_dir path_base path_real

  [[ -d "$root" ]] || return 1
  root_real="$(cd "$root" && pwd -P)" || return 1
  path_dir="$(dirname "$path")"
  path_base="$(basename "$path")"
  [[ -d "$path_dir" ]] || return 1
  path_real="$(cd "$path_dir" && pwd -P)/$path_base" || return 1

  [[ "$path_real" == "$root_real"/* ]]
}

sho_snapshot_settings_json() {
  local entries=(
    "global hdmi_control_enabled"
    "global hdmi_control_auto_wakeup_enabled"
    "global hdmi_control_auto_device_off_enabled"
    "global hdmi_system_audio_control_enabled"
    "secure match_content_frame_rate"
    "secure long_press_timeout"
    "global window_animation_scale"
    "global transition_animation_scale"
    "global animator_duration_scale"
    "global background_process_limit"
  )
  local entry namespace key value
  {
    for entry in "${entries[@]}"; do
      namespace="${entry%% *}"
      key="${entry#* }"
      value="$(sho_get_setting "$namespace" "$key" || true)"
      [[ "$value" == "null" ]] && value=""
      jq -n --arg namespace "$namespace" --arg key "$key" --arg value "$value" \
        '{namespace: $namespace, key: $key, value: $value}'
    done
  } | jq -s '.'
}

sho_save_snapshot() {
  sho_require_device
  mkdir -p "$SNAPSHOT_DIR"
  local profile friendly brand model device manufacturer release sdk build board dtype disabled_json settings_json name path created
  profile="$(sho_collect_profile_tsv)"
  IFS=$'\t' read -r friendly brand model device manufacturer release sdk build board dtype <<<"$profile"
  disabled_json="$(sho_adb_shell pm list packages -d | sed 's/^package://' | jq -R 'select(length > 0)' | jq -s '.')"
  settings_json="$(sho_snapshot_settings_json)"
  created="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  name="$(printf '%s-%s' "$(date -u '+%Y%m%d-%H%M%S')" "${CURRENT_DEVICE//[:\/]/_}")"
  path="$SNAPSHOT_DIR/$name.json"

  jq -n \
    --arg created_at "$created" \
    --arg serial "$CURRENT_DEVICE" \
    --arg friendly_name "$friendly" \
    --arg brand "$brand" \
    --arg model "$model" \
    --arg device_codename "$device" \
    --arg manufacturer "$manufacturer" \
    --arg android_release "$release" \
    --arg sdk_level "$sdk" \
    --arg build_id "$build" \
    --arg board_platform "$board" \
    --arg device_type "$dtype" \
    --argjson disabled_packages "$disabled_json" \
    --argjson settings "$settings_json" \
    '{
      schema_version: 1,
      created_at: $created_at,
      device: {
        serial: $serial,
        friendly_name: $friendly_name,
        brand: $brand,
        model: $model,
        device_codename: $device_codename,
        manufacturer: $manufacturer,
        android_release: $android_release,
        sdk_level: $sdk_level,
        build_id: $build_id,
        board_platform: $board_platform,
        device_type: $device_type
      },
      disabled_packages: $disabled_packages,
      settings: $settings
    }' > "$path"

  sho_info "Snapshot saved: $path"
}

sho_list_snapshots() {
  mkdir -p "$SNAPSHOT_DIR"
  local file
  printf '\nSnapshots in %s\n' "$SNAPSHOT_DIR"
  for file in "$SNAPSHOT_DIR"/*.json; do
    [[ -e "$file" ]] || { sho_info "  (none)"; return 0; }
    printf '  %s\n' "$file"
  done
}

sho_apply_snapshot() {
  sho_require_device
  mkdir -p "$SNAPSHOT_DIR"
  local path schema package namespace key value
  sho_list_snapshots
  path="$(sho_prompt "Snapshot path to apply: ")"
  if ! sho_snapshot_path_allowed "$SNAPSHOT_DIR" "$path"; then
    sho_warn "Snapshot must be inside $SNAPSHOT_DIR"
    return 1
  fi
  if [[ ! -f "$path" ]]; then
    sho_warn "Snapshot not found: $path"
    return 1
  fi

  schema="$(jq -r '.schema_version // 0' "$path")"
  if [[ "$schema" != "1" ]]; then
    sho_warn "Unsupported snapshot schema_version: $schema"
    return 1
  fi

  sho_warn "Applying a snapshot re-disables packages listed in the snapshot."
  sho_confirm "Continue?" n || return 0

  while IFS= read -r package; do
    [[ -n "$package" ]] || continue
    sho_apply_package_action "$package" disable || true
  done < <(jq -r '.disabled_packages[]?' "$path")

  while IFS=$'\t' read -r namespace key value; do
    [[ -n "$namespace" && -n "$key" ]] || continue
    sho_write_setting "$namespace" "$key" "$value" || true
  done < <(jq -r '.settings[]? | [.namespace, .key, (.value // "")] | @tsv' "$path")
}

sho_snapshot_menu() {
  local choice
  while true; do
    sho_menu_header "Snapshots" "Save or restore disabled packages and tracked settings"
    sho_menu_item "1" "Save snapshot" "writes under home data dir" success
    sho_menu_item "2" "List snapshots" "$SNAPSHOT_DIR"
    sho_menu_item "3" "Apply snapshot" "path-confined restore" warn
    sho_menu_item "0" "Back" "" dim
    choice="$(sho_prompt "Choice: ")"
    case "$choice" in
      1) sho_save_snapshot ;;
      2) sho_list_snapshots ;;
      3) sho_apply_snapshot ;;
      0) return 0 ;;
      *) sho_warn "Invalid choice." ;;
    esac
  done
}

sho_panic_recovery() {
  sho_require_device
  local package output changed=0 failed=0
  sho_warn "Panic recovery enables every currently disabled package."
  sho_confirm "Continue?" n || return 0
  while IFS= read -r package; do
    package="${package#package:}"
    [[ -n "$package" ]] || continue
    output="$(sho_adb_shell pm enable "$package" || true)"
    printf '%-50s %s\n' "$package" "${output:-ok}"
    if sho_shell_ok "$output"; then
      changed=$((changed + 1))
    else
      failed=$((failed + 1))
    fi
  done < <(sho_adb_shell pm list packages -d)
  printf 'Panic recovery complete: enabled=%d failed=%d\n' "$changed" "$failed"
}

sho_reboot_menu() {
  sho_require_device
  local choice
  sho_menu_header "Reboot" "Target: $CURRENT_DEVICE"
  sho_menu_item "1" "Normal reboot" "" warn
  sho_menu_item "2" "Reboot recovery" "" danger
  sho_menu_item "3" "Reboot bootloader" "" danger
  sho_menu_item "0" "Back" "" dim
  choice="$(sho_prompt "Choice: ")"
  case "$choice" in
    1) sho_adb reboot ;;
    2) sho_adb reboot recovery ;;
    3) sho_adb reboot bootloader ;;
    0) return 0 ;;
    *) sho_warn "Invalid choice." ;;
  esac
}

sho_device_menu() {
  local choice
  sho_require_device || return 1
  while true; do
    sho_menu_header "Device Menu" "Current device: $CURRENT_DEVICE"
    sho_menu_item "1" "Device profile" "model, Android, type"
    sho_menu_item "2" "Health report" "display, memory, thermal"
    sho_menu_item "3" "Optimizer catalog" "curated package list"
    sho_menu_item "4" "Optimize apps" "safety-gated" success
    sho_menu_item "5" "Restore apps" "enable / install-existing"
    sho_menu_item "6" "Launcher tools" "HOME handlers"
    sho_menu_item "7" "Install APK" "adb install -r"
    sho_menu_item "8" "Tweaks and scaling" "settings and wm"
    sho_menu_item "9" "Snapshots" "save / apply"
    sho_menu_item "10" "Panic recovery" "enable disabled packages" danger
    sho_menu_item "11" "Reboot" "device power actions" warn
    sho_menu_item "12" "Choose another device" "switch target"
    sho_menu_item "0" "Back" "" dim
    choice="$(sho_prompt "Choice: ")"
    case "$choice" in
      1) sho_show_device_profile; sho_pause ;;
      2) sho_health_report; sho_pause ;;
      3) sho_show_catalog; sho_pause ;;
      4) sho_run_optimize; sho_pause ;;
      5) sho_run_restore; sho_pause ;;
      6) sho_launcher_menu ;;
      7) sho_install_apk; sho_pause ;;
      8) sho_tweaks_menu ;;
      9) sho_snapshot_menu ;;
      10) sho_panic_recovery; sho_pause ;;
      11) sho_reboot_menu; sho_pause ;;
      12) CURRENT_DEVICE=""; sho_choose_device || true ;;
      0) return 0 ;;
      *) sho_warn "Invalid choice." ;;
    esac
  done
}

sho_main_menu() {
  local choice target
  sho_adb_raw start-server >/dev/null
  while true; do
    sho_menu_header "Shield Optimizer Bash" "Linux / Termux ADB toolkit"
    sho_menu_item "1" "List ADB devices" "usb and tcp targets"
    sho_menu_item "2" "Select / manage device" "${CURRENT_DEVICE:-no device selected}"
    sho_menu_item "3" "Network scan" "${SHO_SUBNET:-auto subnet}"
    sho_menu_item "4" "Connect by IP" "ip or ip:port"
    sho_menu_item "5" "Restart ADB server" "kill-server/start-server" warn
    sho_menu_item "6" "Health report all devices" "read only"
    sho_menu_item "0" "Quit" "" dim
    choice="$(sho_prompt "Choice: ")"
    case "$choice" in
      1) sho_list_devices; sho_pause ;;
      2) sho_device_menu ;;
      3) sho_network_scan; sho_pause ;;
      4)
        target="$(sho_prompt "IP or IP:port: ")"
        [[ -n "$target" ]] && sho_adb_connect "$target"
        sho_pause
        ;;
      5) sho_restart_adb; sho_pause ;;
      6) sho_report_all_devices; sho_pause ;;
      0) return 0 ;;
      *) sho_warn "Invalid choice." ;;
    esac
  done
}

sho_main() {
  sho_parse_args "$@"
  case "$SHO_ACTION" in
    help)
      sho_usage
      ;;
    check-deps)
      sho_check_dependencies
      ;;
    list-devices)
      sho_require_dependencies
      sho_list_devices
      ;;
    menu)
      sho_require_dependencies
      sho_main_menu
      ;;
    *)
      sho_error "Unknown action: $SHO_ACTION"
      exit 2
      ;;
  esac
}

if [[ "${SHIELD_OPTIMIZER_TEST_MODE:-0}" != "1" ]]; then
  sho_main "$@"
fi
