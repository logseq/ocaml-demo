#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
web_root="$repo_root/web/demo"
resource_root="$repo_root/mobile/Sources/OCamlDemo/Resources/JournalWeb"

npm --prefix "$web_root" run build
mkdir -p "$resource_root"
rsync -a --delete --delete-excluded \
  --exclude='assets/sqlite-*' \
  --exclude='assets/sqlite3-*' \
  "$web_root/site-dist/" \
  "$resource_root/"
