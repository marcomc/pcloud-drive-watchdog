#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)"
LABEL="com.marcomc.pcloud-drive-watchdog"

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  expected="$1"
  actual="$2"
  label="$3"

  if [ "${expected}" != "${actual}" ]; then
    fail "${label}: expected '${expected}', got '${actual}'"
  fi
}

assert_contains() {
  haystack="$1"
  needle="$2"
  label="$3"

  case "${haystack}" in
    *"${needle}"*)
      ;;
    *)
      fail "${label}: expected output to contain '${needle}'"
      ;;
  esac
}

plist_value() {
  plist_path="$1"
  key_path="$2"
  plutil -extract "${key_path}" raw -o - "${plist_path}"
}

make_fixture() {
  fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/pcloud-watchdog-test.XXXXXX")"
  mkdir -p \
    "${fixture_root}/home" \
    "${fixture_root}/pCloud Drive.app/Contents"
  printf '%s\n' "${fixture_root}"
}

cleanup_fixture() {
  rm -rf "${fixture_root:-}" 2>/dev/null || true
}

install_with_fixture() {
  fixture_root="$1"
  interval="$2"
  threshold="$3"
  mode="$4"

  HOME="${fixture_root}/home" \
    INTERVAL_SECONDS="${interval}" \
    PCLOUD_FAILURE_THRESHOLD="${threshold}" \
    PCLOUD_APP_PATH="${fixture_root}/pCloud Drive.app" \
    NO_LAUNCH=1 \
    "${PROJECT_ROOT}/scripts/install.sh" "${mode}"
}

test_fresh_install_writes_default_policy() {
  fixture_root="$(make_fixture)"
  trap cleanup_fixture EXIT INT TERM

  output="$(install_with_fixture "${fixture_root}" 300 2 install)"
  plist_path="${fixture_root}/home/Library/LaunchAgents/${LABEL}.plist"
  interval="$(plist_value "${plist_path}" StartInterval)"
  threshold="$(plist_value "${plist_path}" EnvironmentVariables.PCLOUD_FAILURE_THRESHOLD)"

  assert_contains "${output}" "Generated ${plist_path}" "fresh install output"
  assert_eq "300" "${interval}" "fresh install interval"
  assert_eq "2" "${threshold}" "fresh install threshold"

  cleanup_fixture
  trap - EXIT INT TERM
}

test_install_is_noop_when_already_installed() {
  fixture_root="$(make_fixture)"
  trap cleanup_fixture EXIT INT TERM

  install_with_fixture "${fixture_root}" 300 2 install >/dev/null
  output="$(install_with_fixture "${fixture_root}" 600 9 install)"
  plist_path="${fixture_root}/home/Library/LaunchAgents/${LABEL}.plist"
  interval="$(plist_value "${plist_path}" StartInterval)"
  threshold="$(plist_value "${plist_path}" EnvironmentVariables.PCLOUD_FAILURE_THRESHOLD)"

  assert_contains "${output}" "Already installed" "second install output"
  assert_eq "300" "${interval}" "noop interval"
  assert_eq "2" "${threshold}" "noop threshold"

  cleanup_fixture
  trap - EXIT INT TERM
}

test_configure_updates_existing_policy() {
  fixture_root="$(make_fixture)"
  trap cleanup_fixture EXIT INT TERM

  install_with_fixture "${fixture_root}" 300 2 install >/dev/null
  output="$(install_with_fixture "${fixture_root}" 600 9 configure)"
  plist_path="${fixture_root}/home/Library/LaunchAgents/${LABEL}.plist"
  interval="$(plist_value "${plist_path}" StartInterval)"
  threshold="$(plist_value "${plist_path}" EnvironmentVariables.PCLOUD_FAILURE_THRESHOLD)"

  assert_contains "${output}" "Configured ${LABEL}" "configure output"
  assert_eq "600" "${interval}" "configured interval"
  assert_eq "9" "${threshold}" "configured threshold"

  cleanup_fixture
  trap - EXIT INT TERM
}

test_invalid_threshold_is_rejected() {
  fixture_root="$(make_fixture)"
  trap cleanup_fixture EXIT INT TERM

  set +e
  output="$(install_with_fixture "${fixture_root}" 300 0 configure 2>&1)"
  status=$?
  set -e

  if [ "${status}" -eq 0 ]; then
    fail "invalid threshold should fail"
  fi
  assert_contains "${output}" "consecutive failure threshold must be between" "invalid threshold output"

  cleanup_fixture
  trap - EXIT INT TERM
}

test_fresh_install_writes_default_policy
test_install_is_noop_when_already_installed
test_configure_updates_existing_policy
test_invalid_threshold_is_rejected

printf 'ok - install/configure tests passed\n'
