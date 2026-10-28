#!/usr/bin/env bats

load test_helper

setup() {
  setup_dirs
}

@test "matrix is empty without published versions" {
  run "${SCRIPTS_DIR}/matrix.sh"
  [ "${status}" -eq 0 ]
  [ "${output}" == "[]" ]
}

@test "matrix lists every published version and patient count" {
  printf 'v1 sha256:%064d\nv2 sha256:%064d\n' 1 2 >"${DATASETS_DIR}/fixture-chunked/digests"
  printf '1.0 sha256:%064d\n' 3 >"${DATASETS_DIR}/fixture-file/digests"
  run "${SCRIPTS_DIR}/matrix.sh"
  [ "${status}" -eq 0 ]
  [ "$(jq -c 'length' <<<"${output}")" == "7" ]
  [ "$(jq -c 'map(select(.set == "fixture-chunked" and .version == "v2")) | map(.patients)' <<<"${output}")" \
    == '["3","6","9"]' ]
  [ "$(jq -c 'map(select(.set == "fixture-file"))' <<<"${output}")" \
    == '[{"set":"fixture-file","version":"1.0","patients":""}]' ]
}
