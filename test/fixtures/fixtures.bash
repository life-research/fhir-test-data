# shellcheck shell=bash
# Generates the synthetic fixture data for the sets in test/fixtures/datasets.

# Patient keys deliberately not in sorted order: chunks follow authored.json.
FIXTURE_KEYS=(p-07 p-02 p-09 p-01 p-05 p-08 p-03 p-06 p-04)

gzip_json() {
  printf '%s' "$1" | gzip -n >"$2"
}

# Writes the input layout (authored.json, kds/...) of fixture-chunked.
make_chunked_data() {
  local dir="$1" key authored=""
  mkdir -p "${dir}/kds"
  for key in "${FIXTURE_KEYS[@]}"; do
    gzip_json "{\"resourceType\":\"Bundle\",\"id\":\"${key}\"}" "${dir}/kds/${key}.json.gz"
    authored+="${authored:+,}\"${key}\":\"2020-01-01T00:00:00+01:00\""
  done
  echo "{${authored}}" >"${dir}/authored.json"
  gzip_json '{"resourceType":"Bundle","id":"hospital"}' "${dir}/kds/hospitalInformation.json.gz"
  gzip_json '{"resourceType":"Bundle","id":"practitioner"}' "${dir}/kds/practitionerInformation.json.gz"
  (cd "${dir}/kds" && sha256sum -- *.json.gz >checksums.sha256)
}

# Writes the single file of fixture-file.
make_file_data() {
  local dir="$1"
  mkdir -p "${dir}"
  echo "fixture file content" >"${dir}/fixture-1.0.zip"
}

# Writes both fixtures as pack.sh input below <build_dir>.
build_fixtures() {
  local build_dir="$1"
  make_chunked_data "${build_dir}/fixture-chunked"
  make_file_data "${build_dir}/fixture-file"
}
