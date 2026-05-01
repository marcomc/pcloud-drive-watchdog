# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows a simple date-based release workflow until tagged
releases are introduced.

## [Unreleased]

## [0.1.0] - 2026-05-01

### Added

- Initial public release of `pcloud-drive-watchdog`.
- LaunchAgent-based pCloud Drive watchdog for macOS.
- Interactive installer, configure flow, uninstall flow, and public README.
- Configurable check interval and consecutive failure threshold.
- `tests/runtime_restart_tests.sh` to verify that the watchdog force-kills a
  fake pCloud process that ignores `SIGTERM`.
- LaunchAgent and installer support for:
  `PCLOUD_QUIT_EVENT_TIMEOUT_SECONDS`,
  `PCLOUD_QUIT_WAIT_SECONDS`, and
  `PCLOUD_FORCE_KILL_WAIT_SECONDS`.

### Changed

- Default watchdog policy set to a 5-minute interval and restart after 2
  consecutive failed checks.
- `make test` and `make lint` now include the runtime restart regression test.
- The README now documents the restart-escalation timing controls.

### Fixed

- The watchdog no longer blocks indefinitely when pCloud hangs inside its quit
  handler.
- Restart recovery now escalates from AppleEvent quit to `SIGTERM` and then
  `SIGKILL` for pCloud processes that ignore graceful termination.
- The live watchdog installation can now replace a wedged `pCloud Drive`
  process and restore the `pcloudfs` mount.
