# shellcheck shell=bash disable=SC2034
# Common setup for all bats tests. Every test gets its own DATASETS_DIR,
# BUILD_DIR and OUT_DIR below BATS_TEST_TMPDIR.

SCRIPTS_DIR="$(cd "${BATS_TEST_DIRNAME}/../scripts" && pwd)"
FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures"

# shellcheck source=test/fixtures/fixtures.bash
source "${FIXTURES_DIR}/fixtures.bash"

setup_dirs() {
  export DATASETS_DIR="${BATS_TEST_TMPDIR}/datasets"
  export BUILD_DIR="${BATS_TEST_TMPDIR}/build"
  export OUT_DIR="${BATS_TEST_TMPDIR}/out"
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
