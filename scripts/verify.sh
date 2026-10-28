#!/usr/bin/env bash
# Verifies a pulled data set: exact patient selection and checksums for
# chunked sets, presence of the file otherwise.
#
# Usage: verify.sh <set> <path> [patients]
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

main() {
  [[ $# -ge 2 && $# -le 3 ]] || die "usage: verify.sh <set> <path> [patients]"
  local set="$1" path="$2" patients="${3:-}"
  load_set "${set}"

  if [[ "${KIND}" == "chunked" ]]; then
    patients="$(resolve_patients "${patients}")"
    verify_chunked_dir "${path}" "${patients}"
  else
    verify_file_dir "${path}"
  fi
  info "Verified ${set} in ${path}"
}

main "$@"
