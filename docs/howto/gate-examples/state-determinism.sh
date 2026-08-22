#!/usr/bin/env bash
# Proof (C3): state.json is a DETERMINISTIC projection — two independent rebuilds of the same event log
# produce byte-identical state.json (no list(set()) ordering churn). Python side (hash randomization
# makes set() order vary across processes). Prints STATE-DETERMINISM-OK. Fails today.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src"
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
p="$tmp/proj"; HB_NO_GIT=1 hb init "$p" >/dev/null 2>&1 || fail "init"
# append several task/phase events so the projected sets are non-trivial
for i in 1 2 3 4 5; do printf '%s\n' "{\"event\":\"task_done\",\"task\":\"T$i\"}" >> "$p/.hb/events.jsonl"; done
printf '%s\n' '{"event":"phase_complete","phase":"PB"}' '{"event":"phase_complete","phase":"PA"}' >> "$p/.hb/events.jsonl"
# canon = the projection MINUS last_updated (an acknowledged wall-clock field, state.py:169) — so this
# tests the SET-ORDERING determinism KB3 fixed, deterministically (no timestamp flake).
canon(){ python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d.pop('last_updated',None); print(json.dumps(d,sort_keys=True))" "$1"; }
PYTHONHASHSEED=random hb rebuild --dir "$p" >/dev/null 2>&1; a="$(canon "$p/.hb/state.json")"
PYTHONHASHSEED=random hb rebuild --dir "$p" >/dev/null 2>&1; b="$(canon "$p/.hb/state.json")"
[ -n "$a" ] && [ "$a" = "$b" ] || fail "state projection differs across rebuilds (nondeterministic set ordering): $a vs $b"
echo "STATE-DETERMINISM-OK"
