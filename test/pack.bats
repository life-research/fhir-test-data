#!/usr/bin/env bats

load test_helper

setup() {
  setup_dirs
  build_fixtures "${BUILD_DIR}"
}

out() {
  echo "${OUT_DIR}/fixture-chunked/$1"
}

@test "pack creates base and one layer per chunk" {
  run "${SCRIPTS_DIR}/pack.sh" fixture-chunked
  [ "${status}" -eq 0 ]
  run ls "${OUT_DIR}/fixture-chunked"
  [ "${output}" == $'base.tar.gz\nchunk-1-3.tar.gz\nchunk-4-6.tar.gz\nchunk-7-9.tar.gz' ]
}

@test "base layer holds authored.json and extra files only" {
  "${SCRIPTS_DIR}/pack.sh" fixture-chunked
  run tar_entries "$(out base.tar.gz)"
  [ "${output}" == $'authored.json\nkds/checksums.sha256\nkds/hospitalInformation.json.gz\nkds/practitionerInformation.json.gz' ]
}

@test "chunks follow authored.json order" {
  "${SCRIPTS_DIR}/pack.sh" fixture-chunked
  [ "$(tar_entries "$(out chunk-1-3.tar.gz)")" == "$(first_patient_files 3 | sort)" ]
  [ "$(tar_entries "$(out chunk-4-6.tar.gz)")" == "$(first_patient_files 6 | tail -n 3 | sort)" ]
  [ "$(tar_entries "$(out chunk-7-9.tar.gz)")" == "$(first_patient_files 9 | tail -n 3 | sort)" ]
}

@test "tar entries are normalized" {
  "${SCRIPTS_DIR}/pack.sh" fixture-chunked
  TZ=UTC run tar -tvzf "$(out chunk-1-3.tar.gz)"
  [[ "${output}" == "-rw-r--r-- 0/0"* ]]
  [[ "${output}" == *"1970-01-01 00:00 kds/p-02.json.gz"* ]]
}

@test "pack is reproducible" {
  "${SCRIPTS_DIR}/pack.sh" fixture-chunked
  first="$(cd "${OUT_DIR}/fixture-chunked" && sha256sum -- *)"

  touch -d '2001-02-03' "${BUILD_DIR}"/fixture-chunked/kds/* "${BUILD_DIR}/fixture-chunked/authored.json"
  chmod 600 "${BUILD_DIR}"/fixture-chunked/kds/*
  "${SCRIPTS_DIR}/pack.sh" fixture-chunked
  second="$(cd "${OUT_DIR}/fixture-chunked" && sha256sum -- *)"

  [ "${first}" == "${second}" ]
}

@test "pack removes stale output" {
  mkdir -p "${OUT_DIR}/fixture-chunked"
  touch "$(out stale.tar.gz)"
  "${SCRIPTS_DIR}/pack.sh" fixture-chunked
  [ ! -e "$(out stale.tar.gz)" ]
}

@test "pack fails on missing patient file" {
  rm "${BUILD_DIR}/fixture-chunked/kds/p-05.json.gz"
  run "${SCRIPTS_DIR}/pack.sh" fixture-chunked
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"does not contain exactly the first 9 patients"* ]]
}

@test "pack fails on too few patients" {
  jq 'del(."p-04")' "${BUILD_DIR}/fixture-chunked/authored.json" >"${BATS_TEST_TMPDIR}/a.json"
  mv "${BATS_TEST_TMPDIR}/a.json" "${BUILD_DIR}/fixture-chunked/authored.json"
  run "${SCRIPTS_DIR}/pack.sh" fixture-chunked
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"fewer than 9 patients"* ]]
}

@test "pack fails on checksum mismatch" {
  gzip_json '{"tampered":true}' "${BUILD_DIR}/fixture-chunked/kds/p-01.json.gz"
  run "${SCRIPTS_DIR}/pack.sh" fixture-chunked
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"checksum verification failed"* ]]
}

@test "pack fails on missing extra file" {
  rm "${BUILD_DIR}/fixture-chunked/kds/hospitalInformation.json.gz"
  run "${SCRIPTS_DIR}/pack.sh" fixture-chunked
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"kds/hospitalInformation.json.gz missing"* ]]
}

@test "pack fails without input" {
  rm -r "${BUILD_DIR}/fixture-chunked"
  run "${SCRIPTS_DIR}/pack.sh" fixture-chunked
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"missing, put a local copy of 'fixture-chunked' there"* ]]
}

@test "pack reads an explicit input directory" {
  mv "${BUILD_DIR}/fixture-chunked" "${BATS_TEST_TMPDIR}/elsewhere"
  run "${SCRIPTS_DIR}/pack.sh" fixture-chunked "${BATS_TEST_TMPDIR}/elsewhere"
  [ "${status}" -eq 0 ]
  [ "$(tar_entries "$(out chunk-1-3.tar.gz)")" == "$(first_patient_files 3 | sort)" ]
}

@test "pack copies single file sets unchanged" {
  run "${SCRIPTS_DIR}/pack.sh" fixture-file
  [ "${status}" -eq 0 ]
  cmp "${BUILD_DIR}/fixture-file/fixture-1.0.zip" "${OUT_DIR}/fixture-file/fixture-1.0.zip"
}
