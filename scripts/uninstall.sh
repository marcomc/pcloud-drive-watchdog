#!/bin/sh

set -eu

LABEL="com.marcomc.pcloud-drive-watchdog"
INSTALLED_SCRIPT="${HOME}/.local/bin/pcloud-drive-watchdog.sh"
INSTALLED_PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="${HOME}/Library/Logs"

main() {
  launch_domain="gui/$(id -u)"
  service_target="${launch_domain}/${LABEL}"
  if launchctl print "${service_target}" >/dev/null 2>&1; then
    launchctl bootout "${service_target}" >/dev/null 2>&1 || true
  fi

  rm -f "${INSTALLED_PLIST}" "${INSTALLED_SCRIPT}"

  if [ "${REMOVE_LOGS:-0}" = "1" ]; then
    rm -f \
      "${LOG_DIR}/pcloud-drive-watchdog.log" \
      "${LOG_DIR}/pcloud-drive-watchdog.stdout.log" \
      "${LOG_DIR}/pcloud-drive-watchdog.stderr.log"
  fi

  printf 'Uninstalled %s\n' "${LABEL}"
}

main "$@"
