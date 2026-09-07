#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
package_script="${repo_root}/scripts/package-app.sh"
verify_script="${repo_root}/scripts/verify-app.sh"
output_app="${repo_root}/build/TopTimer.app"
sentinel="${output_app}/Contents/Resources/transaction-test-sentinel.txt"

fingerprint() {
  /usr/bin/find "$1" -type f -exec /usr/bin/shasum -a 256 {} \; \
    | LC_ALL=C /usr/bin/sort \
    | /usr/bin/shasum -a 256 \
    | /usr/bin/awk '{ print $1 }'
}

/bin/bash "${package_script}" >/dev/null
printf 'existing verified output must survive late candidate failure\n' >"${sentinel}"
/usr/bin/codesign --force --deep --sign - "${output_app}" >/dev/null 2>&1
/bin/bash "${verify_script}" "${output_app}" >/dev/null
before="$(fingerprint "${output_app}")"

set +e
TOPTIMER_TEST_FAIL_AFTER_CANDIDATE_VERIFY=1 \
  /bin/bash "${package_script}" >/tmp/toptimer-transaction-test.log 2>&1
exit_code=$?
set -e
after="$(fingerprint "${output_app}")"

if [[ "${exit_code}" -eq 0 ]]; then
  echo "Expected forced late packaging failure" >&2
  exit 1
fi
if [[ "${before}" != "${after}" ]]; then
  echo "Existing verified output changed after late packaging failure" >&2
  exit 1
fi
/bin/bash "${verify_script}" "${output_app}" >/dev/null

echo "Transactional packaging test passed"
