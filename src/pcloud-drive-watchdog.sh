#!/bin/sh

set -u

APP_NAME="${PCLOUD_APP_NAME:-pCloud Drive}"
APP_BUNDLE_ID="${PCLOUD_APP_BUNDLE_ID:-com.pcloud.pcloud.macos}"
DRIVE_PATH="${PCLOUD_DRIVE_PATH:-${HOME}/pCloud Drive}"
LOG_FILE="${PCLOUD_WATCHDOG_LOG_FILE:-${HOME}/Library/Logs/pcloud-drive-watchdog.log}"
LOCK_DIR="${TMPDIR:-/tmp}/pcloud-drive-watchdog.lock"
PCLOUD_APP_PATH="${PCLOUD_APP_PATH:-}"
readonly APP_NAME APP_BUNDLE_ID DRIVE_PATH LOG_FILE LOCK_DIR PCLOUD_APP_PATH

log() {
  timestamp="$(date '+%Y-%m-%d %H:%M:%S %z')"
  printf '%s %s\n' "${timestamp}" "$*" >> "${LOG_FILE}"
}

cleanup() {
  rm -f "${LOCK_DIR}/pid" 2>/dev/null || true
  rmdir "${LOCK_DIR}" 2>/dev/null || true
}

lock_is_active() {
  if [ ! -f "${LOCK_DIR}/pid" ]; then
    return 1
  fi

  lock_pid="$(cat "${LOCK_DIR}/pid" 2>/dev/null || true)"
  case "${lock_pid}" in
    '' | *[!0-9]*)
      return 1
      ;;
    *)
      ;;
  esac

  kill -0 "${lock_pid}" 2>/dev/null
}

acquire_lock() {
  if mkdir "${LOCK_DIR}" 2>/dev/null; then
    printf '%s\n' "$$" > "${LOCK_DIR}/pid"
    return 0
  fi

  sleep 2
  if lock_is_active; then
    return 1
  fi

  rm -f "${LOCK_DIR}/pid" 2>/dev/null || true
  if rmdir "${LOCK_DIR}" 2>/dev/null; then
    log "Removed stale watchdog lock"
  fi

  if mkdir "${LOCK_DIR}" 2>/dev/null; then
    printf '%s\n' "$$" > "${LOCK_DIR}/pid"
    return 0
  fi

  return 1
}

detect_app_path() {
  if [ -n "${PCLOUD_APP_PATH}" ]; then
    if [ -d "${PCLOUD_APP_PATH}" ]; then
      printf '%s\n' "${PCLOUD_APP_PATH}"
      return 0
    fi

    return 1
  fi

  for candidate in \
    "/Applications/${APP_NAME}.app" \
    "${HOME}/Applications/${APP_NAME}.app"; do
    if [ -d "${candidate}" ]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  if command -v mdfind >/dev/null 2>&1; then
    mdfind "kMDItemCFBundleIdentifier == \"${APP_BUNDLE_ID}\"" | while IFS= read -r candidate; do
      if [ -d "${candidate}/Contents" ]; then
        printf '%s\n' "${candidate}"
        return 0
      fi
    done
  fi

  return 1
}

app_executable() {
  app_path="$(detect_app_path)"
  if [ -z "${app_path}" ]; then
    return 1
  fi

  printf '%s\n' "${app_path}/Contents/MacOS/${APP_NAME}"
}

has_process() {
  executable="$(app_executable)" || return 1
  pgrep -f "${executable}" >/dev/null
}

process_age_seconds() {
  executable="$(app_executable)" || {
    printf '%s\n' 0
    return 0
  }
  pid="$(pgrep -f "${executable}" | head -n 1)"
  if [ -z "${pid}" ]; then
    printf '%s\n' 0
    return 0
  fi

  etime="$(ps -o etime= -p "${pid}" 2>/dev/null | tr -d ' ')"
  awk -v etime="${etime}" '
    BEGIN {
      days = 0
      day_parts = split(etime, day_split, "-")
      if (day_parts == 2) {
        days = day_split[1]
        time_value = day_split[2]
      } else {
        time_value = etime
      }

      time_parts = split(time_value, time_split, ":")
      if (time_parts == 3) {
        seconds = (time_split[1] * 3600) + (time_split[2] * 60) + time_split[3]
      } else if (time_parts == 2) {
        seconds = (time_split[1] * 60) + time_split[2]
      } else {
        seconds = 999999
      }

      print (days * 86400) + seconds
    }
  '
}

has_mount() {
  mount | grep -F " on ${DRIVE_PATH} (pcloudfs," >/dev/null
}

drive_has_content() {
  find "${DRIVE_PATH}" -mindepth 1 -maxdepth 1 ! -name '.DS_Store' -print -quit 2>/dev/null | grep -q .
}

network_reachable() {
  scutil -r www.pcloud.com 2>/dev/null | grep -q 'Reachable'
}

restart_pcloud() {
  reason="$1"
  app_path="$(detect_app_path)"

  if [ -z "${app_path}" ]; then
    log "Cannot restart ${APP_NAME}: app bundle was not found"
    return 1
  fi

  log "Restarting ${APP_NAME}: ${reason}"
  osascript -e "tell application id \"${APP_BUNDLE_ID}\" to quit" >/dev/null 2>&1 || true
  sleep 8
  executable="$(app_executable)" || executable=""
  if [ -n "${executable}" ]; then
    pkill -f "${executable}" >/dev/null 2>&1 || true
  fi
  pkill -f "com.pcloud.pcloudfs.Mounter.Helper" >/dev/null 2>&1 || true
  sleep 2
  open -b "${APP_BUNDLE_ID}" >/dev/null 2>&1 || open "${app_path}" >/dev/null 2>&1
}

main() {
  if ! acquire_lock; then
    log "Skipped: another watchdog run is active"
    return 0
  fi
  trap cleanup EXIT INT TERM

  if ! has_process; then
    restart_pcloud "app process is not running"
    return 0
  fi

  if ! has_mount; then
    restart_pcloud "pCloudFS mount is missing"
    return 0
  fi

  if ! drive_has_content; then
    age_seconds="$(process_age_seconds)"
    if [ "${age_seconds:-0}" -lt 90 ]; then
      log "Warm-up: mounted drive has no visible cloud content yet; process age is ${age_seconds:-0}s"
      return 0
    fi

    sleep 20
    if drive_has_content; then
      log "Healthy after retry: drive content appeared"
      return 0
    fi

    if network_reachable; then
      restart_pcloud "drive is mounted but has no visible cloud content"
    else
      log "Skipped restart: drive content is unavailable and pCloud is not reachable"
    fi
    return 0
  fi

  log "Healthy: process, mount, and drive content are present"
}

case "${1:-}" in
  --detect-app-path)
    detect_app_path
    ;;
  --help | -h)
    printf 'Usage: %s [--detect-app-path]\n' "$0"
    ;;
  '')
    main
    ;;
  *)
    printf 'Unknown option: %s\n' "$1" >&2
    exit 2
    ;;
esac
