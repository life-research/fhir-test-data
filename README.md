# FHIR Test Data

Public, synthetic FHIR test data sets, hosted as OCI artifacts on GHCR and
reachable from GitHub-hosted runners and developer machines without
credentials.

| Set                                             | Content                                               | Pull Options                 |
|-------------------------------------------------|-------------------------------------------------------|------------------------------|
| [`kds`](datasets/kds)                           | MII KDS patients (10 000)                             | `patients`: 100, 1000, 10000 |
| [`kds-fhir-consent`](datasets/kds-fhir-consent) | MII KDS patients with FHIR consents (100)             | `patients`: 100              |
| [`synthea-1000`](datasets/synthea-1000)         | Synthea patients (1000), `synthea-1000.tar`           | –                            |
| [`fhir-definitions`](datasets/fhir-definitions) | HL7 FHIR R4 definitions, `fhir-definitions-4.0.1.zip` | –                            |

All data is synthetic. Never add real patient data. License-restricted
terminologies (LOINC, SNOMED CT) are not hosted here.

## Usage

### GitHub Action

```yaml
- uses: life-research/fhir-test-data@<commit-sha> # pin a commit
  with:
    set: kds
    patients: 1000      # chunked sets only, default: smallest chunk
    path: test-data/kds # must be empty or absent
    cache: true         # optional, actions/cache keyed on digest and patients
```

Pinning the action commit pins the data version and its digest: the action
reads the latest version from [`datasets/<set>/digests`](datasets) at that
commit. Use the `version` input to select an older published version. The
`digest` output holds the manifest digest.

### Locally

Requires [ORAS](https://oras.land/docs/installation) (≥ 1.2), `jq` and GNU
`tar`/`coreutils`. Use the scripts of a pinned commit, so data versions
match CI:

```sh
ref=<commit-sha>
mkdir -p .fhir-test-data
curl -fsSL "https://github.com/life-research/fhir-test-data/archive/${ref}.tar.gz" \
  | tar -xz --strip-components=1 -C .fhir-test-data
.fhir-test-data/scripts/pull.sh kds test-data/kds 1000
```

```
scripts/pull.sh <set> <path> [patients] [version]
```

Only the layers needed for the requested patient count are downloaded.
After pulling, the patient selection and all checksums are verified.

## Layout

Chunked sets (`kds`, `kds-fhir-consent`) unpack to:

```
<path>/
├── authored.json                 # all patients, in chunk order
└── kds/
    ├── <patient>.json.gz         # first <patients> entries of authored.json
    ├── hospitalInformation.json.gz
    ├── practitionerInformation.json.gz
    └── checksums.sha256          # all patients, check with --ignore-missing
```

Their artifact holds a `base.tar.gz` layer (everything but patients) and one
layer per chunk, e.g. `chunk-00001-00100.tar.gz`, `chunk-00101-01000.tar.gz`
and `chunk-01001-10000.tar.gz` for `kds`. Patient files are assigned to
chunks in `authored.json` order. Single file sets have one layer named after
the file.

Artifacts live at `ghcr.io/life-research/fhir-test-data/<set>:<version>`.
Tags never move once published; the action and `pull.sh` fetch by digest.

## Publishing

Data sets are published manually by a maintainer from a local copy, which is
never tracked by git. Put the copy into `build/<set>/` (or pass `INPUT=<dir>`):
chunked sets in the layout above with all patients, single file sets as that
file. Each set is configured in `datasets/<set>/set.env`.

```sh
gh auth refresh -s write:packages
gh auth token | oras login ghcr.io -u "$(gh api user -q .login)" --password-stdin
make publish SET=kds VERSION=v1 # optionally INPUT=<dir>
```

`publish` runs `pack` (validates the input, writes reproducible layers into
`out/`) and `push`. `pack` fails on missing patients, missing files or
checksum mismatches. `push` refuses versions that are already recorded or
tagged, and appends `<version> <digest>` to `datasets/<set>/digests`. Open a
pull request with that change. After the first publish of a set, make its
package public in the GitHub package settings.

Fine-grained personal access tokens do not support GHCR; use `gh` as above or
a classic token with `write:packages`.

## Development

```sh
docker run -d -p 5000:5000 registry:2 # for the registry round trip tests
make lint test
```

CI (`.github/workflows/verify.yml`) runs lint and tests, runs the action
against fixtures in a local registry, and pulls and verifies every published
version and patient count, also weekly.

## License

Scripts: [Apache-2.0](LICENSE). Data: see the README of each set.
