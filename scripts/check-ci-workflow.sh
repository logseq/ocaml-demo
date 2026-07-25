#!/usr/bin/env bash

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
workflow="$repo_root/.github/workflows/ci.yml"

grep -Fq "opam exec -- dune build @shared-platform-check" "$workflow"
grep -Fq "scripts/test-shared-ocaml-architecture.sh" "$workflow"
grep -Fq "ocaml-compiler: 5.5.0" "$workflow"
