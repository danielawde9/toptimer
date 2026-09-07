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
cleanup() {
  /bin/rm -rf "${temporary_directory}"
}
trap cleanup EXIT

cd "${repo_root}"
/usr/bin/swift build -c release -Xswiftc -warnings-as-errors
binary_directory="$(/usr/bin/swift build -c release --show-bin-path)"

/bin/rm -rf "${default_destination}"
/bin/mkdir -p "${destination}/Contents/MacOS" "${destination}/Contents/Resources"
/bin/cp "${binary_directory}/TopTimer" "${destination}/Contents/MacOS/TopTimer"
/bin/chmod 755 "${destination}/Contents/MacOS/TopTimer"
/bin/cp "${repo_root}/Sources/TopTimerApp/Resources/Info.plist" "${destination}/Contents/Info.plist"
/usr/bin/swift "${repo_root}/scripts/generate-icon.swift" "${temporary_directory}"
/bin/cp "${temporary_directory}/TopTimer.icns" "${destination}/Contents/Resources/TopTimer.icns"

/usr/bin/codesign --force --deep --sign - "${destination}"
/bin/bash "${repo_root}/scripts/verify-app.sh" "${destination}"
