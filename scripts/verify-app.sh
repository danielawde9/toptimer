#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "${script_dir}/.." && pwd -P)"
requested_path="${1:-}"

if [[ -z "${requested_path}" ]]; then
  echo "Usage: $0 <path-to-TopTimer.app>" >&2
  exit 64
fi

if [[ "${requested_path}" != /* ]]; then
  requested_path="${PWD}/${requested_path}"
fi

if [[ ! -e "${requested_path}" ]]; then
  echo "TopTimer.app not found" >&2
  exit 1
fi

if [[ -d "${requested_path}" ]]; then
  app_path="$(cd "${requested_path}" && pwd -P)"
else
  app_path="$(cd "$(dirname "${requested_path}")" && pwd -P)/$(basename "${requested_path}")"
fi
home_path="$(cd "${HOME}" && pwd -P)"

case "${app_path}" in
  "/"|"${home_path}"|"${repo_root}")
    echo "Refusing unsafe app path: ${app_path}" >&2
    exit 1
    ;;
esac

executable_path="${app_path}/Contents/MacOS/TopTimer"
plist_path="${app_path}/Contents/Info.plist"
icon_path="${app_path}/Contents/Resources/TopTimer.icns"

if [[ ! -x "${executable_path}" ]]; then
  echo "TopTimer executable missing or not executable" >&2
  exit 1
fi

if ! /usr/bin/plutil -lint "${plist_path}" >/dev/null; then
  echo "Info.plist is missing or invalid" >&2
  exit 1
fi

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "${plist_path}" 2>/dev/null
}

if [[ "$(plist_value CFBundleExecutable)" != "TopTimer" ]]; then
  echo "CFBundleExecutable must be TopTimer" >&2
  exit 1
fi

if [[ "$(plist_value CFBundleIconFile)" != "TopTimer" ]]; then
  echo "CFBundleIconFile must be TopTimer" >&2
  exit 1
fi

if [[ "$(plist_value CFBundlePackageType)" != "APPL" ]]; then
  echo "CFBundlePackageType must be APPL" >&2
  exit 1
fi

if [[ "$(plist_value CFBundleShortVersionString)" != "1.0.0" ]]; then
  echo "CFBundleShortVersionString must be 1.0.0" >&2
  exit 1
fi

if [[ "$(plist_value CFBundleVersion)" != "1" ]]; then
  echo "CFBundleVersion must be 1" >&2
  exit 1
fi

if [[ "$(plist_value LSMinimumSystemVersion)" != "13.5" ]]; then
  echo "LSMinimumSystemVersion must be 13.5" >&2
  exit 1
fi

if [[ "$(plist_value LSUIElement)" != "true" ]]; then
  echo "LSUIElement must be true" >&2
  exit 1
fi

if [[ "$(plist_value CFBundleIdentifier)" != "com.danielawde9.toptimer" ]]; then
  echo "CFBundleIdentifier must be com.danielawde9.toptimer" >&2
  exit 1
fi

executable_description="$(/usr/bin/file -b "${executable_path}")"
if [[ "${executable_description}" != *"Mach-O"* ]]; then
  echo "TopTimer executable must be Mach-O" >&2
  exit 1
fi

architectures="$(/usr/bin/lipo -archs "${executable_path}" 2>/dev/null)"
if [[ -z "${architectures}" ]]; then
  echo "TopTimer executable has no supported architecture" >&2
  exit 1
fi
for architecture in ${architectures}; do
  case "${architecture}" in
    arm64|x86_64) ;;
    *)
      echo "TopTimer executable has unsupported architecture: ${architecture}" >&2
      exit 1
      ;;
  esac
done

if [[ ! -s "${icon_path}" ]]; then
  echo "TopTimer icon must be a nonempty valid ICNS file" >&2
  exit 1
fi
icon_test_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/toptimer-icon-verify.XXXXXX")"
cleanup_icon_test() {
  /bin/rm -rf "${icon_test_root}"
}
trap cleanup_icon_test EXIT
if ! /usr/bin/iconutil -c iconset "${icon_path}" -o "${icon_test_root}/TopTimer.iconset" >/dev/null 2>&1; then
  echo "TopTimer icon must be a nonempty valid ICNS file" >&2
  exit 1
fi

if ! /usr/bin/codesign --verify --deep --strict "${app_path}" >/dev/null 2>&1; then
  echo "TopTimer.app has no valid code signature" >&2
  exit 1
fi

signature_details="$(/usr/bin/codesign -dv --verbose=4 "${app_path}" 2>&1)"
if [[ "${signature_details}" != *"Signature=adhoc"* ]]; then
  echo "TopTimer.app must use an ad-hoc code signature" >&2
  exit 1
fi

echo "TopTimer.app verified"
