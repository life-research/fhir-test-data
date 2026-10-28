# shellcheck shell=bash disable=SC2034
# Shared helpers for pack.sh, push.sh, pull.sh, digest.sh and verify.sh.
# Source this file; do not execute it.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DATASETS_DIR="${DATASETS_DIR:-${ROOT_DIR}/datasets}"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out}"
REGISTRY="${REGISTRY:-ghcr.io/life-research/fhir-test-data}"
PLAIN_HTTP="${PLAIN_HTTP:-false}"

readonly ARTIFACT_TYPE="application/vnd.life-research.fhir-test-data.v1"
readonly SOURCE_URL="https://github.com/life-research/fhir-test-data"
readonly AUTHORED_FILE="authored.json"
readonly PATIENT_DIR="kds"
readonly BASE_LAYER="base.tar.gz"
readonly TAR_GZ_MEDIA_TYPE="application/vnd.oci.image.layer.v1.tar+gzip"
readonly FILE_MEDIA_TYPE="application/octet-stream"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

info() {
  echo "$*" >&2
}

# Loads datasets/<set>/set.env into KIND, DESCRIPTION, LICENSES and
# either CHUNKS + EXTRA_FILES (KIND=chunked) or FILE (KIND=file).
load_set() {
  local set="$1"
  [[ "${set}" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || die "invalid set name: '${set}'"
  local env_file="${DATASETS_DIR}/${set}/set.env"
  [[ -f "${env_file}" ]] || die "unknown set: '${set}' (no ${env_file})"

  KIND="" DESCRIPTION="" LICENSES="" CHUNKS="" EXTRA_FILES="" FILE=""
  # shellcheck source=/dev/null
  source "${env_file}"

  case "${KIND}" in
    chunked) [[ -n "${CHUNKS}" ]] || die "${env_file}: CHUNKS missing" ;;
    file) [[ -n "${FILE}" ]] || die "${env_file}: FILE missing" ;;
    *) die "${env_file}: unknown KIND '${KIND}'" ;;
  esac
}

digests_file() {
  echo "${DATASETS_DIR}/$1/digests"
}

artifact_repo() {
  echo "${REGISTRY}/$1"
}

# Prints the digest of a published version, or of the latest one if no
# version is given. Lines in the digests file: "<version> <digest>".
resolve_digest() {
  local set="$1" version="${2:-}" file digest
  file="$(digests_file "${set}")"
  [[ -s "${file}" ]] || die "no published versions of '${set}' in ${file}"
  if [[ -n "${version}" ]]; then
    digest="$(awk -v v="${version}" '$1 == v { print $2 }' "${file}")"
    [[ -n "${digest}" ]] || die "version '${version}' of '${set}' not found in ${file}"
  else
    digest="$(awk 'NF { d = $2 } END { print d }' "${file}")"
  fi
  [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || die "malformed digest '${digest}' in ${file}"
  echo "${digest}"
}

oras_flags() {
  if [[ "${PLAIN_HTTP}" == "true" ]]; then
    echo "--plain-http"
  fi
}

# Chunk boundaries are cumulative patient counts, e.g. "100 1000 10000".
# Prints one "<from> <to>" line per chunk.
chunk_ranges() {
  local from=1 to
  for to in ${CHUNKS}; do
    echo "${from} ${to}"
    from=$((to + 1))
  done
}

last_chunk_boundary() {
  local boundaries
  read -r -a boundaries <<<"${CHUNKS}"
  echo "${boundaries[-1]}"
}

chunk_name() {
  local from="$1" to="$2" width
  width="${#3}"
  printf 'chunk-%0*d-%0*d.tar.gz\n' "${width}" "${from}" "${width}" "${to}"
}

# Validates a requested patient count against the chunk boundaries.
# Empty selects the smallest chunk boundary.
resolve_patients() {
  local requested="${1:-}" boundary
  if [[ -z "${requested}" ]]; then
    read -r boundary _ <<<"${CHUNKS}"
    echo "${boundary}"
    return
  fi
  for boundary in ${CHUNKS}; do
    if [[ "${requested}" == "${boundary}" ]]; then
      echo "${requested}"
      return
    fi
  done
  die "unsupported patient count '${requested}', allowed: ${CHUNKS}"
}

# Prints the layer titles needed for the given patient count.
layer_titles() {
  local patients="$1" last from to
  last="$(last_chunk_boundary)"
  echo "${BASE_LAYER}"
  while read -r from to; do
    ((from <= patients)) || break
    chunk_name "${from}" "${to}" "${last}"
  done < <(chunk_ranges)
}

# Files of a chunked set that are not patients: authored.json and EXTRA_FILES.
base_files() {
  local extra_files
  read -r -a extra_files <<<"${EXTRA_FILES}"
  printf '%s\n' "${AUTHORED_FILE}" "${extra_files[@]}"
}

# Prints the keys of authored.json in order, optionally only the first <limit>.
patient_keys() {
  local dir="$1" limit="${2:-}"
  jq -r --arg limit "${limit}" \
    'keys_unsorted | if $limit == "" then . else .[:($limit | tonumber)] end | .[]' \
    "${dir}/${AUTHORED_FILE}"
}

patient_file() {
  echo "${PATIENT_DIR}/$1.json.gz"
}

# Asserts that <dir> holds exactly the first <patients> patients of
# authored.json, the extra files, and that all checksums match.
verify_chunked_dir() {
  local dir="$1" patients="$2" file expected actual
  while read -r file; do
    [[ -f "${dir}/${file}" ]] || die "${dir}/${file} missing"
  done < <(base_files)

  expected="$(patient_keys "${dir}" "${patients}" | LC_ALL=C sort)"
  actual="$(LC_ALL=C comm -12 \
    <(patient_keys "${dir}" | LC_ALL=C sort) \
    <(find "${dir}/${PATIENT_DIR}" -maxdepth 1 -name '*.json.gz' -printf '%f\n' \
      | sed 's/\.json\.gz$//' | LC_ALL=C sort))"
  [[ "$(grep -c . <<<"${expected}")" == "${patients}" ]] \
    || die "${dir}/${AUTHORED_FILE} has fewer than ${patients} patients"
  [[ "${expected}" == "${actual}" ]] \
    || die "${dir}/${PATIENT_DIR} does not contain exactly the first ${patients} patients"

  (cd "${dir}/${PATIENT_DIR}" && sha256sum --quiet --strict -c --ignore-missing checksums.sha256) \
    || die "checksum verification failed in ${dir}/${PATIENT_DIR}"
}

verify_file_dir() {
  local dir="$1"
  [[ -s "${dir}/${FILE}" ]] || die "${dir}/${FILE} missing or empty"
}

# Asserts that <dir> holds the complete set, as required for packing.
verify_complete_set() {
  if [[ "${KIND}" == "chunked" ]]; then
    verify_chunked_dir "$1" "$(last_chunk_boundary)"
  else
    verify_file_dir "$1"
  fi
}
