#!/usr/bin/env bash
# Packs a local copy of a data set into reproducible OCI layer files in
# out/<set>/. The input is not tracked by git; see README.md for its layout.
#
# Usage: pack.sh <set> [input-dir]
#   input-dir  local copy of the data set (default: build/<set>)
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Writes a reproducible tar.gz of the files listed on stdin (relative to <dir>).
reproducible_tar_gz() {
  local dir="$1" output="$2"
  LC_ALL=C sort \
    | tar --create --file=- --directory="${dir}" --no-recursion \
      --format=gnu --mtime=@0 --owner=0 --group=0 --numeric-owner \
      --mode=u=rw,go=r --files-from=- \
    | gzip -n -9 >"${output}"
}

pack_chunked() {
  local src="$1" out="$2" keys last from to name
  keys="$(patient_keys "${src}")"
  last="$(last_chunk_boundary)"

  info "Packing ${BASE_LAYER}"
  base_files | reproducible_tar_gz "${src}" "${out}/${BASE_LAYER}"

  while read -r from to; do
    name="$(chunk_name "${from}" "${to}" "${last}")"
    info "Packing ${name}"
    sed -n "${from},${to}p" <<<"${keys}" \
      | while read -r key; do patient_file "${key}"; done \
      | reproducible_tar_gz "${src}" "${out}/${name}"
  done < <(chunk_ranges)
}

pack_file() {
  local src="$1" out="$2"
  info "Copying ${FILE}"
  cp "${src}/${FILE}" "${out}/${FILE}"
}

main() {
  [[ $# -ge 1 && $# -le 2 ]] || die "usage: pack.sh <set> [input-dir]"
  local set="$1"
  load_set "${set}"

  local src="${2:-${BUILD_DIR}/${set}}" out="${OUT_DIR}/${set}"
  [[ -d "${src}" ]] || die "${src} missing, put a local copy of '${set}' there"
  verify_complete_set "${src}"
  rm -rf "${out}"
  mkdir -p "${out}"

  "pack_${KIND}" "${src}" "${out}"
  (cd "${out}" && sha256sum -- *)
}

main "$@"
