#!/usr/bin/env bash
# Prints a JSON array with one {set, version, patients} entry per published
# version and allowed patient count. Used as CI matrix.
#
# Usage: matrix.sh
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

patient_counts() {
  if [[ "${KIND}" == "chunked" ]]; then
    chunk_ranges | cut -d ' ' -f 2
  else
    echo ""
  fi
}

published_entries() {
  local env_file set version digest patients
  for env_file in "${DATASETS_DIR}"/*/set.env; do
    set="$(basename "$(dirname "${env_file}")")"
    load_set "${set}"
    [[ -f "$(digests_file "${set}")" ]] || continue
    while read -r version digest; do
      [[ -n "${version}" ]] || continue
      while read -r patients; do
        jq -nc --arg set "${set}" --arg version "${version}" --arg patients "${patients}" \
          '{set: $set, version: $version, patients: $patients}'
      done < <(patient_counts)
    done <"$(digests_file "${set}")"
  done
}

main() {
  [[ $# -eq 0 ]] || die "usage: matrix.sh"
  published_entries | jq -sc .
}

main "$@"
