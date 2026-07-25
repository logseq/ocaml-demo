#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

matches="$(
  {
    rg -n --glob 'dune' --glob 'dune-project' --glob '*.opam' \
      '\b(ocaml_demo|ocaml_demo\.driver|core|core_kernel|ppx_jane|ppx_ocaml_demo)\b' .
    rg -n --glob '*.ml' --glob '*.mli' \
      '\bOCamlDemo\b|\bCore\b|open! Core|open Core' .
  } \
    | rg -v '^\./scripts/check-no-ocaml_demo-core-deps\.sh:' \
    | rg -v '^\./test/dune:' \
    | rg -v '^\./(dune-project|[^:]+\.opam):[0-9]+:.*(ocaml-demo|github\.com/.*/ocaml-demo|name ocaml_demo_|name ocaml_demo|public_name ocaml_demo_)' \
    | rg -v '^\./[^:]+:[0-9]+:.*\bOCamlDemo_[a-zA-Z0-9_]+\b' \
    || true
)"

if [[ -n "$matches" ]]; then
  printf '%s\n' "$matches"
  exit 1
fi
