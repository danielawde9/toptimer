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

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "${plist_path}" 2>/dev/null)" != "true" ]]; then
  echo "LSUIElement must be true" >&2
  exit 1
fi

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${plist_path}" 2>/dev/null)" != "com.lelabodigital.TopTimer" ]]; then
  echo "Unexpected bundle identifier" >&2
  exit 1
fi

if [[ ! -f "${icon_path}" ]]; then
  echo "TopTimer icon missing" >&2
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
