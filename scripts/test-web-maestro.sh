#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
demo_root="$repo_root/web/demo"
host=127.0.0.1
port=${OCAML_DEMO_WEB_TEST_PORT:-4173}
web_url="http://$host:$port"
maestro_bin=${MAESTRO_BIN:-maestro}
server_log=$(mktemp)
server_pid=

cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -f "$server_log"
}
trap cleanup EXIT INT TERM

cd "$demo_root"
npm run build
npm exec -- vite preview --host "$host" --port "$port" --strictPort \
  >"$server_log" 2>&1 &
server_pid=$!

for _ in {1..100}; do
  if curl --fail --silent --output /dev/null "$web_url"; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    cat "$server_log" >&2
    exit 1
  fi
  sleep 0.1
done

if ! curl --fail --silent --output /dev/null "$web_url"; then
  cat "$server_log" >&2
  exit 1
fi

"$maestro_bin" test -e WEB_URL="$web_url" .maestro/10-web.yaml
