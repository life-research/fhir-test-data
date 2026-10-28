#!/usr/bin/env bash
# Prints the manifest digest of a published data set version.
#
# Usage: digest.sh <set> [version]
#   version  published version (default: latest in datasets/<set>/digests)
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

main() {
  [[ $# -ge 1 && $# -le 2 ]] || die "usage: digest.sh <set> [version]"
  load_set "$1"
  resolve_digest "$1" "${2:-}"
}

main "$@"
