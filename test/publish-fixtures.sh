#!/usr/bin/env bash
# Builds, packs and pushes both fixture sets as version "ci", for testing
# the action against a local registry. Uses DATASETS_DIR, BUILD_DIR,
# OUT_DIR, REGISTRY and PLAIN_HTTP from the environment.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${TEST_DIR}/../scripts"

# shellcheck source=test/fixtures/fixtures.bash
source "${TEST_DIR}/fixtures/fixtures.bash"

: "${BUILD_DIR:?BUILD_DIR must be set}"
build_fixtures "${BUILD_DIR}"
for set in fixture-chunked fixture-file; do
  "${SCRIPTS_DIR}/pack.sh" "${set}"
  "${SCRIPTS_DIR}/push.sh" "${set}" ci
done
