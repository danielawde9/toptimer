#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
verify_script="${repo_root}/scripts/verify-app.sh"
source_app="${repo_root}/build/TopTimer.app"
test_root="$(/usr/bin/mktemp -d "${repo_root}/build/.verify-tests.XXXXXX")"
failures=0

cleanup() {
  /bin/rm -rf "${test_root}"
}
trap cleanup EXIT

resign() {
  /usr/bin/codesign --force --deep --sign - "$1" >/dev/null 2>&1
}

expect_rejection() {
  local name="$1"
  local expected="$2"
  local fixture="${test_root}/${name}.app"
  local output
  local exit_code
  /usr/bin/ditto "${source_app}" "${fixture}"
  shift 2
  "$@" "${fixture}"
  set +e
  output="$(/bin/bash "${verify_script}" "${fixture}" 2>&1)"
  exit_code=$?
  set -e
  if [[ "${exit_code}" -eq 0 || "${output}" != *"${expected}"* ]]; then
    printf 'RED %s: expected rejection containing %q, got exit %s: %s\n' \
      "${name}" "${expected}" "${exit_code}" "${output}" >&2
    failures=$((failures + 1))
  fi
}

set_plist_value() {
  local key="$1"
  local value="$2"
  local fixture="$3"
  /usr/libexec/PlistBuddy -c "Set :${key} ${value}" "${fixture}/Contents/Info.plist"
  resign "${fixture}"
}

corrupt_executable_type() {
  local fixture="$1"
  printf '#!/bin/bash\nexit 0\n' >"${fixture}/Contents/MacOS/TopTimer"
  /bin/chmod 755 "${fixture}/Contents/MacOS/TopTimer"
  resign "${fixture}"
}

remove_executable() {
  local fixture="$1"
  /bin/rm "${fixture}/Contents/MacOS/TopTimer"
  resign "${fixture}"
}

make_executable_nonexecutable() {
  local fixture="$1"
  /bin/chmod 644 "${fixture}/Contents/MacOS/TopTimer"
  resign "${fixture}"
}

use_unsupported_architecture() {
  local fixture="$1"
  printf '\x07\x00\x00\x00' \
    | /bin/dd of="${fixture}/Contents/MacOS/TopTimer" bs=1 seek=4 conv=notrunc 2>/dev/null
  resign "${fixture}"
}

empty_icon() {
  local fixture="$1"
  : >"${fixture}/Contents/Resources/TopTimer.icns"
  resign "${fixture}"
}

invalid_icon() {
  local fixture="$1"
  printf 'not an icns file\n' >"${fixture}/Contents/Resources/TopTimer.icns"
  resign "${fixture}"
}

remove_icon() {
  local fixture="$1"
  /bin/rm "${fixture}/Contents/Resources/TopTimer.icns"
  resign "${fixture}"
}

invalidate_plist() {
  local fixture="$1"
  printf 'not a property list\n' >"${fixture}/Contents/Info.plist"
  resign "${fixture}"
}

break_signature() {
  local fixture="$1"
  printf 'tamper\n' >>"${fixture}/Contents/Info.plist"
}

/bin/bash "${verify_script}" "${source_app}" >/dev/null
expect_rejection executable-name "CFBundleExecutable must be TopTimer" \
  set_plist_value CFBundleExecutable OtherExecutable
expect_rejection icon-name "CFBundleIconFile must be TopTimer" \
  set_plist_value CFBundleIconFile OtherIcon
expect_rejection package-type "CFBundlePackageType must be APPL" \
  set_plist_value CFBundlePackageType BNDL
expect_rejection short-version "CFBundleShortVersionString must be 1.0.0" \
  set_plist_value CFBundleShortVersionString 9.9.9
expect_rejection build-version "CFBundleVersion must be 1" \
  set_plist_value CFBundleVersion 2
expect_rejection minimum-system "LSMinimumSystemVersion must be 13.5" \
  set_plist_value LSMinimumSystemVersion 14.0
expect_rejection agent-app "LSUIElement must be true" \
  set_plist_value LSUIElement false
expect_rejection identifier "CFBundleIdentifier must be com.danielawde9.toptimer" \
  set_plist_value CFBundleIdentifier com.example.TopTimer
expect_rejection invalid-plist "Info.plist is missing or invalid" invalidate_plist
expect_rejection missing-executable "TopTimer executable missing or not executable" remove_executable
expect_rejection nonexecutable "TopTimer executable missing or not executable" make_executable_nonexecutable
expect_rejection executable-format "TopTimer executable must be Mach-O" corrupt_executable_type
expect_rejection executable-architecture "TopTimer executable has unsupported architecture:" \
  use_unsupported_architecture
expect_rejection missing-icon "TopTimer icon must be a nonempty valid ICNS file" remove_icon
expect_rejection empty-icon "TopTimer icon must be a nonempty valid ICNS file" empty_icon
expect_rejection invalid-icon "TopTimer icon must be a nonempty valid ICNS file" invalid_icon
expect_rejection invalid-signature "TopTimer.app has no valid code signature" break_signature

if [[ "${failures}" -ne 0 ]]; then
  printf '%s verification contract fixture(s) were accepted or rejected incorrectly\n' \
    "${failures}" >&2
  exit 1
fi

echo "Verification contract tests passed"
