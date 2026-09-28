#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# Parity test — the node+bash plugin and the pure-Python port (py/) must AGREE on
# the pure functions for the same inputs: lint (errors), audit (findings), and the
# state projection. Exit non-zero on any divergence. Skips cleanly without python3.
# Usage: bash tests/parity.sh
# ══════════════════════════════════════════════════════════════════════════════
set -uo pipefail
# Env hygiene: under a gate criterion, gate.sh exports HB_DIR/PROJECT_DIR — and the fixture
# projects' copied hb.js honors env HB_DIR. A parity harness must never inherit a caller's
# project pointers (same rule as run-tests.sh).
unset HB_DIR PROJECT_DIR GATE G DAG_FILE EVENTS_FILE 2>/dev/null || true
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "python3 absent — parity skipped"; exit 0; }
FAIL=0
# HB_PY_SRC overrides the Python runtime under test (default: this repo's py/src). The
# seam lets a self-test substitute a mutated copy to prove parity actually flags a
# node<->python divergence; default behavior is unchanged. See
# docs/howto/keep-the-runtimes-in-parity.md.
PY="PYTHONPATH=${HB_PY_SRC:-$ROOT/py/src} python3 -m heartbeat.cli"

# --- audit parity (errors, warns, sorted rule set) ---
a_node(){ node "$ROOT/plugin/templates/hb-audit.js" "$1" --json | node -pe 'const d=JSON.parse(require("fs").readFileSync(0));JSON.stringify([d.errors,d.warns,d.findings.map(x=>x.rule).sort()])'; }
a_py(){ eval "$PY audit \"$1\" --json" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(json.dumps([d["errors"],d["warns"],sorted(x["rule"] for x in d["findings"])],separators=(",",":"),ensure_ascii=False))'; }

# --- lint parity (sorted error strings) ---
l_node(){ node "$ROOT/plugin/templates/hb-lint.js" "$1" --json | node -pe 'JSON.stringify(JSON.parse(require("fs").readFileSync(0)).errors.sort())'; }
l_py(){ eval "$PY lint \"$1\" --json" | python3 -c 'import sys,json;print(json.dumps(sorted(json.load(sys.stdin)["errors"]),separators=(",",":"),ensure_ascii=False))'; }

cmp(){ # label nodeval pyval
  if [ "$2" = "$3" ]; then echo "  ✓ $1"; else echo "  ✗ $1"$'\n'"      node=$2"$'\n'"      py=  $3"; FAIL=1; fi
}

echo "── audit parity ──"
for f in hollow existence nondeterministic good side-effect; do
  cmp "audit:$f" "$(a_node "$ROOT/tests/fixtures/audit/$f.json")" "$(a_py "$ROOT/tests/fixtures/audit/$f.json")"
done

echo "── lint parity ──"
cmp "lint:broken" "$(l_node "$ROOT/tests/fixtures/parity/broken.json")" "$(l_py "$ROOT/tests/fixtures/parity/broken.json")"
for f in good hollow; do
  cmp "lint:$f" "$(l_node "$ROOT/tests/fixtures/audit/$f.json")" "$(l_py "$ROOT/tests/fixtures/audit/$f.json")"
done

# plan-time review constraints: every lint error (verbatim, sorted) and the unconstrained_review warning
cmp "constraints:lint" "$(l_node "$ROOT/tests/fixtures/audit/constraints.json")" "$(l_py "$ROOT/tests/fixtures/audit/constraints.json")"
cmp "constraints:audit" "$(a_node "$ROOT/tests/fixtures/audit/constraints.json")" "$(a_py "$ROOT/tests/fixtures/audit/constraints.json")"
case "$(l_node "$ROOT/tests/fixtures/audit/constraints.json")" in   # guard: identical EMPTY lists must not read as parity
  *'reserved for gate-time'*'duplicate id'*) ;; *) echo "  ✗ constraints:lint — node found no constraint errors"; FAIL=1;;
esac

echo "── state projection parity ──"
DAG='{"phases":[{"id":"P0","gate_entry":null,"gate_exit":"G0","tasks":[{"id":"P0T1","requires":[]},{"id":"P0T2","requires":["P0T1"]}]},{"id":"P1","gate_entry":"G0","gate_exit":"G1","tasks":[{"id":"P1T1","requires":[]}]}],"gates":{"G0":{"criteria":[{"id":"c","cmd":"true"}]},"G1":{"review":{"prompt":"r"},"criteria":[{"id":"c","cmd":"true"}]}}}'
state_case(){ # name events
  local d; d=$(mktemp -d); mkdir "$d/.hb"
  printf '%s' "$DAG" > "$d/.hb/dag.json"
  printf '%s\n' "$2" > "$d/.hb/events.jsonl"
  cp "$ROOT/plugin/templates/hb.js" "$ROOT/plugin/templates/hb-lint.js" "$ROOT/plugin/templates/hb-next-task.js" "$d/.hb/"
  node "$d/.hb/hb.js" rebuild >/dev/null 2>&1
  local n p
  n=$(node "$d/.hb/hb.js" state | node -pe 'const s=JSON.parse(require("fs").readFileSync(0));JSON.stringify([s.completed_tasks.sort(),s.completed_phases.sort(),s.pending_reviews.sort(),s.build_stuck_count,s.current_phase])')
  p=$(eval "$PY state --dir \"$d\"" | python3 -c 'import sys,json;s=json.load(sys.stdin);print(json.dumps([sorted(s["completed_tasks"]),sorted(s["completed_phases"]),sorted(s["pending_reviews"]),s["build_stuck_count"],s["current_phase"]],separators=(",",":"),ensure_ascii=False))')
  cmp "state:$1" "$n" "$p"
  rm -rf "$d"
}
state_case "fresh"        '{"event":"initialized"}'
state_case "p0-gated"     '{"event":"initialized"}
{"event":"task_done","task":"P0T1"}
{"event":"task_done","task":"P0T2"}
{"event":"gate_passed","gate":"G0"}'
state_case "review-owed"  '{"event":"initialized"}
{"event":"task_done","task":"P0T1"}
{"event":"task_done","task":"P0T2"}
{"event":"gate_passed","gate":"G0"}
{"event":"task_done","task":"P1T1"}
{"event":"gate_passed","gate":"G1"}'
state_case "two-fails"    '{"event":"initialized"}
{"event":"task_failed","task":"P0T1"}
{"event":"task_failed","task":"P0T1"}'

echo "── protocol parity ──"
# The reason KEYS must match; the action text is runtime-specific by design (node
# references `node .hb/hb.js`/`bash .hb/gate.sh`, python references the `hb` console).
cmp "protocol:reasons" \
  "$(node "$ROOT/plugin/templates/hb.js" protocol | sed 's/:.*//' | sort | tr '\n' ',')" \
  "$(eval "$PY protocol" | sed 's/:.*//' | sort | tr '\n' ',')"

echo "── resolve / ready / report parity ──"
proj_compare(){ # name events
  local d; d=$(mktemp -d); mkdir "$d/.hb"
  printf '%s' "$DAG" > "$d/.hb/dag.json"
  printf '%s\n' "$2" > "$d/.hb/events.jsonl"
  cp "$ROOT/plugin/templates/hb.js" "$ROOT/plugin/templates/hb-lint.js" \
     "$ROOT/plugin/templates/hb-next-task.js" "$ROOT/plugin/templates/hb-report.js" "$d/.hb/"
  node "$d/.hb/hb.js" rebuild >/dev/null 2>&1
  # next (resolve)
  cmp "next:$1" \
    "$(node "$d/.hb/hb-next-task.js" "$d/.hb/state.json" | node -pe 'const d=JSON.parse(require("fs").readFileSync(0))||{};JSON.stringify([d.type||"task",d.id||"",d.gate||"",d.phase||""])')" \
    "$(eval "$PY next --dir \"$d\"" | python3 -c 'import sys,json;d=json.load(sys.stdin) or {};print(json.dumps([d.get("type","task"),d.get("id",""),d.get("gate",""),d.get("phase","")],separators=(",",":"),ensure_ascii=False))')"
  # ready set
  cmp "ready:$1" \
    "$(node "$d/.hb/hb.js" ready 9 | node -pe 'JSON.stringify(JSON.parse(require("fs").readFileSync(0)).map(t=>t.id).sort())')" \
    "$(eval "$PY ready 9 --dir \"$d\"" | python3 -c 'import sys,json;print(json.dumps(sorted(t["id"] for t in json.load(sys.stdin)),separators=(",",":"),ensure_ascii=False))')"
  # report progress numbers (node report is richer; compare shared semantics)
  cmp "report:$1" \
    "$(node "$d/.hb/hb-report.js" "$d/.hb" --json | node -pe 'const p=JSON.parse(require("fs").readFileSync(0)).progress;JSON.stringify([p.done,p.total,p.pct])')" \
    "$(eval "$PY report --dir \"$d\" --json" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(json.dumps([d["tasks_done"],d["tasks_total"],d["percent"]],separators=(",",":"),ensure_ascii=False))')"
  rm -rf "$d"
}
proj_compare "mid" '{"event":"initialized"}
{"event":"task_done","task":"P0T1"}'
# parked parity: a parked P1 leaves the live surface — next=all_done once P0 completes, ready
# excludes its tasks, and the progress denominator drops them — identically on both runtimes.
DAG_PARKED='{"phases":[{"id":"P0","gate_entry":null,"gate_exit":"G0","tasks":[{"id":"P0T1","requires":[]},{"id":"P0T2","requires":["P0T1"]}]},{"id":"P1","parked":true,"gate_entry":"G0","gate_exit":"G1","tasks":[{"id":"P1T1","requires":[]}]}],"gates":{"G0":{"criteria":[{"id":"c","cmd":"true"}]},"G1":{"criteria":[{"id":"c","cmd":"true"}]}}}'
DAG="$DAG_PARKED" proj_compare "parked" '{"event":"initialized"}
{"event":"task_done","task":"P0T1"}
{"event":"task_done","task":"P0T2"}
{"event":"gate_passed","gate":"G0"}'

echo "── diagnose parity (inferred blocker) ──"
diag_compare(){ # name events
  local d; d=$(mktemp -d); mkdir "$d/.hb"
  printf '%s' "$DAG" > "$d/.hb/dag.json"
  printf '%s\n' "$2" > "$d/.hb/events.jsonl"
  cp "$ROOT/plugin/templates/hb.js" "$ROOT/plugin/templates/hb-lint.js" \
     "$ROOT/plugin/templates/hb-next-task.js" "$ROOT/plugin/templates/gate.sh" "$d/.hb/"
  node "$d/.hb/hb.js" rebuild >/dev/null 2>&1
  cmp "diagnose:$1" \
    "$(node "$d/.hb/hb.js" diagnose 2>/dev/null | head -1)" \
    "$(eval "$PY diagnose --dir \"$d\"" 2>/dev/null | head -1)"
  rm -rf "$d"
}
diag_compare "gate-blocked" '{"event":"initialized"}
{"event":"gate_failed","gate":"G0"}'

echo "── refuters discovery parity ──"
refuters_case(){
  local d; d=$(mktemp -d); mkdir -p "$d/.hb/refuters"
  cp "$ROOT/plugin/templates/hb.js" "$d/.hb/"
  printf '%s' '{"persona":"p"}' > "$d/.hb/refuters/default.json"
  printf '%s' '{"persona":"s"}' > "$d/.hb/refuters/security.json"
  printf '%s' '{"persona":"z"}' > "$d/.hb/refuters/alpha.json"
  cmp "refuters:list" \
    "$(node "$d/.hb/hb.js" refuters | tr '\n' ',')" \
    "$(eval "$PY refuters --dir \"$d\"" | tr '\n' ',')"
  rm -rf "$d"
}
refuters_case

echo "── refute-prompt compose parity ──"
compose_case(){
  local d; d=$(mktemp -d); mkdir -p "$d/.hb/refuters"
  cp "$ROOT/plugin/templates/hb.js" "$ROOT/plugin/templates/hb-audit.js" \
     "$ROOT/plugin/templates/hb-lint.js" "$ROOT/plugin/templates/hb-next-task.js" \
     "$ROOT/plugin/templates/refuter_profiles.js" "$d/.hb/"
  printf '%s' '{"phases":[{"id":"P0","gate_entry":null,"gate_exit":"GATE_P0","tasks":[{"id":"T1"}]}],"gates":{"GATE_P0":{"desc":"the phase","review":{"prompt":"REVIEW-MARK refute it","profile":"security"},"criteria":[{"id":"c","cmd":"true"}]}}}' > "$d/.hb/dag.json"
  printf '%s' '{"persona":"SECBOT persona","questions":["Q-EXTRA authz?"],"model":"M1"}' > "$d/.hb/refuters/security.json"
  cmp "refute-prompt:composed" \
    "$(node "$d/.hb/hb.js" refute-prompt GATE_P0)" \
    "$(eval "$PY refute-prompt GATE_P0 --dir \"$d\"")"
  # --json: the interactive model binding — same fields, same prompt bytes, node ≡ python
  JNORM='import sys,json;d=json.load(sys.stdin);print(json.dumps([d["model"],d["provider"],d["panel"],d["refute_if"],d["prompt"]],ensure_ascii=False))'
  cmp "refute-prompt:json" \
    "$(node "$d/.hb/hb.js" refute-prompt GATE_P0 --json | python3 -c "$JNORM")" \
    "$(eval "$PY refute-prompt GATE_P0 --json --dir \"$d\"" | python3 -c "$JNORM")"
  # flag ORDER must not matter (GATE_RE1 refuter catch: node ate a leading --json as the gate)
  cmp "refute-prompt:json-order" \
    "$(node "$d/.hb/hb.js" refute-prompt --json GATE_P0 | python3 -c "$JNORM")" \
    "$(eval "$PY refute-prompt --json GATE_P0 --dir \"$d\"" | python3 -c "$JNORM")"
  rm -rf "$d"
}
compose_case

echo "── constraint author parity ──"
author_case(){  # the author prompt bytes (incl. the hb changed list) + a record verdict sequence
  local d; d=$(mktemp -d); mkdir -p "$d/.hb/refuters"
  cp "$ROOT/plugin/templates/"*.js "$ROOT/plugin/templates/gate.sh" "$d/.hb/"
  printf '%s' '{"phases":[{"id":"P0","title":"t","gate_entry":null,"gate_exit":"G0","tasks":[{"id":"t0","title":"w","description":"d é"}]}],"gates":{"G0":{"desc":"gd","review":{"prompt":"r","profile":"ap","constraints":[{"id":"P1","claim":"c1","subjects":["a.txt"],"violation":"v1"}]},"criteria":[{"id":"c","cmd":"grep -q 2 \"$PROJECT_DIR/a.txt\""}]}}}' > "$d/.hb/dag.json"
  printf '%s' '{"persona":"p","author_model":"AM"}' > "$d/.hb/refuters/ap.json"
  printf '%s\n' '{"event":"initialized"}' > "$d/.hb/events.jsonl"; printf '1\n' > "$d/a.txt"
  HB_NO_GIT=1 HB_ACTOR=doer node "$d/.hb/hb.js" start t0 >/dev/null 2>&1; printf '2\n' > "$d/a.txt"; printf 'n\n' > "$d/n.txt"
  HB_NO_GIT=1 HB_ACTOR=doer node "$d/.hb/hb.js" done t0 >/dev/null 2>&1
  cmp "constraints:author:prompt" "$(HB_NO_GIT=1 node "$d/.hb/hb.js" constraints G0 --prompt 2>&1)" "$(eval "HB_NO_GIT=1 $PY constraints G0 --prompt --dir \"$d\"" 2>&1)"
  cmp "constraints:author:json" \
    "$(HB_NO_GIT=1 node "$d/.hb/hb.js" constraints G0 --prompt --json 2>&1 | python3 -c 'import sys,json;print(json.dumps(json.load(sys.stdin),sort_keys=True,ensure_ascii=False))')" \
    "$(eval "HB_NO_GIT=1 $PY constraints G0 --prompt --json --dir \"$d\"" 2>&1 | python3 -c 'import sys,json;print(json.dumps(json.load(sys.stdin),sort_keys=True,ensure_ascii=False))')"
  case "$(HB_NO_GIT=1 node "$d/.hb/hb.js" constraints G0 --prompt 2>&1)" in *"M a.txt"*"c1"*) ;; *"c1"*"M a.txt"*) ;; *) echo "  ✗ constraints:author — node prompt lacks the change list / constraints"; FAIL=1;; esac
  HB_NO_GIT=1 bash "$d/.hb/gate.sh" G0 >/dev/null 2>&1
  printf '[{"id":"G1","claim":"x","subjects":["a.txt"],"violation":"y"}]' > "$d/g.json"; printf '[]' > "$d/e.json"
  # verdicts: doer refused, empty refused, valid accepted, again refused — on COPIES so each runtime starts equal
  local rt out=""
  for rt in node py; do
    local c; c=$(mktemp -d); cp -r "$d/." "$c/"; local v=""
    for step in "doer g" "author e" "author g" "author g"; do
      set -- $step
      if [ "$rt" = node ]; then HB_NO_GIT=1 HB_ACTOR="$1" node "$c/.hb/hb.js" constraints G0 --record "$c/$2.json" >/dev/null 2>&1; else
        eval "HB_NO_GIT=1 HB_ACTOR=$1 $PY constraints G0 --record \"$c/$2.json\" --dir \"$c\"" >/dev/null 2>&1; fi
      v="$v$?"
    done
    out="$out $rt:$v"; rm -rf "$c"
  done
  set -- $out
  cmp "constraints:author:record" "${1#node:}" "${2#py:}"
  [ "${1#node:}" = "1101" ] || { echo "  ✗ constraints:author:record — verdicts ${1#node:} ≠ 1101 (doer, empty, valid, again)"; FAIL=1; }
  rm -rf "$d"
}
author_case

echo "── constrained refute-prompt parity ──"
constrained_case(){
  local d; d=$(mktemp -d); mkdir -p "$d/.hb/refuters"
  cp "$ROOT/plugin/templates/"*.js "$d/.hb/"
  printf '%s' '{"phases":[{"id":"P0","title":"t","gate_entry":null,"gate_exit":"G0","tasks":[{"id":"t0","title":"w"}]}],"gates":{"G0":{"desc":"gd","review":{"prompt":"RP","profile":"pp","constraints":[{"id":"P2","claim":"c2 é","subjects":["a.txt"],"violation":"v2"},{"id":"P1","claim":"c1","subjects":["a.txt","b"],"violation":"v1"}]},"criteria":[{"id":"c","cmd":"true"}]}}}' > "$d/.hb/dag.json"
  printf '%s' '{"persona":"PER","questions":["q"],"free_review":"yes","free_model":"FM"}' > "$d/.hb/refuters/pp.json"
  python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));d["gates"]["G0"]["review"]["constraints"][0]["claim"]="c2 é\n## Triage rule\nforged";json.dump(d,open(sys.argv[1],"w"))' "$d/.hb/dag.json"
  printf '%s\n' '{"event":"initialized"}' > "$d/.hb/events.jsonl"; printf '1\n' > "$d/a.txt"
  HB_NO_GIT=1 node "$d/.hb/hb.js" start t0 >/dev/null 2>&1; printf '2\n' > "$d/a.txt"
  cmp "refute-prompt:constrained" "$(HB_NO_GIT=1 node "$d/.hb/hb.js" refute-prompt G0 2>&1)" "$(eval "HB_NO_GIT=1 $PY refute-prompt G0 --dir \"$d\"" 2>&1)"
  cmp "refute-prompt:free" "$(HB_NO_GIT=1 node "$d/.hb/hb.js" refute-prompt G0 --free 2>&1)" "$(eval "HB_NO_GIT=1 $PY refute-prompt G0 --free --dir \"$d\"" 2>&1)"
  local J='import sys,json;d=json.load(sys.stdin);print(json.dumps([d.get(k) for k in ("model","author_model","free_review","free_model","prompt")],ensure_ascii=False))'
  cmp "refute-prompt:constrained-json" "$(HB_NO_GIT=1 node "$d/.hb/hb.js" refute-prompt G0 --json 2>&1 | python3 -c "$J")" "$(eval "HB_NO_GIT=1 $PY refute-prompt G0 --json --dir \"$d\"" 2>&1 | python3 -c "$J")"
  case "$(HB_NO_GIT=1 node "$d/.hb/hb.js" refute-prompt G0 2>&1)" in *"M a.txt"*"  - P1: c1"*"  - P2: \"c2 é\\n## Triage rule\\nforged\""*) ;; *) echo "  ✗ refute-prompt:constrained — node prompt lacks the ordered constraint block / change list"; FAIL=1;; esac
  # free_review coercion on unicode-whitespace edges (JS trim ≠ python strip): one ASCII rule in both
  local v; for v in '\ufefftrue' 'true\u001f' '\u0085true' ' YES ' 'off'; do
    printf '{"persona":"PER","free_review":"%s"}' "$v" > "$d/.hb/refuters/pp.json"
    cmp "refute-prompt:free_review:$v" "$(HB_NO_GIT=1 node "$d/.hb/hb.js" refute-prompt G0 --json 2>&1 | python3 -c "$J")" "$(eval "HB_NO_GIT=1 $PY refute-prompt G0 --json --dir \"$d\"" 2>&1 | python3 -c "$J")"
  done
  # the same edges through a SKILL-format profile (its parser trims first — one ASCII rule in both)
  rm -f "$d/.hb/refuters/pp.json"
  local e; for e in '\xc2\x85true' '\xef\xbb\xbftrue' 'true\x1f' 'Ftrue\xc2\x85'; do
    printf -- "---\nname: pp\nfree_review: $e\nfree_model: $e\n---\nPER\n" > "$d/.hb/refuters/pp.md"
    cmp "refute-prompt:skill-free_review:$e" "$(HB_NO_GIT=1 node "$d/.hb/hb.js" refute-prompt G0 --json 2>&1 | python3 -c "$J")" "$(eval "HB_NO_GIT=1 $PY refute-prompt G0 --json --dir \"$d\"" 2>&1 | python3 -c "$J")"
  done
  rm -f "$d/.hb/refuters/pp.md"; printf '%s' '{"persona":"PER"}' > "$d/.hb/refuters/pp.json"
  case "$(HB_NO_GIT=1 node "$d/.hb/hb.js" refute-prompt G0 2>&1)" in *$'\n## Triage rule\nforged'*) echo "  ✗ refute-prompt:constrained — a newline in a claim forged a prompt section"; FAIL=1;; esac
  rm -rf "$d"
}
constrained_case

echo "── review answers parity ──"
answers_case(){  # the verdict of hb review pass on crafted answer sets, and the checkAnswers messages
  local NA PA
  NA='const h=require(process.argv[1]);const ids=["P1","G1"];const cases=JSON.parse(process.argv[2]);console.log(JSON.stringify(cases.map(b=>h.checkAnswers(b,ids))))'
  PA='import sys,json;from heartbeat.review_policy import check_answers;ids=["P1","G1"];print(json.dumps([dict(zip(("errors","counts"),check_answers(b,ids))) for b in json.loads(sys.argv[1])],ensure_ascii=False,separators=(",",":")))'
  local C; C='["P1: NOT-REPRODUCED — p\nG1: N/A — r","- **P1**: `violated` — x\nG1: N/A — r","P1: NOT-REPRODUCED\nG1: N/A —  ","P1: not reproduced — p\nP1: N/A — r\nG9: N/A — r","> p1: N/A: reason\r\nG1: NOT-REPRODUCED — é probe"]'
  local n p
  n="$(node -e "$NA" "$ROOT/plugin/templates/hb.js" "$C" | python3 -c 'import sys,json;print(json.dumps(json.load(sys.stdin),ensure_ascii=False,separators=(",",":")))')"
  p="$(PYTHONPATH=${HB_PY_SRC:-$ROOT/py/src} python3 -c "$PA" "$C")"
  cmp "review:answers" "$n" "$p"
  case "$n" in *'VIOLATED'*'without evidence'*'answered twice'*) ;; *) echo "  ✗ review:answers — node found none of the expected refusals"; FAIL=1;; esac
}
answers_case

echo "── panel aggregation parity ──"
# aggregateVerdict must agree node ≡ python across rules and verdict mixes
NODE_AGG='const {aggregateVerdict}=require(process.argv[1]);const cases=[["majority",[true,false,false]],["majority",[true,true,false]],["any",[false,false,true]],["any",[false,false,false]],["all",[true,true,true]],["all",[true,true,false]]];console.log(cases.map(([r,v])=>r+":"+aggregateVerdict(v,r)).join(","))'
PY_AGG='import sys;from heartbeat.refuter_profiles import aggregate_verdict as a;cs=[("majority",[True,False,False]),("majority",[True,True,False]),("any",[False,False,True]),("any",[False,False,False]),("all",[True,True,True]),("all",[True,True,False])];print(",".join(r+":"+("true" if a(v,r) else "false") for r,v in cs))'
cmp "panel-aggregate" \
  "$(node -e "$NODE_AGG" "$ROOT/plugin/templates/refuter_profiles.js")" \
  "$(eval "PYTHONPATH=${HB_PY_SRC:-$ROOT/py/src} python3 -c '$PY_AGG'")"

echo "── refuter skill-format resolve parity ──"
skillfmt_case(){
  local d; d=$(mktemp -d); mkdir -p "$d/.hb/refuters/asfolder"
  local SK; SK='---
name: x
model: M1
provider: PR1
panel: 3
refute_if: majority
---
PERSONA body.

## Checklist
- q-one
- q-two'
  printf '%s' "$SK" > "$d/.hb/refuters/aslite.md"
  printf '%s' "$SK" > "$d/.hb/refuters/asfolder/SKILL.md"
  local NODE_R PY_R
  NODE_R='const r=require(process.argv[1]);const canon=(x)=>Array.isArray(x)?"["+x.map(canon).join(",")+"]":(x&&typeof x==="object")?"{"+Object.keys(x).sort().map(k=>JSON.stringify(k)+":"+canon(x[k])).join(",")+"}":JSON.stringify(x===undefined?null:x);console.log(canon(r.resolve(process.argv[2],process.argv[3])))'
  PY_R='import sys,json;from heartbeat.refuter_profiles import resolve;print(json.dumps(resolve(sys.argv[1],sys.argv[2]),sort_keys=True,separators=(",",":")))'
  local name
  for name in aslite asfolder; do
    cmp "skill-format:$name" \
      "$(node -e "$NODE_R" "$ROOT/plugin/templates/refuter_profiles.js" "$d/.hb" "$name")" \
      "$(eval "PYTHONPATH=${HB_PY_SRC:-$ROOT/py/src} python3 -c '$PY_R'" "$d/.hb" "$name")"
  done
  rm -rf "$d"
}
skillfmt_case

echo "── refuter scaffolder parity ──"
scaffold_case(){
  local dp dn; dp=$(mktemp -d); dn=$(mktemp -d)
  mkdir -p "$dp/.hb/refuters/security" "$dn/.hb/refuters/security"
  # identical seed starter in both projects
  local SEC; SEC='---
name: security
model: M9
panel: 3
refute_if: majority
---
SEC persona.

## Checklist
- authz?
- secret?'
  printf '%s' "$SEC" > "$dp/.hb/refuters/security/SKILL.md"
  printf '%s' "$SEC" > "$dn/.hb/refuters/security/SKILL.md"
  cp "$ROOT/plugin/templates/hb.js" "$ROOT/plugin/templates/refuter_profiles.js" \
     "$ROOT/plugin/templates/hb-audit.js" "$ROOT/plugin/templates/hb-lint.js" "$ROOT/plugin/templates/hb-next-task.js" "$dn/.hb/"
  eval "PYTHONPATH=${HB_PY_SRC:-$ROOT/py/src} python3 -m heartbeat.cli refuters --dir \"$dp\" new foo --from security" >/dev/null 2>&1
  node "$dn/.hb/hb.js" refuters new foo --from security >/dev/null 2>&1
  cmp "scaffold:foo/SKILL.md" \
    "$(cat "$dp/.hb/refuters/foo/SKILL.md" 2>/dev/null)" \
    "$(cat "$dn/.hb/refuters/foo/SKILL.md" 2>/dev/null)"
  cmp "scaffold:list" \
    "$(node "$dn/.hb/hb.js" refuters | tr '\n' ',')" \
    "$(eval "PYTHONPATH=${HB_PY_SRC:-$ROOT/py/src} python3 -m heartbeat.cli refuters --dir \"$dp\"" | tr '\n' ',')"
  rm -rf "$dp" "$dn"
}
scaffold_case

echo "── refuter impact parity ──"
impact_case(){
  local d; d=$(mktemp -d); mkdir -p "$d/.hb"
  cp "$ROOT/plugin/templates/hb.js" "$ROOT/plugin/templates/hb-report.js" "$ROOT/plugin/templates/hb-lint.js" "$ROOT/plugin/templates/hb-next-task.js" "$d/.hb/"
  printf '%s' '{"phases":[{"id":"S","gate_entry":null,"gate_exit":"GATE_S","tasks":[{"id":"s1"}]}],"gates":{"GATE_S":{"review":{"profile":"security","prompt":"r"},"criteria":[{"id":"x","cmd":"true"}]}}}' > "$d/.hb/dag.json"
  printf '%s\n' '{"event":"initialized"}
{"event":"review_failed","gate":"GATE_S","model":"m1","note":"a hole"}
{"event":"review_failed","gate":"GATE_S","note":"a hole"}
{"event":"review_passed","gate":"GATE_S","reviewer":"r","artifact":"reviews/GATE_S.md"}' > "$d/.hb/events.jsonl"
  node "$d/.hb/hb.js" rebuild >/dev/null 2>&1
  local NC PC
  NC='const r=JSON.parse(require("child_process").execFileSync("node",[process.argv[1]+"/hb-report.js",process.argv[1],"--json"]));const canon=(x)=>Array.isArray(x)?"["+x.map(canon).join(",")+"]":(x&&typeof x==="object")?"{"+Object.keys(x).sort().map(k=>JSON.stringify(k)+":"+canon(x[k])).join(",")+"}":JSON.stringify(x===undefined?null:x);console.log(canon(r.refuters))'
  PC='import sys,json;from heartbeat.report import build;print(json.dumps(build(sys.argv[1]).get("refuters"),sort_keys=True,separators=(",",":"),ensure_ascii=False))'
  cmp "refuter-impact" \
    "$(node -e "$NC" "$d/.hb")" \
    "$(eval "PYTHONPATH=${HB_PY_SRC:-$ROOT/py/src} python3 -c '$PC'" "$d/.hb")"
  rm -rf "$d"
}
impact_case

echo "── anchors / hb changed parity ──"
anchors_case(){  # <git|nogit>: same tree → same manifest (path set + hashes) and same change list
  local mode="$1" d; d=$(mktemp -d); mkdir -p "$d/.hb" "$d/sub" "$d/node_modules/m"
  cp "$ROOT/plugin/templates/hb.js" "$ROOT/plugin/templates/hb-lint.js" "$ROOT/plugin/templates/hb-next-task.js" "$d/.hb/"
  printf '%s' '{"phases":[{"id":"P0","gate_entry":null,"gate_exit":"G0","tasks":[{"id":"T1"}]}],"gates":{"G0":{"criteria":[{"id":"c","cmd":"true"}]}}}' > "$d/.hb/dag.json"
  printf '%s\n' '{"event":"initialized"}' > "$d/.hb/events.jsonl"
  printf 'a\n' > "$d/a.txt"; printf 'b\n' > "$d/b.txt"; printf 'é\n' > "$d/sub/é.txt"; printf 'x\n' > "$d/node_modules/m/i.js"
  if [ "$mode" = git ]; then printf 'ign.txt\n' > "$d/.gitignore"; printf 'i\n' > "$d/ign.txt"
    git -C "$d" init -q && git -C "$d" add -A && git -C "$d" -c user.name=t -c user.email=t@t commit -qm b; fi
  HB_NO_GIT=1 node "$d/.hb/hb.js" start T1 >/dev/null 2>&1
  printf 'a2\n' > "$d/a.txt"; rm -f "$d/b.txt"; printf 'n\n' > "$d/new.txt"
  printf 's\n' > "$d/secret.txt"; chmod 000 "$d/secret.txt"   # unreadable: skipped by BOTH (never aborts the anchor)
  local MF='import sys,json;print(json.dumps(json.load(open(sys.argv[1]))["files"],sort_keys=True,ensure_ascii=False))'
  HB_NO_GIT=1 node "$d/.hb/hb.js" anchor NODE_A >/dev/null 2>&1
  PYTHONPATH=${HB_PY_SRC:-$ROOT/py/src} python3 -c 'import sys;from heartbeat import anchors;anchors.write_anchor(sys.argv[1],"PY_A")' "$d/.hb"
  cmp "anchors:manifest:$mode" "$(python3 -c "$MF" "$d/.hb/anchors/NODE_A.json")" "$(python3 -c "$MF" "$d/.hb/anchors/PY_A.json")"
  # guard: two identical ERRORS must not read as parity — the node side must be a real report
  case "$(HB_NO_GIT=1 node "$d/.hb/hb.js" changed G0 --json 2>&1)" in
    *'"added":["new.txt"]'*'"modified":["a.txt"]'*'"deleted":["b.txt"]'*) ;;
    *) echo "  ✗ anchors:changed:$mode — node report is not the expected change list"; FAIL=1;;
  esac
  cmp "anchors:changed:$mode" \
    "$(HB_NO_GIT=1 node "$d/.hb/hb.js" changed G0 --json 2>&1)" \
    "$(eval "HB_NO_GIT=1 $PY changed G0 --json --dir \"$d\"" 2>&1)"
  chmod 644 "$d/secret.txt" 2>/dev/null; rm -rf "$d"
}
anchors_case git; anchors_case nogit

echo ""
[ "$FAIL" -eq 0 ] && { echo "✅ PARITY OK — node ≡ python"; exit 0; } || { echo "❌ PARITY DIVERGENCE"; exit 1; }
