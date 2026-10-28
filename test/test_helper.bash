# shellcheck shell=bash disable=SC2034
# Common setup for all bats tests. Every test gets its own datasets, build
# and out directories below BATS_TEST_TMPDIR.

SCRIPTS_DIR="$(cd "${BATS_TEST_DIRNAME}/../scripts" && pwd)"
FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures"

# shellcheck source=test/fixtures/fixtures.bash
source "${FIXTURES_DIR}/fixtures.bash"

setup_dirs() {
  DATASETS_DIR="${BATS_TEST_TMPDIR}/datasets"
  BUILD_DIR="${BATS_TEST_TMPDIR}/build"
  OUT_DIR="${BATS_TEST_TMPDIR}/out"
  export FHIR_TEST_DATA_DATASETS_DIR="${DATASETS_DIR}"
  export FHIR_TEST_DATA_BUILD_DIR="${BUILD_DIR}"
  export FHIR_TEST_DATA_OUT_DIR="${OUT_DIR}"
  cp -r "${FIXTURES_DIR}/datasets" "${DATASETS_DIR}"
  mkdir -p "${BUILD_DIR}"
}

# Lists tar entries of a gzipped tarball, one per line.
tar_entries() {
  tar -tzf "$1"
}

# Prints the patient files of the first <n> fixture keys.
first_patient_files() {
  local key
  for key in "${FIXTURE_KEYS[@]:0:$1}"; do
    echo "kds/${key}.json.gz"
  done
}
