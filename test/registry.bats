#!/usr/bin/env bats
# Round trip tests against a local OCI registry, e.g.:
#   docker run -d -p 5000:5000 registry:2

load test_helper

TEST_REGISTRY="${TEST_REGISTRY:-localhost:5000}"

setup_file() {
  curl -sf "http://${TEST_REGISTRY}/v2/" >/dev/null \
    || skip "no registry at ${TEST_REGISTRY}, start one with: docker run -d -p 5000:5000 registry:2"
  command -v oras >/dev/null || skip "oras not installed"
}

setup() {
  setup_dirs
  build_fixtures "${BUILD_DIR}"
  REGISTRY="${TEST_REGISTRY}/test-${BATS_ROOT_PID}-${BATS_SUITE_TEST_NUMBER}"
  export FHIR_TEST_DATA_PLAIN_HTTP=true
  export FHIR_TEST_DATA_REGISTRY="${REGISTRY}"
}

publish() {
  "${SCRIPTS_DIR}/pack.sh" "$1" >/dev/null
  "${SCRIPTS_DIR}/push.sh" "$1" "$2"
}

pulled() {
  echo "${BATS_TEST_TMPDIR}/pulled"
}

patient_files_in() {
  (cd "$1" && find kds -name 'p-*.json.gz' | sort)
}

@test "push records the manifest digest" {
  run publish fixture-chunked v1
  [ "${status}" -eq 0 ]
  digest="${lines[-1]}"
  [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]]
  [ "$(cat "${DATASETS_DIR}/fixture-chunked/digests")" == "v1 ${digest}" ]
}

@test "push sets artifact type and annotations" {
  publish fixture-chunked v1
  manifest="$(oras manifest fetch --plain-http "${REGISTRY}/fixture-chunked:v1")"
  [ "$(jq -r .artifactType <<<"${manifest}")" == "application/vnd.life-research.fhir-test-data.v1" ]
  [ "$(jq -r '.annotations["org.opencontainers.image.version"]' <<<"${manifest}")" == "v1" ]
  [ "$(jq -r '.annotations["org.opencontainers.image.licenses"]' <<<"${manifest}")" == "CC0-1.0" ]
  [ "$(jq -r '.annotations["org.opencontainers.image.source"]' <<<"${manifest}")" == "https://github.com/life-research/fhir-test-data" ]
  [ "$(jq -r '[.layers[].annotations["org.opencontainers.image.title"]] | join(" ")' <<<"${manifest}")" \
    == "base.tar.gz chunk-1-3.tar.gz chunk-4-6.tar.gz chunk-7-9.tar.gz" ]
}

@test "push refuses a version already recorded" {
  publish fixture-chunked v1
  run publish fixture-chunked v1
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"version 'v1' of 'fixture-chunked' is already recorded"* ]]
}

@test "push refuses an existing tag" {
  publish fixture-chunked v1
  : >"${DATASETS_DIR}/fixture-chunked/digests"
  run publish fixture-chunked v1
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"already exists"* ]]
}

@test "push fails if the registry cannot be checked" {
  export FHIR_TEST_DATA_REGISTRY="localhost:1/unreachable"
  run publish fixture-chunked v1
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"cannot check whether"* ]]
}

@test "push rejects invalid versions" {
  run "${SCRIPTS_DIR}/push.sh" fixture-chunked "v1/../x"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"invalid version"* ]]
}

@test "push fails without packed output" {
  run "${SCRIPTS_DIR}/push.sh" fixture-chunked v1
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"run pack.sh first"* ]]
}

@test "pull fetches the smallest chunk by default" {
  publish fixture-chunked v1
  run "${SCRIPTS_DIR}/pull.sh" fixture-chunked "$(pulled)"
  [ "${status}" -eq 0 ]
  [ "$(patient_files_in "$(pulled)")" == "$(first_patient_files 3 | sort)" ]
  [ -f "$(pulled)/authored.json" ]
  [ -f "$(pulled)/kds/hospitalInformation.json.gz" ]
}

@test "pull fetches exactly the requested patients" {
  publish fixture-chunked v1
  for patients in 3 6 9; do
    rm -rf "$(pulled)"
    "${SCRIPTS_DIR}/pull.sh" fixture-chunked "$(pulled)" "${patients}"
    [ "$(patient_files_in "$(pulled)")" == "$(first_patient_files "${patients}" | sort)" ]
    "${SCRIPTS_DIR}/verify.sh" fixture-chunked "$(pulled)" "${patients}"
  done
}

@test "pull selects a given version" {
  publish fixture-chunked v1
  gzip_json '{"resourceType":"Bundle","id":"hospital-v2"}' "${BUILD_DIR}/fixture-chunked/kds/hospitalInformation.json.gz"
  (cd "${BUILD_DIR}/fixture-chunked/kds" && sha256sum -- *.json.gz >checksums.sha256)
  publish fixture-chunked v2

  "${SCRIPTS_DIR}/pull.sh" fixture-chunked "$(pulled)" "" v1
  [ "$(zcat "$(pulled)/kds/hospitalInformation.json.gz")" == '{"resourceType":"Bundle","id":"hospital"}' ]
  rm -rf "$(pulled)"
  "${SCRIPTS_DIR}/pull.sh" fixture-chunked "$(pulled)"
  [ "$(zcat "$(pulled)/kds/hospitalInformation.json.gz")" == '{"resourceType":"Bundle","id":"hospital-v2"}' ]
}

@test "pull ignores a generic REGISTRY of the calling environment" {
  publish fixture-chunked v1
  REGISTRY=ghcr.io/example/unrelated run "${SCRIPTS_DIR}/pull.sh" fixture-chunked "$(pulled)"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Pulling ${REGISTRY}/fixture-chunked@sha256:"* ]]
}

@test "pull rejects unsupported patient counts" {
  publish fixture-chunked v1
  run "${SCRIPTS_DIR}/pull.sh" fixture-chunked "$(pulled)" 5
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"unsupported patient count '5'"* ]]
  [ ! -e "$(pulled)" ]
}

@test "pull refuses a non-empty target" {
  publish fixture-chunked v1
  mkdir -p "$(pulled)"
  touch "$(pulled)/existing"
  run "${SCRIPTS_DIR}/pull.sh" fixture-chunked "$(pulled)"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"is not empty"* ]]
}

@test "pull fails on a digest that is not in the registry" {
  printf 'v1 sha256:%064d\n' 0 >"${DATASETS_DIR}/fixture-chunked/digests"
  run "${SCRIPTS_DIR}/pull.sh" fixture-chunked "$(pulled)"
  [ "${status}" -ne 0 ]
}

@test "pull detects a manipulated chunk" {
  publish fixture-chunked v1
  gzip_json '{"tampered":true}' "${BUILD_DIR}/fixture-chunked/kds/p-07.json.gz"
  # Repack without pack.sh validation to smuggle in a tampered patient.
  (cd "${BUILD_DIR}/fixture-chunked" && tar -czf "${OUT_DIR}/fixture-chunked/chunk-1-3.tar.gz" \
    kds/p-07.json.gz kds/p-02.json.gz kds/p-09.json.gz)
  (cd "${OUT_DIR}/fixture-chunked" && oras push --plain-http "${REGISTRY}/fixture-chunked:tampered" \
    base.tar.gz chunk-1-3.tar.gz) >/dev/null
  digest="$(oras resolve --plain-http "${REGISTRY}/fixture-chunked:tampered")"
  echo "tampered ${digest}" >>"${DATASETS_DIR}/fixture-chunked/digests"

  run "${SCRIPTS_DIR}/pull.sh" fixture-chunked "$(pulled)" 3 tampered
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"checksum verification failed"* ]]
}

@test "file sets round trip unchanged" {
  publish fixture-file 1.0
  run "${SCRIPTS_DIR}/pull.sh" fixture-file "$(pulled)"
  [ "${status}" -eq 0 ]
  cmp "${BUILD_DIR}/fixture-file/fixture-1.0.zip" "$(pulled)/fixture-1.0.zip"
  "${SCRIPTS_DIR}/verify.sh" fixture-file "$(pulled)"
}

@test "file sets reject a patient count" {
  publish fixture-file 1.0
  run "${SCRIPTS_DIR}/pull.sh" fixture-file "$(pulled)" 100
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"patient count not supported"* ]]
}
