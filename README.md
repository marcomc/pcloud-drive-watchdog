# pCloud Drive Watchdog

A small macOS LaunchAgent that watches pCloud Drive and restarts it when the
virtual drive stops behaving like a mounted cloud drive.

This project is not affiliated with, endorsed by, or supported by pCloud AG or
the official pCloud Drive application. It is only a companion workaround for a
failure mode that should ideally disappear once the official macOS client is
stable.

Current version: `0.1.0`.

## Table of Contents

- [Problem](#problem)
- [What It Does](#what-it-does)
- [Requirements](#requirements)
- [Install](#install)
- [Reconfigure](#reconfigure)
- [Uninstall](#uninstall)
- [Configuration](#configuration)
- [Script Interface](#script-interface)
- [Logs](#logs)
- [Troubleshooting](#troubleshooting)
- [References](#references)
- [License](#license)

## Problem

Some macOS users have seen pCloud Drive appear in Finder while the virtual drive
is empty or not actually mounted. In that state, the folder at
`~/pCloud Drive` may still exist, but the `pcloudfs` mount is missing or the
official app process has exited. Manually quitting and reopening pCloud Drive
usually restores the files immediately.

This watchdog was created after debugging that exact pattern on macOS 26.4.1
with pCloud Drive 4.0.10:

- Finder showed `pCloud Drive`.
- The local `~/pCloud Drive` folder existed.
- No active `pcloudfs` mount was present.
- Restarting the official pCloud Drive app restored the mount and file listing.

## What It Does

The watchdog runs periodically through `launchd` and checks three conditions:

- the pCloud Drive app process is running;
- `~/pCloud Drive` is mounted as `pcloudfs`;
- the mounted drive contains visible cloud content.

If one of those checks fails repeatedly, the script asks pCloud Drive to quit,
waits, stops leftover pCloud helper processes, and opens pCloud Drive again.
The default policy checks every 5 minutes and restarts after 2 consecutive
failed checks. That avoids reacting to short mount warm-up periods or transient
network hiccups.

The script includes a short warm-up guard so it does not restart pCloud while
the app is still mounting the drive after a fresh launch.

## Requirements

- macOS.
- The official pCloud Drive app installed.
- Apple command-line tools normally present on macOS: `launchctl`, `plutil`,
  `open`, `osascript`, `pgrep`, `pkill`, and `scutil`.
- `make` for the simple install and uninstall commands.

## Install

Clone the project, then run:

```sh
make install
```

The installer detects `pCloud Drive.app`, asks for a check interval and a
consecutive failure threshold, generates a LaunchAgent for the current user, and
starts it immediately.

The default check interval is `300` seconds. The default restart threshold is
`2` consecutive failed checks. To install without an interactive prompt, pass
the values explicitly:

```sh
INTERVAL_SECONDS=300 PCLOUD_FAILURE_THRESHOLD=2 make install
```

If the watchdog is already installed, `make install` does not overwrite the
current LaunchAgent. Use `make configure` to change settings or use
`FORCE=1 make install` to reinstall the files anyway.

## Reconfigure

To update an existing installation:

```sh
make configure
```

`make config` is also available as a shorter alias. The command asks for the new
check interval and the number of consecutive failed checks required before a
restart, then reloads the LaunchAgent.

For unattended reconfiguration:

```sh
INTERVAL_SECONDS=600 PCLOUD_FAILURE_THRESHOLD=3 make configure
```

If pCloud Drive is installed in an unusual location, pass `PCLOUD_APP_PATH`:

```sh
PCLOUD_APP_PATH="/Applications/pCloud Drive.app" make install
```

To generate the installed script and LaunchAgent without loading or restarting
the launchd service, pass `NO_LAUNCH=1`:

```sh
NO_LAUNCH=1 make install
```

## Uninstall

```sh
make uninstall
```

This unloads the LaunchAgent and removes the installed watchdog script. It keeps
logs by default.

To remove logs too:

```sh
REMOVE_LOGS=1 make uninstall
```

## Configuration

The installer writes:

- `~/.local/bin/pcloud-drive-watchdog.sh`
- `~/Library/LaunchAgents/com.marcomc.pcloud-drive-watchdog.plist`

The LaunchAgent stores the chosen check interval in `StartInterval`.
It stores the restart threshold in `PCLOUD_FAILURE_THRESHOLD`.

The runtime script also supports these environment variables:

- `PCLOUD_APP_PATH`: path to `pCloud Drive.app`;
- `PCLOUD_APP_NAME`: app name, default `pCloud Drive`;
- `PCLOUD_APP_BUNDLE_ID`: app bundle identifier, default
  `com.pcloud.pcloud.macos`;
- `PCLOUD_DRIVE_PATH`: mounted drive path, default `~/pCloud Drive`;
- `PCLOUD_WATCHDOG_LOG_FILE`: log file path.
- `PCLOUD_FAILURE_THRESHOLD`: consecutive failed checks before restart, default
  `2`, allowed range `1` through `999`;
- `PCLOUD_STATE_DIR`: small state directory used to count consecutive failed
  checks, default `~/Library/Application Support/pcloud-drive-watchdog`;
- `PCLOUD_VERBOSE`: set to `1` to log every healthy check.
- `PCLOUD_QUIT_EVENT_TIMEOUT_SECONDS`: seconds to wait for the AppleEvent quit
  request before continuing with process termination, default `5`;
- `PCLOUD_QUIT_WAIT_SECONDS`: seconds to wait after requesting quit before
  checking for remaining pCloud processes, default `8`;
- `PCLOUD_FORCE_KILL_WAIT_SECONDS`: seconds to wait after `SIGTERM` before
  escalating to `SIGKILL`, default `2`.

When these variables are passed to `make install` or `make configure`, the
generated LaunchAgent persists them for scheduled watchdog runs. Most users
should only need `INTERVAL_SECONDS` and `PCLOUD_FAILURE_THRESHOLD`.

Set `NO_LAUNCH=1` during install when you want to inspect the generated files
before loading the LaunchAgent.

## Script Interface

The installed watchdog script is:

```text
~/.local/bin/pcloud-drive-watchdog.sh
```

Supported command-line options:

- no arguments: run one watchdog check cycle;
- `--help` or `-h`: print the supported options;
- `--version`: print the watchdog version;
- `--detect-app-path`: print the detected `pCloud Drive.app` path and exit.

Examples:

```sh
~/.local/bin/pcloud-drive-watchdog.sh
~/.local/bin/pcloud-drive-watchdog.sh --help
~/.local/bin/pcloud-drive-watchdog.sh --version
PCLOUD_APP_PATH="/Applications/pCloud Drive.app" \
  ~/.local/bin/pcloud-drive-watchdog.sh --detect-app-path
```

Supported runtime environment variables:

- `PCLOUD_APP_PATH`: override the detected `pCloud Drive.app` path;
- `PCLOUD_APP_NAME`: override the app display name used in path detection;
- `PCLOUD_APP_BUNDLE_ID`: override the app bundle identifier used for
  AppleEvent quit and `open -b`;
- `PCLOUD_DRIVE_PATH`: override the expected mount point path;
- `PCLOUD_WATCHDOG_LOG_FILE`: override the main watchdog log file path;
- `PCLOUD_FAILURE_THRESHOLD`: set the number of consecutive failed checks
  required before restart, valid range `1` through `999`;
- `PCLOUD_STATE_DIR`: override the state directory used for the failure counter;
- `PCLOUD_VERBOSE`: set to `1` to log healthy checks too;
- `PCLOUD_QUIT_EVENT_TIMEOUT_SECONDS`: limit how long the script waits for the
  AppleEvent quit request before continuing with process termination;
- `PCLOUD_QUIT_WAIT_SECONDS`: wait after requesting quit before checking for
  remaining pCloud processes;
- `PCLOUD_FORCE_KILL_WAIT_SECONDS`: wait after `SIGTERM` before escalating to
  `SIGKILL`.

## Logs

The watchdog writes its own status log here:

```text
~/Library/Logs/pcloud-drive-watchdog.log
```

The LaunchAgent stdout and stderr files are:

```text
~/Library/Logs/pcloud-drive-watchdog.stdout.log
~/Library/Logs/pcloud-drive-watchdog.stderr.log
```

Useful status commands:

```sh
launchctl print "gui/$(id -u)/com.marcomc.pcloud-drive-watchdog"
tail -f ~/Library/Logs/pcloud-drive-watchdog.log
```

## Troubleshooting

Check whether pCloud Drive is mounted:

```sh
mount | grep pcloudfs
```

Check whether the official app is running:

```sh
pgrep -afil "pCloud Drive"
```

Run the watchdog manually:

```sh
~/.local/bin/pcloud-drive-watchdog.sh
```

If the app is installed somewhere unusual, reinstall with `PCLOUD_APP_PATH`.

## References

- [pCloud Drive for macOS release notes](https://www.pcloud.com/release-notes/mac-os.html)
- [Reddit: pCloud Drive 4.0.10 broken on macOS 26.4.1](https://www.reddit.com/r/pcloud/comments/1spld1e/pcloud_drive_4010_broken_on_macos_2641_kext_fails/)
- [Reddit: downgrade to macOS pCloud version 4.0.6 solved our problems](https://www.reddit.com/r/pcloud/comments/1s9irxt/downgrade_to_macos_pcloud_version_406_solved_our/)

## License

MIT. See [LICENSE.md](LICENSE.md).
