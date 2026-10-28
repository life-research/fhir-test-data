#!/usr/bin/env bash
# Pushes out/<set>/ as <registry>/<set>:<version> and records the manifest
# digest in datasets/<set>/digests. Refuses to overwrite existing versions.
#
# Usage: push.sh <set> <version>
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_version_unrecorded() {
  local set="$1" version="$2" file
  file="$(digests_file "${set}")"
  if [[ -f "${file}" ]] && awk -v v="${version}" '$1 == v { found = 1 } END { exit !found }' "${file}"; then
    die "version '${version}' of '${set}' is already recorded in ${file}"
  fi
}

assert_tag_absent() {
  local ref="$1" output
  # shellcheck disable=SC2046
  if output="$(oras resolve $(oras_flags) "${ref}" 2>&1)"; then
    die "${ref} already exists (${output}), tags are immutable"
  fi
  [[ "${output}" == *"not found"* ]] || die "cannot check whether ${ref} exists: ${output}"
}

layer_files() {
  if [[ "${KIND}" == "chunked" ]]; then
    layer_titles "$(last_chunk_boundary)"
  else
    echo "${FILE}"
  fi
}

layer_media_type() {
  if [[ "${KIND}" == "chunked" ]]; then
    echo "${TAR_GZ_MEDIA_TYPE}"
  else
    echo "${FILE_MEDIA_TYPE}"
  fi
}

push_artifact() {
  local ref="$1" out="$2" version="$3" files file media_type layers=()
  mapfile -t files < <(layer_files)
  media_type="$(layer_media_type)"
  for file in "${files[@]}"; do
    [[ -f "${out}/${file}" ]] || die "${out}/${file} missing, run pack.sh first"
    layers+=("${file}:${media_type}")
  done
  # shellcheck disable=SC2046
  (cd "${out}" && oras push $(oras_flags) --format json \
    --artifact-type "${ARTIFACT_TYPE}" \
    --annotation "org.opencontainers.image.source=${SOURCE_URL}" \
    --annotation "org.opencontainers.image.description=${DESCRIPTION}" \
    --annotation "org.opencontainers.image.licenses=${LICENSES}" \
    --annotation "org.opencontainers.image.version=${version}" \
    "${ref}" "${layers[@]}") | jq -er .digest
}

main() {
  [[ $# -eq 2 ]] || die "usage: push.sh <set> <version>"
  local set="$1" version="$2"
  [[ "${version}" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$ ]] || die "invalid version: '${version}'"
  load_set "${set}"

  local ref out digest
  ref="$(artifact_repo "${set}"):${version}"
  out="${OUT_DIR}/${set}"

  assert_version_unrecorded "${set}" "${version}"
  assert_tag_absent "${ref}"

  info "Pushing ${ref}"
  digest="$(push_artifact "${ref}" "${out}" "${version}")"
  echo "${version} ${digest}" >>"$(digests_file "${set}")"
  info "Pushed ${ref}@${digest}"
  echo "${digest}"
}

main "$@"
