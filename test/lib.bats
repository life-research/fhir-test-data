#!/usr/bin/env bats

load test_helper

setup() {
  setup_dirs
}

# Runs a snippet in a shell that has lib.sh sourced and <set> loaded.
run_lib() {
  local set="$1" snippet="$2"
  run bash -euo pipefail -c "source '${SCRIPTS_DIR}/lib.sh'; load_set '${set}'; ${snippet}"
}

@test "load_set rejects unknown set" {
  run_lib does-not-exist "true"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"unknown set: 'does-not-exist'"* ]]
}

@test "load_set rejects invalid set name" {
  run_lib "../etc" "true"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"invalid set name"* ]]
}

@test "load_set rejects unknown kind" {
  mkdir "${DATASETS_DIR}/broken"
  echo "KIND=other" >"${DATASETS_DIR}/broken/set.env"
  run_lib broken "true"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"unknown KIND 'other'"* ]]
}

@test "chunk_ranges yields cumulative ranges" {
  run_lib fixture-chunked chunk_ranges
  [ "${status}" -eq 0 ]
  [ "${output}" == $'1 3\n4 6\n7 9' ]
}

@test "chunk_name pads to the width of the last boundary" {
  run_lib fixture-chunked 'chunk_name 101 1000 10000'
  [ "${output}" == "chunk-00101-01000.tar.gz" ]
}

@test "layer_titles selects base and chunks up to the patient count" {
  run_lib fixture-chunked 'layer_titles 6'
  [ "${status}" -eq 0 ]
  [ "${output}" == $'base.tar.gz\nchunk-1-3.tar.gz\nchunk-4-6.tar.gz' ]
}

@test "layer_titles for kds boundaries" {
  run bash -c "source '${SCRIPTS_DIR}/lib.sh'; CHUNKS='100 1000 10000'; layer_titles 10000"
  [ "${output}" == $'base.tar.gz\nchunk-00001-00100.tar.gz\nchunk-00101-01000.tar.gz\nchunk-01001-10000.tar.gz' ]
}

@test "resolve_patients defaults to the smallest boundary" {
  run_lib fixture-chunked 'resolve_patients ""'
  [ "${output}" == "3" ]
}

@test "resolve_patients accepts chunk boundaries" {
  run_lib fixture-chunked 'resolve_patients 6'
  [ "${output}" == "6" ]
}

@test "resolve_patients rejects other counts" {
  run_lib fixture-chunked 'resolve_patients 5'
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"unsupported patient count '5', allowed: 3 6 9"* ]]
}

@test "resolve_digest picks the latest version by default" {
  printf 'v1 sha256:%064d\nv2 sha256:%064d\n' 1 2 >"${DATASETS_DIR}/fixture-file/digests"
  run_lib fixture-file 'resolve_digest fixture-file'
  [ "${output}" == "sha256:$(printf '%064d' 2)" ]
}

@test "resolve_digest picks a given version" {
  printf 'v1 sha256:%064d\nv2 sha256:%064d\n' 1 2 >"${DATASETS_DIR}/fixture-file/digests"
  run_lib fixture-file 'resolve_digest fixture-file v1'
  [ "${output}" == "sha256:$(printf '%064d' 1)" ]
}

@test "resolve_digest fails on unknown version" {
  printf 'v1 sha256:%064d\n' 1 >"${DATASETS_DIR}/fixture-file/digests"
  run_lib fixture-file 'resolve_digest fixture-file v9'
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"version 'v9' of 'fixture-file' not found"* ]]
}

@test "resolve_digest fails without published versions" {
  run_lib fixture-file 'resolve_digest fixture-file'
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"no published versions of 'fixture-file'"* ]]
}

@test "resolve_digest fails on malformed digest" {
  echo "v1 sha256:abc" >"${DATASETS_DIR}/fixture-file/digests"
  run_lib fixture-file 'resolve_digest fixture-file'
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"malformed digest"* ]]
}

@test "digest.sh prints the latest digest" {
  printf 'v1 sha256:%064d\n' 1 >"${DATASETS_DIR}/fixture-file/digests"
  run "${SCRIPTS_DIR}/digest.sh" fixture-file
  [ "${status}" -eq 0 ]
  [ "${output}" == "sha256:$(printf '%064d' 1)" ]
}

@test "verify.sh handles more patients in authored.json than requested" {
  build_fixtures "${BUILD_DIR}"
  dir="${BUILD_DIR}/fixture-chunked"
  # Enough extra keys to exceed the pipe buffer of a truncating reader.
  jq '. + ([range(20000)] | map({key: "extra-\(.)", value: ""}) | from_entries)' \
    "${dir}/authored.json" >"${BATS_TEST_TMPDIR}/authored.json"
  mv "${BATS_TEST_TMPDIR}/authored.json" "${dir}/authored.json"
  rm "${dir}"/kds/p-0[18].json.gz "${dir}"/kds/p-0[3-6].json.gz
  run "${SCRIPTS_DIR}/verify.sh" fixture-chunked "${dir}" 3
  [ "${status}" -eq 0 ]
}

@test "generic environment variables do not affect configuration" {
  run env -u FHIR_TEST_DATA_DATASETS_DIR -u FHIR_TEST_DATA_BUILD_DIR -u FHIR_TEST_DATA_OUT_DIR \
    REGISTRY=ghcr.io/example/unrelated PLAIN_HTTP=true \
    DATASETS_DIR=/nonexistent BUILD_DIR=/nonexistent OUT_DIR=/nonexistent \
    bash -c "source '${SCRIPTS_DIR}/lib.sh'; printf '%s\n' \"\${REGISTRY}\" \"\${PLAIN_HTTP}\" \"\${DATASETS_DIR}\" \"\${BUILD_DIR}\" \"\${OUT_DIR}\""
  root="$(cd "${SCRIPTS_DIR}/.." && pwd)"
  [ "${output}" == "ghcr.io/life-research/fhir-test-data"$'\n'"false"$'\n'"${root}/datasets"$'\n'"${root}/build"$'\n'"${root}/out" ]
}

@test "prefixed environment variables configure the scripts" {
  run env FHIR_TEST_DATA_REGISTRY=localhost:5000/x FHIR_TEST_DATA_PLAIN_HTTP=true \
    bash -c "source '${SCRIPTS_DIR}/lib.sh'; artifact_repo kds; oras_flags; echo \"\${DATASETS_DIR}\""
  [ "${output}" == "localhost:5000/x/kds"$'\n'"--plain-http"$'\n'"${DATASETS_DIR}" ]
}
