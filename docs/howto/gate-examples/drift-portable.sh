#!/usr/bin/env bash
# Proof (C5): drift hashing works when sha256sum is absent (macOS) via a shasum fallback, and is NOT a
# silent no-op — a changed watched file yields a DIFFERENT hash. Prints DRIFT-PORTABLE-OK. Fails today
# (tick.sh only uses sha256sum → empty hash when absent → drift silently disabled). Deterministic.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
fail(){ echo "FAIL: $1"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# clean bin: coreutils + node + a shasum fallback, but NO sha256sum (simulate macOS)
cb="$tmp/bin"; mkdir -p "$cb"
for b in bash find sort xargs cut cat mktemp env dirname printf grep sed head node; do x="$(command -v $b 2>/dev/null)" && ln -sf "$x" "$cb/$b"; done
# provide the real shasum (macOS's hasher) as the fallback; exclude sha256sum to simulate macOS
command -v shasum >/dev/null 2>&1 && ln -sf "$(command -v shasum)" "$cb/shasum" || { echo "shasum absent — cannot simulate the macOS fallback"; exit 1; }
env PATH="$cb" bash -c 'command -v sha256sum' >/dev/null 2>&1 && fail "setup: sha256sum leaked into clean PATH"
# extract compute_watch_hash from the CURRENT tick.sh and run it under the clean PATH with a watched file
wf="$tmp/watched.txt"; echo "one" > "$wf"
hash_of(){ env PATH="$cb" WATCH_PATHS="$wf" bash -c 'source <(sed -n "/^compute_watch_hash()/,/^}/p" "'"$ROOT/plugin/templates/tick.sh"'"); compute_watch_hash'; }
h1="$(hash_of)"; echo "two" > "$wf"; h2="$(hash_of)"
[ -n "$h1" ] || fail "drift hash EMPTY when sha256sum absent (silent no-op — macOS drift disabled)"
[ "$h1" != "$h2" ] || fail "drift hash did not change when a watched file changed"
echo "DRIFT-PORTABLE-OK"
