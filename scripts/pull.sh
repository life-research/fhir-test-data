#!/usr/bin/env bash
# Pulls a published data set into <path>. Only the layers needed for the
# requested patient count are downloaded.
#
# Usage: pull.sh <set> <path> [patients] [version]
#   patients  chunked sets only, must be a chunk boundary (default: smallest)
#   version   published version (default: latest in datasets/<set>/digests)
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

validate_patients() {
  if [[ "${KIND}" == "chunked" ]]; then
    resolve_patients "$1"
  elif [[ -n "$1" ]]; then
    die "set is not chunked, patient count not supported"
  fi
}

prepare_target() {
  local path="$1"
  mkdir -p "${path}"
  [[ -z "$(ls -A "${path}")" ]] || die "${path} is not empty"
}

layer_digest() {
  local manifest="$1" title="$2"
  jq -er --arg title "${title}" \
    '.layers[] | select(.annotations["org.opencontainers.image.title"] == $title) | .digest' \
    <<<"${manifest}" || die "layer '${title}' not found in manifest"
}

fetch_blob() {
  local repo="$1" digest="$2" output="$3"
  # shellcheck disable=SC2046
  oras blob fetch $(oras_flags) --output "${output}" "${repo}@${digest}"
}

pull_chunked() {
  local repo="$1" manifest="$2" path="$3" patients="$4" title digest
  while read -r title; do
    info "Fetching ${title}"
    digest="$(layer_digest "${manifest}" "${title}")"
    fetch_blob "${repo}" "${digest}" - | tar -xz --no-same-owner -C "${path}"
  done < <(layer_titles "${patients}")
  verify_chunked_dir "${path}" "${patients}"
}

pull_file() {
  local repo="$1" manifest="$2" path="$3" digest
  info "Fetching ${FILE}"
  digest="$(layer_digest "${manifest}" "${FILE}")"
  fetch_blob "${repo}" "${digest}" "${path}/${FILE}"
  verify_file_dir "${path}"
}

main() {
  [[ $# -ge 2 && $# -le 4 ]] || die "usage: pull.sh <set> <path> [patients] [version]"
  local set="$1" path="$2" patients="${3:-}" version="${4:-}"
  load_set "${set}"
  patients="$(validate_patients "${patients}")"

  local repo digest manifest
  repo="$(artifact_repo "${set}")"
  digest="$(resolve_digest "${set}" "${version}")"
  prepare_target "${path}"

  info "Pulling ${repo}@${digest}"
  # shellcheck disable=SC2046
  manifest="$(oras manifest fetch $(oras_flags) "${repo}@${digest}")"
  "pull_${KIND}" "${repo}" "${manifest}" "${path}" "${patients}"
  info "Pulled ${set} into ${path}"
}

main "$@"
