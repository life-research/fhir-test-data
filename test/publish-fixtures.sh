#!/usr/bin/env bash
# Builds, packs and pushes both fixture sets as version "ci", for testing
# the action against a local registry. Uses the FHIR_TEST_DATA_* variables
# from the environment, see scripts/lib.sh.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${TEST_DIR}/../scripts"

# shellcheck source=test/fixtures/fixtures.bash
source "${TEST_DIR}/fixtures/fixtures.bash"

: "${FHIR_TEST_DATA_BUILD_DIR:?FHIR_TEST_DATA_BUILD_DIR must be set}"
build_fixtures "${FHIR_TEST_DATA_BUILD_DIR}"
for set in fixture-chunked fixture-file; do
  "${SCRIPTS_DIR}/pack.sh" "${set}"
  "${SCRIPTS_DIR}/push.sh" "${set}" ci
done
