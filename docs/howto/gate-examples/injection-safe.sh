#!/usr/bin/env bash
# Proof (R1,R2): external-ish data (a project path) is passed to subprocess/JS via argv, not spliced into
# a shell/JS source string. Uses REAL vectors: a project dir NAMED with `$(touch PWNED)` (evaluated inside
# a double-quoted shell f-string — the doctor.py:130 vector) and a single-quote (the node -e JS-string
# vector). Asserts NO PWNED file and the tools don't break. Prints INJECTION-SAFE-OK. Fails today.
set -u
unset HB_NO_GIT HB_NO_HOOK
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src"
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
fail(){ echo "FAIL: $1"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# (R1) doctor.py: a project path containing $(touch PWNED) must NOT execute it during the rot trace
proj="$tmp/p\$(touch $tmp/PWNED)x"; mkdir -p "$proj"
HB_NO_GIT=1 python3 -m heartbeat.cli init "$proj" >/dev/null 2>&1 || fail "init (crafted path)"
python3 - "$proj/.hb/dag.json" <<'PY'
import json,sys
json.dump({"phases":[{"id":"P0","gate_entry":None,"gate_exit":"GATE_P0","tasks":[{"id":"T1","title":"t"}]}],
"gates":{"GATE_P0":{"desc":"g","criteria":[{"id":"c","desc":"x","cmd":"grep -q X tests/gone.js"}]}}},open(sys.argv[1],"w"))
PY
printf '%s\n' '{"event":"task_done","task":"T1"}' '{"event":"gate_passed","gate":"GATE_P0","pass":1,"fail":0}' >> "$proj/.hb/events.jsonl"
HB_NO_GIT=1 python3 -m heartbeat.cli rebuild --dir "$proj" >/dev/null 2>&1 || true
git -C "$proj" init -q 2>/dev/null || true
HB_NO_GIT=1 python3 -m heartbeat.cli diagnose --dir "$proj" >/dev/null 2>&1 || true
python3 -m heartbeat.cli doctor --dir "$proj" >/dev/null 2>&1 || true
[ ! -f "$tmp/PWNED" ] || fail "doctor executed an injected command via the project path (shell=True f-string)"

# (R2) node -e: a project path containing a single-quote must not break bootstrap/tick/gate node -e — the
# path is passed via argv or process.env everywhere, not spliced into the JS source.
q="$tmp/pa'th"; mkdir -p "$q"
HB_NO_GIT=1 bash "$ROOT/plugin/bootstrap.sh" "$q" >/dev/null 2>&1 || true
node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$q/.hb/state.json" 2>/dev/null   || fail "bootstrap node -e broke on a single-quote in the project path (spliced into JS source, not argv)"

# (R2b) the reviewer's real repro: tick.sh must not emit a FALSE state_corrupted at a quote-path
r="$(cd "$q" && bash .hb/tick.sh 2>/dev/null | node -pe 'try{JSON.parse(require("fs").readFileSync(0,"utf8")).data.reason||""}catch(e){""}')"
[ "$r" != "state_corrupted" ] || fail "tick.sh false state_corrupted at a quote-path (node -e spliced the path into JS source)"
# gate.sh teeth: gate.sh --all at a quote-path must not break its node -e (SyntaxError)
go="$(cd "$q" && bash .hb/gate.sh --all 2>&1 || true)"
printf '%s' "$go" | grep -qi 'SyntaxError' && fail "gate.sh node -e broke on a single-quote path (spliced into JS source)"
echo "INJECTION-SAFE-OK"
