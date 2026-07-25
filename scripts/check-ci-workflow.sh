#!/usr/bin/env bash
set -euo pipefail

repo_root="$(
  if [[ -n "${OCAML_DEMO_REPO_ROOT:-}" ]]; then
    printf '%s\n' "$OCAML_DEMO_REPO_ROOT"
  elif git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s\n' "$git_root"
  else
    cd "$(dirname "${BASH_SOURCE[0]}")/.."
    pwd
  fi
)"
workflow="$repo_root/.github/workflows/ci.yml"
dune_project="$repo_root/dune-project"
ocaml_demo_native_opam="$repo_root/ocaml_demo_native.opam"

require_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  if ! grep -Fq "$needle" "$file"; then
    printf '%s\n' "$message" >&2
    exit 1
  fi
}

reject_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  if grep -Fq "$needle" "$file"; then
    printf '%s\n' "$message" >&2
    exit 1
  fi
}

require_contains \
  "$workflow" \
  "runs-on: macos-15-intel" \
  "CI must run on a pinned macOS runner because ocaml_demo_apple builds stubs that include dispatch/dispatch.h."

reject_contains \
  "$workflow" \
  "runs-on: ubuntu-latest" \
  "CI must not run Apple stub builds on Ubuntu."

reject_contains \
  "$workflow" \
  "runs-on: macos-latest" \
  "CI must not use macos-latest because the backing image can drift under this Apple-specific build."

reject_contains \
  "$workflow" \
  "janestreet-bleeding" \
  "CI must not add Jane Street bleeding repositories because they can select preview dependencies incompatible with fresh macOS runners."

require_contains \
  "$workflow" \
  "brew install pkg-config ripgrep" \
  "CI must install macOS system dependencies used by build and repository tests."

require_contains \
  "$dune_project" \
  "melange" \
  "dune-project must declare melange for libraries built in Melange mode."

require_contains \
  "$ocaml_demo_native_opam" \
  '"melange"' \
  "ocaml_demo_native.opam must declare melange so fresh opam builds provide melc."
