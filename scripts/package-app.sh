#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "${script_dir}/.." && pwd -P)"
build_root="${repo_root}/build"
default_destination="${build_root}/TopTimer.app"
requested_destination="${1:-${default_destination}}"

if [[ "${requested_destination}" != /* ]]; then
  requested_destination="${PWD}/${requested_destination}"
fi

if [[ "${requested_destination}" != "${default_destination}" ]]; then
  echo "Destination must be inside ${build_root}" >&2
  exit 64
fi

/bin/mkdir -p "${build_root}"
destination="$(cd "$(dirname "${requested_destination}")" && pwd -P)/$(basename "${requested_destination}")"
if [[ "${destination}" != "${default_destination}" ]]; then
  echo "Destination must be inside ${build_root}" >&2
  exit 64
fi

temporary_directory="$(/usr/bin/mktemp -d "${build_root}/.package.XXXXXX")"
candidate="${temporary_directory}/TopTimer.app"
backup="${temporary_directory}/Previous-TopTimer.app"
published=0
cleanup() {
  if [[ -d "${backup}" && "${published}" -ne 1 ]]; then
    if [[ -e "${destination}" ]]; then
      echo "Previous TopTimer.app preserved at ${backup}; destination appeared concurrently" >&2
      return
    elif ! /bin/mv "${backup}" "${destination}"; then
      echo "Could not restore previous TopTimer.app; preserved at ${backup}" >&2
      return
    fi
  fi
  /bin/rm -rf "${temporary_directory}"
}
trap cleanup EXIT

cd "${repo_root}"
/usr/bin/swift build -c release -Xswiftc -warnings-as-errors
binary_directory="$(/usr/bin/swift build -c release --show-bin-path)"

/bin/mkdir -p "${candidate}/Contents/MacOS" "${candidate}/Contents/Resources"
/bin/cp "${binary_directory}/TopTimer" "${candidate}/Contents/MacOS/TopTimer"
/bin/chmod 755 "${candidate}/Contents/MacOS/TopTimer"
/bin/cp "${repo_root}/Sources/TopTimerApp/Resources/Info.plist" "${candidate}/Contents/Info.plist"
/usr/bin/swift "${repo_root}/scripts/generate-icon.swift" "${temporary_directory}"
/bin/cp "${temporary_directory}/TopTimer.icns" "${candidate}/Contents/Resources/TopTimer.icns"

/usr/bin/codesign --force --deep --sign - "${candidate}"
/bin/bash "${repo_root}/scripts/verify-app.sh" "${candidate}"

if [[ "${TOPTIMER_TEST_FAIL_AFTER_CANDIDATE_VERIFY:-0}" == "1" ]]; then
  echo "Forced failure after candidate verification" >&2
  exit 75
fi

if [[ -e "${destination}" ]]; then
  /bin/mv "${destination}" "${backup}"
fi
if ! /bin/mv "${candidate}" "${destination}"; then
  if [[ -d "${backup}" && ! -e "${destination}" ]]; then
    /bin/mv "${backup}" "${destination}"
  fi
  echo "Could not publish verified TopTimer.app" >&2
  exit 1
fi
published=1
/bin/rm -rf "${backup}"
