#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)"
WATCHDOG="${PROJECT_ROOT}/src/pcloud-drive-watchdog.sh"

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [ -n "${fake_pid:-}" ] && kill -0 "${fake_pid}" 2>/dev/null; then
    kill -KILL "${fake_pid}" 2>/dev/null || true
  fi
  if [ -n "${fake_launcher_pid:-}" ] && kill -0 "${fake_launcher_pid}" 2>/dev/null; then
    kill -KILL "${fake_launcher_pid}" 2>/dev/null || true
  fi
  rm -rf "${fixture_root:-}" 2>/dev/null || true
}

fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/pcloud-watchdog-runtime.XXXXXX")"
trap cleanup EXIT INT TERM

fake_app="${fixture_root}/pCloud Drive.app"
fake_executable="${fake_app}/Contents/MacOS/pCloud Drive"
mkdir -p "$(dirname -- "${fake_executable}")" "${fixture_root}/home"
mkdir -p "${fixture_root}/tmp"

cat > "${fake_executable}" <<'SCRIPT'
#!/bin/sh
trap '' TERM
while :; do
  sleep 60
done
SCRIPT
chmod 755 "${fake_executable}"

(
  "${fake_executable}" >/dev/null 2>&1 &
  printf '%s\n' "$!" > "${fixture_root}/fake.pid"
  wait "$!" 2>/dev/null || true
) &
fake_launcher_pid=$!

while [ ! -s "${fixture_root}/fake.pid" ]; do
  sleep 1
done
fake_pid="$(cat "${fixture_root}/fake.pid")"

if ! kill -0 "${fake_pid}" 2>/dev/null; then
  fail "fake pCloud process did not start"
fi

HOME="${fixture_root}/home" \
  TMPDIR="${fixture_root}/tmp" \
  PCLOUD_APP_PATH="${fake_app}" \
  PCLOUD_APP_BUNDLE_ID="test.invalid.pcloud" \
  PCLOUD_FAILURE_THRESHOLD=1 \
  PCLOUD_STATE_DIR="${fixture_root}/state" \
  PCLOUD_DRIVE_PATH="${fixture_root}/missing-drive" \
  PCLOUD_WATCHDOG_LOG_FILE="${fixture_root}/watchdog.log" \
  PCLOUD_QUIT_WAIT_SECONDS=0 \
  PCLOUD_FORCE_KILL_WAIT_SECONDS=1 \
  "${WATCHDOG}" >/dev/null 2>&1 || true

if kill -0 "${fake_pid}" 2>/dev/null; then
  fail "watchdog did not force-kill a pCloud process that ignored TERM"
fi

wait "${fake_pid}" 2>/dev/null || true
wait "${fake_launcher_pid}" 2>/dev/null || true
fake_pid=""
fake_launcher_pid=""
printf 'ok - runtime restart tests passed\n'
