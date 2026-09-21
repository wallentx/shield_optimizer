# Shield Optimizer Bash Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a root-level `Shield-Optimizer.sh` Bash entrypoint that brings the v1 PowerShell workflow to Linux distributions and Termux without installing dependencies automatically.

**Architecture:** Keep the Bash port self-contained at the repo root. Reuse v2 JSON app lists as the package catalog, mirror v2 safety rules in Bash, and expose the same practical workflows as v1 through an interactive ADB menu. Add a small Bash test runner that sources the script in test mode and verifies pure helper behavior.

**Tech Stack:** Bash 4+, Android Debug Bridge, jq, standard POSIX userland tools where possible.

---

## Scope

- [x] Create `Shield-Optimizer.sh` at the repository root.
- [x] Add `tests/Shield-Optimizer.sh.Tests.sh` for focused Bash helper tests.
- [x] Do not modify v2 source, v2 workflows, or release scripts.
- [x] Do not install or download dependencies.

## Task 1: Dependency And Entry-Point Foundation

- [x] Add strict Bash mode and guard the interactive main function behind `SHIELD_OPTIMIZER_TEST_MODE`.
- [x] Implement command-line flags: `--help`, `--check-deps`, `--list-devices`, `--subnet`.
- [x] Report missing required tools instead of installing them.
- [x] Resolve ADB from `SHIELD_OPTIMIZER_ADB`, repo-local platform-tools, or `PATH`.
- [x] Keep dependency checks usable on both Termux and general Linux.

## Task 2: Pure Helpers And Tests

- [x] Write tests first for package-name validation, safety classification, device profile detection, and snapshot path confinement.
- [x] Implement the pure helper functions needed by the tests.
- [x] Run `bash tests/Shield-Optimizer.sh.Tests.sh` and keep it passing before moving on.

## Task 3: Device Discovery And Profiling

- [x] Implement ADB server restart, device listing, IP connect, and network scan.
- [x] Implement current-device selection.
- [x] Gather Android properties for model, brand, manufacturer, SDK, serial, and device profile.
- [x] Detect Shield, Google TV, Fire TV, Android TV, and unknown profiles.

## Task 4: App Catalog, Optimization, And Restore

- [x] Load `v2/data/app-lists/common.json` plus the detected device-specific list with `jq`.
- [x] Show app labels, package names, risk, effective method, and default optimize flag.
- [x] Apply optimization using disable or uninstall actions only after package validation and safety classification.
- [x] Restore disabled or uninstalled catalog packages with `pm enable` or `cmd package install-existing`.
- [x] Never disable or uninstall packages classified as never-disable.

## Task 5: Main User Workflows

- [x] Add health report output for display, storage, memory, thermal, audio, launcher, and disabled packages.
- [x] Add launcher tools for viewing HOME handlers, setting default launchers where supported, and guarded stock-launcher disabling.
- [x] Add APK installation using a user-provided local path.
- [x] Add Android TV tweak presets for animations, frame rate, CEC, accessibility shortcut, long-press home, and display scaling.
- [x] Add snapshot save, list, and apply under the user's home directory with path confinement.
- [x] Add panic recovery to re-enable disabled packages and reboot actions.

## Task 6: Verification

- [x] Run `bash -n Shield-Optimizer.sh`.
- [x] Run `bash tests/Shield-Optimizer.sh.Tests.sh`.
- [x] Run `./Shield-Optimizer.sh --check-deps` if executable bits are available.
- [x] Run `./Shield-Optimizer.sh --help`.
- [x] Report any checks skipped because local dependencies are unavailable.
