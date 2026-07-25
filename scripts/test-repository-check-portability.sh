#!/usr/bin/env bash

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
portable_bin=$(mktemp -d)
trap '/bin/rm -rf "$portable_bin"' EXIT

for command_name in basename git grep tr; do
  ln -s "$(command -v "$command_name")" "$portable_bin/$command_name"
done

PATH="$portable_bin" /bin/bash "$repo_root/scripts/test-project-naming.sh"
PATH="$portable_bin" /bin/bash "$repo_root/scripts/test-shared-ocaml-architecture.sh"
