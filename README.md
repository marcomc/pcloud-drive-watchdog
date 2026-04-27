# pCloud Drive Watchdog

A small macOS LaunchAgent that watches pCloud Drive and restarts it when the
virtual drive stops behaving like a mounted cloud drive.

This project is not affiliated with, endorsed by, or supported by pCloud AG or
the official pCloud Drive application. It is only a companion workaround for a
failure mode that should ideally disappear once the official macOS client is
stable.

## Table of Contents

- [Problem](#problem)
- [What It Does](#what-it-does)
- [Requirements](#requirements)
- [Install](#install)
- [Uninstall](#uninstall)
- [Configuration](#configuration)
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

If one of those checks fails, the script asks pCloud Drive to quit, waits, stops
leftover pCloud helper processes, and opens pCloud Drive again.

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

The installer detects `pCloud Drive.app`, asks for a check interval, generates a
LaunchAgent for the current user, and starts it immediately.

The default check interval is `60` seconds. To install without an interactive
prompt, pass `INTERVAL_SECONDS`:

```sh
INTERVAL_SECONDS=300 make install
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

The runtime script also supports these environment variables:

- `PCLOUD_APP_PATH`: path to `pCloud Drive.app`;
- `PCLOUD_APP_NAME`: app name, default `pCloud Drive`;
- `PCLOUD_APP_BUNDLE_ID`: app bundle identifier, default
  `com.pcloud.pcloud.macos`;
- `PCLOUD_DRIVE_PATH`: mounted drive path, default `~/pCloud Drive`;
- `PCLOUD_WATCHDOG_LOG_FILE`: log file path.

When these variables are passed to `make install`, the generated LaunchAgent
persists them for scheduled watchdog runs. Most users should only need
`INTERVAL_SECONDS`.

Set `NO_LAUNCH=1` during install when you want to inspect the generated files
before loading the LaunchAgent.

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
