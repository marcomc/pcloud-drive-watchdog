#!/bin/sh

set -u

APP_NAME="${PCLOUD_APP_NAME:-pCloud Drive}"
APP_BUNDLE_ID="${PCLOUD_APP_BUNDLE_ID:-com.pcloud.pcloud.macos}"
DRIVE_PATH="${PCLOUD_DRIVE_PATH:-${HOME}/pCloud Drive}"
LOG_FILE="${PCLOUD_WATCHDOG_LOG_FILE:-${HOME}/Library/Logs/pcloud-drive-watchdog.log}"
STATE_DIR="${PCLOUD_STATE_DIR:-${HOME}/Library/Application Support/pcloud-drive-watchdog}"
FAILURE_THRESHOLD="${PCLOUD_FAILURE_THRESHOLD:-2}"
VERBOSE="${PCLOUD_VERBOSE:-0}"
LOCK_DIR="${TMPDIR:-/tmp}/pcloud-drive-watchdog.lock"
PCLOUD_APP_PATH="${PCLOUD_APP_PATH:-}"
FAILURE_COUNT_FILE="${STATE_DIR}/failure-count"
readonly APP_NAME APP_BUNDLE_ID DRIVE_PATH LOG_FILE STATE_DIR FAILURE_THRESHOLD VERBOSE LOCK_DIR PCLOUD_APP_PATH FAILURE_COUNT_FILE

log() {
  mkdir -p "$(dirname -- "${LOG_FILE}")"
  timestamp="$(date '+%Y-%m-%d %H:%M:%S %z')"
  printf '%s %s\n' "${timestamp}" "$*" >> "${LOG_FILE}"
}

validate_failure_threshold() {
  case "${FAILURE_THRESHOLD}" in
    '' | *[!0-9]*)
      log "Invalid PCLOUD_FAILURE_THRESHOLD='${FAILURE_THRESHOLD}'; expected 1-999"
      return 1
      ;;
    *)
      ;;
  esac

  if [ "${FAILURE_THRESHOLD}" -lt 1 ] || [ "${FAILURE_THRESHOLD}" -gt 999 ]; then
    log "Invalid PCLOUD_FAILURE_THRESHOLD='${FAILURE_THRESHOLD}'; expected 1-999"
    return 1
  fi
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

failure_count() {
  if [ ! -f "${FAILURE_COUNT_FILE}" ]; then
    printf '%s\n' 0
    return 0
  fi

  count="$(cat "${FAILURE_COUNT_FILE}" 2>/dev/null || printf '%s\n' 0)"
  case "${count}" in
    '' | *[!0-9]*)
      printf '%s\n' 0
      ;;
    *)
      printf '%s\n' "${count}"
      ;;
  esac
}

reset_failure_count() {
  previous_count="$(failure_count)"
  rm -f "${FAILURE_COUNT_FILE}" 2>/dev/null || true

  if [ "${previous_count}" -gt 0 ]; then
    log "Healthy: cleared ${previous_count} consecutive failed check(s)"
  elif [ "${VERBOSE}" = "1" ]; then
    log "Healthy: process, mount, and drive content are present"
  fi
}

record_failure() {
  reason="$1"
  previous_count="$(failure_count)"
  next_count=$((previous_count + 1))

  mkdir -p "${STATE_DIR}"
  printf '%s\n' "${next_count}" > "${FAILURE_COUNT_FILE}"

  if [ "${next_count}" -lt "${FAILURE_THRESHOLD}" ]; then
    log "Failure ${next_count}/${FAILURE_THRESHOLD}: ${reason}; waiting for another failed check before restart"
    return 1
  fi

  log "Failure ${next_count}/${FAILURE_THRESHOLD}: ${reason}; restart threshold reached"
  return 0
}

restart_after_failure() {
  reason="$1"

  if record_failure "${reason}"; then
    restart_pcloud "${reason}"
    rm -f "${FAILURE_COUNT_FILE}" 2>/dev/null || true
  fi
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
  if ! validate_failure_threshold; then
    return 1
  fi

  if ! acquire_lock; then
    log "Skipped: another watchdog run is active"
    return 0
  fi
  trap cleanup EXIT INT TERM

  if ! has_process; then
    restart_after_failure "app process is not running"
    return 0
  fi

  if ! has_mount; then
    restart_after_failure "pCloudFS mount is missing"
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
      restart_after_failure "drive is mounted but has no visible cloud content"
    else
      log "Skipped restart: drive content is unavailable and pCloud is not reachable"
    fi
    return 0
  fi

  reset_failure_count
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
