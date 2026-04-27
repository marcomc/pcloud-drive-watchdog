#!/bin/sh

set -eu

LABEL="com.marcomc.pcloud-drive-watchdog"
DEFAULT_INTERVAL_SECONDS="300"
MIN_INTERVAL_SECONDS="30"
DEFAULT_FAILURE_THRESHOLD="2"
MAX_FAILURE_THRESHOLD="999"
DEFAULT_APP_NAME="pCloud Drive"
DEFAULT_APP_BUNDLE_ID="com.pcloud.pcloud.macos"

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)"
SOURCE_SCRIPT="${PROJECT_ROOT}/src/pcloud-drive-watchdog.sh"
PLIST_TEMPLATE="${PROJECT_ROOT}/launchd/${LABEL}.plist.template"
INSTALL_BIN_DIR="${HOME}/.local/bin"
LOG_DIR="${HOME}/Library/Logs"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
INSTALLED_SCRIPT="${INSTALL_BIN_DIR}/pcloud-drive-watchdog.sh"
INSTALLED_PLIST="${LAUNCH_AGENTS_DIR}/${LABEL}.plist"
PCLOUD_APP_NAME="${PCLOUD_APP_NAME:-${DEFAULT_APP_NAME}}"
PCLOUD_APP_BUNDLE_ID="${PCLOUD_APP_BUNDLE_ID:-${DEFAULT_APP_BUNDLE_ID}}"
PCLOUD_DRIVE_PATH="${PCLOUD_DRIVE_PATH:-${HOME}/pCloud Drive}"
PCLOUD_WATCHDOG_LOG_FILE="${PCLOUD_WATCHDOG_LOG_FILE:-${LOG_DIR}/pcloud-drive-watchdog.log}"
PCLOUD_STATE_DIR="${PCLOUD_STATE_DIR:-${HOME}/Library/Application Support/pcloud-drive-watchdog}"
PCLOUD_VERBOSE="${PCLOUD_VERBOSE:-0}"
NO_LAUNCH="${NO_LAUNCH:-0}"
FORCE="${FORCE:-0}"

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '[pcloud-drive-watchdog] %s\n' "$*"
}

detect_pcloud_app() {
  set +e
  detected_path="$(
    PCLOUD_APP_NAME="${PCLOUD_APP_NAME}" \
    PCLOUD_APP_BUNDLE_ID="${PCLOUD_APP_BUNDLE_ID}" \
    PCLOUD_APP_PATH="${PCLOUD_APP_PATH:-}" \
    "${SOURCE_SCRIPT}" --detect-app-path
  )"
  detect_status=$?
  set -e

  if [ "${detect_status}" -ne 0 ] || [ -z "${detected_path}" ]; then
    return 1
  fi

  printf '%s\n' "${detected_path}"
}

prompt_interval() {
  default_interval="${INTERVAL_SECONDS:-$(existing_plist_value StartInterval "${DEFAULT_INTERVAL_SECONDS}")}"

  if [ -t 0 ]; then
    printf 'Check interval in seconds [%s]: ' "${default_interval}" >&2
    IFS= read -r answer
    if [ -z "${answer}" ]; then
      answer="${default_interval}"
    fi
  else
    answer="${default_interval}"
  fi

  case "${answer}" in
    '' | *[!0-9]*)
      die "interval must be a positive integer number of seconds"
      ;;
    *)
      ;;
  esac

  if [ "${answer}" -lt "${MIN_INTERVAL_SECONDS}" ]; then
    die "interval must be at least ${MIN_INTERVAL_SECONDS} seconds"
  fi

  printf '%s\n' "${answer}"
}

prompt_failure_threshold() {
  default_threshold="${PCLOUD_FAILURE_THRESHOLD:-$(existing_plist_value EnvironmentVariables.PCLOUD_FAILURE_THRESHOLD "${DEFAULT_FAILURE_THRESHOLD}")}"

  if [ -t 0 ]; then
    printf 'Consecutive failed checks before restart [%s]: ' "${default_threshold}" >&2
    IFS= read -r answer
    if [ -z "${answer}" ]; then
      answer="${default_threshold}"
    fi
  else
    answer="${default_threshold}"
  fi

  case "${answer}" in
    '' | *[!0-9]*)
      die "consecutive failure threshold must be between 1 and ${MAX_FAILURE_THRESHOLD}"
      ;;
    *)
      ;;
  esac

  if [ "${answer}" -lt 1 ] || [ "${answer}" -gt "${MAX_FAILURE_THRESHOLD}" ]; then
    die "consecutive failure threshold must be between 1 and ${MAX_FAILURE_THRESHOLD}"
  fi

  printf '%s\n' "${answer}"
}

existing_plist_value() {
  key_path="$1"
  fallback="$2"

  if [ -f "${INSTALLED_PLIST}" ]; then
    plutil -extract "${key_path}" raw -o - "${INSTALLED_PLIST}" 2>/dev/null || printf '%s\n' "${fallback}"
  else
    printf '%s\n' "${fallback}"
  fi
}

xml_escape() {
  sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\&apos;/g"
}

sed_escape() {
  sed -e 's/[\/&|]/\\&/g'
}

replace_token() {
  token="$1"
  value="$2"
  file="$3"
  escaped_value="$(printf '%s' "${value}" | xml_escape | sed_escape)"
  sed -i '' "s|${token}|${escaped_value}|g" "${file}"
}

unload_existing_agent() {
  launch_domain="$1"
  service_target="${launch_domain}/${LABEL}"

  if launchctl print "${service_target}" >/dev/null 2>&1; then
    info "Unloading existing LaunchAgent"
    launchctl bootout "${service_target}" >/dev/null 2>&1 || true
    wait_for_unloaded "${service_target}"
  fi
}

wait_for_unloaded() {
  service_target="$1"
  attempts=0

  while launchctl print "${service_target}" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "${attempts}" -eq 1 ] || [ $((attempts % 10)) -eq 0 ]; then
      info "Waiting for existing LaunchAgent to stop"
    fi
    if [ "${attempts}" -ge 150 ]; then
      die "timed out waiting for existing LaunchAgent to unload"
    fi
    sleep 0.2
  done
}

validate_mode() {
  mode="$1"

  case "${mode}" in
    install | configure)
      ;;
    *)
      die "usage: $0 [install|configure]"
      ;;
  esac
}

main() {
  mode="${1:-install}"
  validate_mode "${mode}"

  info "Checking macOS and project files"
  os_name="$(uname -s)"
  [ "${os_name}" = "Darwin" ] || die "this installer only supports macOS"
  [ -f "${SOURCE_SCRIPT}" ] || die "missing source script: ${SOURCE_SCRIPT}"
  [ -f "${PLIST_TEMPLATE}" ] || die "missing plist template: ${PLIST_TEMPLATE}"

  if [ "${mode}" = "install" ] && [ "${FORCE}" != "1" ] && [ -f "${INSTALLED_PLIST}" ] && [ -f "${INSTALLED_SCRIPT}" ]; then
    printf 'Already installed: %s\n' "${LABEL}"
    printf 'Nothing changed.\n'
    printf 'Run "make configure" to update the interval, failure threshold, or pCloud path.\n'
    printf 'Run "FORCE=1 make install" to reinstall files anyway.\n'
    return 0
  fi

  interval_seconds="$(prompt_interval)"
  failure_threshold="$(prompt_failure_threshold)"
  info "Detecting pCloud Drive.app"
  set +e
  pcloud_app_path="$(detect_pcloud_app)"
  detect_status=$?
  set -e
  if [ "${detect_status}" -ne 0 ] || [ -z "${pcloud_app_path}" ]; then
    die "pCloud Drive.app was not found. Install pCloud Drive first or set PCLOUD_APP_PATH."
  fi

  info "Installing watchdog script"
  mkdir -p "${INSTALL_BIN_DIR}" "${LOG_DIR}" "${LAUNCH_AGENTS_DIR}"
  cp "${SOURCE_SCRIPT}" "${INSTALLED_SCRIPT}"
  chmod 755 "${INSTALLED_SCRIPT}"

  info "Generating LaunchAgent plist"
  cp "${PLIST_TEMPLATE}" "${INSTALLED_PLIST}"
  replace_token "__WATCHDOG_SCRIPT__" "${INSTALLED_SCRIPT}" "${INSTALLED_PLIST}"
  replace_token "__START_INTERVAL__" "${interval_seconds}" "${INSTALLED_PLIST}"
  replace_token "__LOG_DIR__" "${LOG_DIR}" "${INSTALLED_PLIST}"
  replace_token "__PCLOUD_APP_PATH__" "${pcloud_app_path}" "${INSTALLED_PLIST}"
  replace_token "__PCLOUD_APP_NAME__" "${PCLOUD_APP_NAME}" "${INSTALLED_PLIST}"
  replace_token "__PCLOUD_APP_BUNDLE_ID__" "${PCLOUD_APP_BUNDLE_ID}" "${INSTALLED_PLIST}"
  replace_token "__PCLOUD_DRIVE_PATH__" "${PCLOUD_DRIVE_PATH}" "${INSTALLED_PLIST}"
  replace_token "__PCLOUD_WATCHDOG_LOG_FILE__" "${PCLOUD_WATCHDOG_LOG_FILE}" "${INSTALLED_PLIST}"
  replace_token "__PCLOUD_FAILURE_THRESHOLD__" "${failure_threshold}" "${INSTALLED_PLIST}"
  replace_token "__PCLOUD_STATE_DIR__" "${PCLOUD_STATE_DIR}" "${INSTALLED_PLIST}"
  replace_token "__PCLOUD_VERBOSE__" "${PCLOUD_VERBOSE}" "${INSTALLED_PLIST}"

  info "Validating generated LaunchAgent"
  plutil -lint "${INSTALLED_PLIST}" >/dev/null

  if [ "${NO_LAUNCH}" = "1" ]; then
    if [ "${mode}" = "configure" ]; then
      printf 'Configured %s without loading launchd service because NO_LAUNCH=1\n' "${LABEL}"
    else
      printf 'Generated %s without loading launchd service because NO_LAUNCH=1\n' "${INSTALLED_PLIST}"
    fi
    printf 'Script: %s\n' "${INSTALLED_SCRIPT}"
    printf 'Interval: %s seconds\n' "${interval_seconds}"
    printf 'Consecutive failed checks: %s\n' "${failure_threshold}"
    printf 'pCloud app: %s\n' "${pcloud_app_path}"
    return 0
  fi

  info "Loading LaunchAgent into launchd"
  launch_domain="gui/$(id -u)"
  unload_existing_agent "${launch_domain}"
  launchctl bootstrap "${launch_domain}" "${INSTALLED_PLIST}"
  launchctl enable "${launch_domain}/${LABEL}"

  if [ "${mode}" = "configure" ]; then
    printf 'Configured %s\n' "${LABEL}"
  else
    printf 'Installed %s\n' "${LABEL}"
  fi
  printf 'Script: %s\n' "${INSTALLED_SCRIPT}"
  printf 'LaunchAgent: %s\n' "${INSTALLED_PLIST}"
  printf 'Interval: %s seconds\n' "${interval_seconds}"
  printf 'Consecutive failed checks: %s\n' "${failure_threshold}"
  printf 'pCloud app: %s\n' "${pcloud_app_path}"
  printf 'Log: %s/pcloud-drive-watchdog.log\n' "${LOG_DIR}"
}

main "$@"
