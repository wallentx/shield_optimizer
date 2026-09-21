# Shield Optimizer Bash Port Design

## Goal

Add `Shield-Optimizer.sh`, a Linux and Termux compatible Bash implementation of the v1 PowerShell workflow. It covers the practical core of v1 rather than cloning every terminal UI detail line-for-line.

The script must not install dependencies. Startup detects required and optional tools, prints a clear missing-dependency report, and either exits or disables only the affected feature.

## Scope

The first Bash version will include:

- A text menu for device discovery and per-device actions.
- ADB status checks, device listing, connect by IP, disconnect, and ADB restart.
- Best-effort network scan on Linux and Termux when host tools are available.
- Device profile and canonical device-type detection for Nvidia Shield, Google TV, Onn, Chromecast, Google TV Streamer, and unknown Android TV devices.
- Optimize and Restore using the existing v2 JSON app catalogs in `v2/data/app-lists`.
- A mandatory do-not-disable safety gate modeled after v2 `engine/safety.rs`.
- Health report: display, RAM, storage, temperature, audio, and top memory consumers where device output supports it.
- Launcher setup using the known launcher catalog and stock launcher disable flow.
- APK install from a local path.
- Tweaks for HDMI-CEC settings, match-content frame rate, long-press timeout, animation scale, and display scaling.
- Snapshot save, preview, and apply using JSON files in a local snapshot directory.
- Panic recovery that re-enables every disabled package.
- Reboot modes: normal, recovery, bootloader.

Out of scope for the first Bash version:

- Pixel-perfect recreation of the PowerShell menu renderer.
- v2 desktop-only features such as GUI screenshots, typed Svelte components, and Tauri update checks.
- Automatic dependency installation.
- Mac support. The target is Linux distributions and Termux.

## Architecture

`Shield-Optimizer.sh` will be a single Bash file at the repository root, matching the placement of `Shield-Optimizer.ps1`.

The script will be organized into sections:

- **Configuration and dependency checks**: parse flags, detect Termux vs general Linux, locate `adb`, check tools, and report missing dependencies.
- **Shared ADB helpers**: `adb_raw`, `adb_shell`, package list parsing, package validation, shell quoting, and common result handling.
- **Catalog loading**: read `v2/data/app-lists/{common,shield,googletv}.json` with `jq`; merge common plus device-specific entries at runtime.
- **Safety policy**: hard-coded Bash arrays for never-disable and caution packages, copied from v2 safety logic.
- **Device discovery/profile**: parse `adb devices`, query properties, classify device type, and format display names.
- **Feature modules**: optimize/restore, health, launcher, APK install, tweaks, snapshots, recovery, reboot.
- **Menu loop**: simple numbered menus using `read -r`, not raw keyboard navigation.

The script keeps pure helpers small enough to test individually through sourced test mode.

## Dependencies

Required for core execution:

- `bash`
- `adb`
- `jq`

Optional, feature-specific dependencies:

- `ping`, `ip`, `route`, or `arp` for network scan.
- No downloader is included in the first Bash version. If `adb` is missing, startup reports it and exits without attempting to fetch platform-tools.
- `mktemp`, `date`, `sed`, `awk`, `sort`, and `grep`, which are expected on Linux and Termux; if any are unavailable, startup reports them.

The script will never run `apt`, `pkg`, `dnf`, `pacman`, `apk`, `zypper`, or `sudo`.

## Data Flow

On startup:

1. Parse flags such as `--subnet`, `--light`, `--dark`, and `--help`.
2. Detect dependencies and print missing tools.
3. Locate `adb` from `SHIELD_OPTIMIZER_ADB`, `./adb`, `./platform-tools/adb`, or `PATH`.
4. Enter the main menu if required tools are present.

For Optimize:

1. Query installed packages with `pm list packages`.
2. Query disabled packages with `pm list packages -d`.
3. Query memory once with `dumpsys meminfo`.
4. Load and merge the appropriate JSON catalog with `jq`.
5. For each actionable row, default to the catalog recommendation but prompt the user.
6. Refuse never-disable packages before any disable or uninstall command.
7. Send `pm disable-user --user 0`, `pm uninstall --user 0`, or `pm enable` as selected.
8. Offer performance settings and reboot.

For Snapshots:

1. Save disabled packages, current launcher, tracked settings, device type, Android version, and timestamp to JSON.
2. Reject snapshot reads outside the configured snapshot directory.
3. Preview apply by comparing snapshot packages/settings with current target state.
4. Apply snapshots additively: disable packages and write tracked settings, but never re-enable packages absent from the snapshot.

## Error Handling

- Every ADB call returns a success flag and combined output.
- `adb shell` exit code alone is not trusted; output is scanned for `Failure`, `Error`, and `Exception`.
- Invalid package names are rejected before interpolation into shell commands.
- User-provided setting keys and snapshot paths are validated before use.
- Network scan failures are non-fatal and suggest Connect IP.
- Missing optional dependencies produce feature-specific messages rather than crashing the script.

## Testing

Tests are Bash-based and live under `tests/` next to the Pester tests. The first implementation uses a plain Bash test runner so the test suite does not add a new dependency.

Initial test coverage focuses on pure functions:

- dependency checker reports missing tools without installing anything
- package-name validation rejects shell metacharacters
- safety policy blocks never-disable packages
- app catalog merge chooses common plus device-specific entries
- device-type detection matches Shield and Google TV examples
- snapshot path confinement rejects traversal
- uninstall/install output decoders produce useful hints

Implementation follows test-first for these pure helpers before wiring them into the menu.

## Acceptance Criteria

- `Shield-Optimizer.sh --help` runs on Linux and Termux.
- With missing tools, the script prints the missing dependency list and does not install anything.
- With `adb` and `jq` available, the script can list connected devices.
- Optimize/Restore actions load existing JSON app lists and enforce the never-disable gate.
- ShellCheck-relevant quoting patterns are followed for user inputs and package names.
- The script is executable.
- Existing v1 and v2 files are not modified except for tests or docs needed to support the Bash port.
