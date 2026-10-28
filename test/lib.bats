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
