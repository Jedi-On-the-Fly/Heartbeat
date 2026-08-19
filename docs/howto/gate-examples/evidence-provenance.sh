#!/usr/bin/env bash
# Proof: a gate pass records EVIDENCE PROVENANCE on the gate_passed event — per-criterion {id,cmd,exit},
# the git `commit` tested, and the `runtime` — and `hb evidence <gate>` reads it back. node ≡ python
# (same recorded keys). Prints EVIDENCE-PROVENANCE-OK. Fails before provenance / the `evidence` command
# exist (spec-first).
set -uo pipefail
# needs git enabled even under the suite's HB_NO_GIT=1 default (commit provenance).
unset HB_NO_GIT; export HB_GIT_AUTOCOMMIT=1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
command -v git  >/dev/null 2>&1 || { echo "git absent"; exit 1; }

DAG='{ "phases":[{"id":"P0","title":"p","gate_entry":null,"gate_exit":"GATE_X","tasks":[{"id":"T0","requires":[]}]}],
  "gates":{"GATE_X":{"desc":"works","criteria":[{"id":"c1","desc":"a","cmd":"true"},{"id":"c2","desc":"b","cmd":"test 1 = 1"}]}} }'

# assert the latest gate_passed for GATE_X in <events file> carries the provenance keys
check_event() {
  node -e '
    const fs=require("fs");
    const evs=fs.readFileSync(process.argv[1],"utf8").trim().split("\n").filter(Boolean).map(JSON.parse);
    const gp=[...evs].reverse().find(e=>e.event==="gate_passed"&&e.gate==="GATE_X");
    if(!gp){console.error("no gate_passed event");process.exit(1);}
    if(!Array.isArray(gp.criteria)||gp.criteria.length<2){console.error("no criteria[] provenance",gp);process.exit(1);}
    const c=gp.criteria[0];
    if(!("id" in c)||!("cmd" in c)||!("exit" in c)){console.error("criterion missing id/cmd/exit",c);process.exit(1);}
    if(!("commit" in gp)){console.error("no commit key",gp);process.exit(1);}
    if(!("runtime" in gp)){console.error("no runtime key",gp);process.exit(1);}
  ' "$1"
}

# ---------- node ----------
tn="$(mktemp -d)"; trap 'rm -rf "$tn" "${tp:-}"' EXIT
bash "$ROOT/plugin/bootstrap.sh" "$tn/p" >/dev/null 2>&1 </dev/null
printf '%s' "$DAG" > "$tn/p/.hb/dag.json"
bash "$tn/p/.hb/gate.sh" GATE_X >/dev/null 2>&1 || { echo "FAIL(node): gate.sh GATE_X errored"; exit 1; }
check_event "$tn/p/.hb/events.jsonl" || { echo "FAIL(node): gate_passed lacks provenance"; exit 1; }
ev="$(node "$tn/p/.hb/hb.js" evidence GATE_X 2>&1)" || { echo "FAIL(node): hb evidence errored"; exit 1; }
printf '%s' "$ev" | grep -q 'true'         || { echo "FAIL(node): evidence did not show a criterion cmd"; echo "$ev"; exit 1; }
printf '%s' "$ev" | grep -qiE 'commit'     || { echo "FAIL(node): evidence did not show the commit"; echo "$ev"; exit 1; }

# ---------- python ----------
if command -v python3 >/dev/null 2>&1; then
  tp="$(mktemp -d)"
  PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli init "$tp/p" >/dev/null 2>&1
  printf '%s' "$DAG" > "$tp/p/.hb/dag.json"
  git -C "$tp/p" rev-parse --is-inside-work-tree >/dev/null 2>&1 || git -C "$tp/p" init -q
  PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli gate GATE_X --dir "$tp/p" >/dev/null 2>&1
  check_event "$tp/p/.hb/events.jsonl" || { echo "FAIL(py): gate_passed lacks provenance (shape != node)"; exit 1; }
  PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli evidence GATE_X --dir "$tp/p" 2>&1 | grep -q 'true' \
    || { echo "FAIL(py): hb evidence reader"; exit 1; }
fi

echo "EVIDENCE-PROVENANCE-OK"
