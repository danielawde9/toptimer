#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
package_script="${repo_root}/scripts/package-app.sh"
verify_script="${repo_root}/scripts/verify-app.sh"

expect_failure() {
  local expected="$1"
  shift
  local output
  local exit_code
  set +e
  output="$("$@" 2>&1)"
  exit_code=$?
  set -e
  if [[ "${exit_code}" -eq 0 || "${output}" != *"${expected}"* ]]; then
    printf 'Expected failure containing %q, got exit %s:\n%s\n' \
      "${expected}" "${exit_code}" "${output}" >&2
    exit 1
  fi
}

expect_failure "Destination must be inside ${repo_root}/build" \
  /bin/bash "${package_script}" "/tmp/TopTimer.app"
expect_failure "Refusing unsafe app path: /" \
  /bin/bash "${verify_script}" "/"
expect_failure "Refusing unsafe app path: ${HOME}" \
  /bin/bash "${verify_script}" "${HOME}"
expect_failure "Refusing unsafe app path: ${repo_root}" \
  /bin/bash "${verify_script}" "${repo_root}"

echo "Packaging safety tests passed"
