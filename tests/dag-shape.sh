#!/usr/bin/env bash
# dag-shape.sh — the shape contract (T186, written BEFORE the structure layer exists).
#
# dag.json's STRUCTURE has one judge, and the judgment is derived from the schema itself: every
# node of plugin/dag.schema.json annotated "x-hb-structure": true (plus the implicit root, which
# must be a readable JSON object carrying phases and gates) is STRUCTURE. A wrong-typed value at a
# structure node — or a missing required one, unless the node is also annotated
# "x-hb-absent-ok": true — is a lint ERROR on both runtimes, byte-identical, exactly one
# structure-attributable line, never a traceback; an unreadable file is the same failure with
# fixed bytes. Audit reports the same failure as one dag_shape finding and stays tolerant
# otherwise. Everything the schema does NOT annotate keeps its existing rules untouched — the
# k3 oracle (the pre-wave linters at commit a500587) proves no existing dag's lint output moved.
#
# SPEC-FIRST: the lint/audit/schema cases are RED TODAY by design — the schema carries no
# annotations yet, python lint crashes on several of these shapes, and the runtimes disagree.
#
#   bash tests/dag-shape.sh [case]           cases: lint (k1-k7) readers (r0-r10); default: both
#   bash tests/dag-shape.sh --selftest [lint|readers]
# Prints SHAPE-LINT-OK / SHAPE-READERS-OK per case and DAG-SHAPE-OK for both; the selftest prints
# SHAPE-SELFTEST-LINT-OK / SHAPE-SELFTEST-READERS-OK and DAG-SHAPE-SELFTEST-OK for both.
set -u
# Env hygiene: under a gate criterion, gate.sh exports HB_DIR/PROJECT_DIR/GATE — and the fixture
# projects' copied CLIs honor env HB_DIR. A proof must never inherit a caller's project pointers.
unset HB_DIR PROJECT_DIR GATE G DAG_FILE EVENTS_FILE 2>/dev/null || true
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export HB_NO_GIT=1 STUCK_TICKS=999
fail(){ echo "FAIL: $1"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
PYSRC="${HB_PY_SRC:-$ROOT/py/src}"
NLINT="${HB_NODE_LINT:-$ROOT/plugin/templates/hb-lint.js}"
NAUDIT="${HB_NODE_AUDIT:-$ROOT/plugin/templates/hb-audit.js}"
SCHEMA="$ROOT/plugin/dag.schema.json"
PRE=a500587   # the last commit before this wave: the k3 oracle's linters
PY(){ PYTHONPATH="$PYSRC" python3 -m heartbeat.cli "$@"; }
crashed(){ grep -qE 'Traceback|TypeError|AttributeError|KeyError|IndexError|ReferenceError|RangeError|Cannot read prop|is not iterable|is not a function|UnicodeDecodeError|UnicodeEncodeError' <<<"$1"; }

# ── the base: a lint-clean dag touching every structure node ──────────────────────────────────
BASE='{"project":"shape-fixture",
 "phases":[
  {"id":"P1","title":"first","gate_entry":null,"gate_exit":"G1","parked":false,
   "tasks":[{"id":"t1","title":"one","requires":[],"description":"writes one"},
            {"id":"t2","title":"two","requires":["t1"],"description":"writes two"}]},
  {"id":"P2","title":"second","gate_entry":"G1","gate_exit":"G2",
   "tasks":[{"id":"t3","title":"three","requires":[],"description":"writes three"}]}],
 "gates":{
  "G1":{"desc":"g1","criteria":[{"id":"c1","desc":"behavioral","cmd":"python3 -c \"assert 1+1==2\""}]},
  "G2":{"desc":"g2","criteria":[{"id":"c2","desc":"behavioral","cmd":"python3 -c \"assert 2+2==4\""}]}}}'

# ── the derivation: STRUCTURE mutations generated from the schema's annotations ───────────────
# Emits one line per mutation: <label>\t<path>\t<expect>\t<dag-json>
#   expect = path (a line naming the JSON path) | entry (the existing "criteria entry N" line)
derive(){
  python3 - "$SCHEMA" "$BASE" <<'PYEOF'
import json, sys
schema = json.load(open(sys.argv[1])); base = json.loads(sys.argv[2])
POOL = {"object": {}, "array": [], "string": "x", "integer": 5, "number": 5.5, "boolean": True, "null": None}
def declared(node):
    t = node.get("type")
    ts = set(t if isinstance(t, list) else ([t] if t else []))
    if "number" in ts: ts.add("integer")
    return ts
def wrong_values(node):
    ts = declared(node); out = []
    for k, v in POOL.items():
        if k in ts: continue
        if k == "number" and "integer" in ts: continue
        out.append(v)
    if "string" in ts and node.get("minLength", 0) >= 1: out.append("")
    return out
def get(d, path):
    for k in path: d = d[k]
    return d
def fmt(path):
    s = ""
    for k in path:
        s += f"[{k}]" if isinstance(k, int) else (("." if s else "") + k)
    return s
muts = []
def emit(label, path, expect, dag):
    muts.append((label, fmt(path), expect, json.dumps(dag)))
def walk(node, path, parent, key):
    # path: the concrete location in BASE of this schema node's first instance (None = absent)
    if node.get("x-hb-structure") is True and path is not None:
        exp = "entry" if (len(path) >= 3 and path[-2] == "criteria" and isinstance(path[-1], int)) else "path"
        for v in wrong_values(node):
            d = json.loads(json.dumps(base)); tgt = get(d, path[:-1]); tgt[path[-1]] = v
            emit(f"{fmt(path)}={json.dumps(v)}", path, exp, d)
        if parent is not None and key in (parent.get("required") or []) and not node.get("x-hb-absent-ok"):
            d = json.loads(json.dumps(base)); tgt = get(d, path[:-1]); del tgt[path[-1]]
            emit(f"{fmt(path)}=<absent>", path, "path", d)
    if path is None: return
    here = get(base, path) if path else base
    for k, sub in (node.get("properties") or {}).items():
        sp = path + [k] if isinstance(here, dict) and k in here else None
        walk(sub, sp, node, k)
    ap = node.get("additionalProperties")
    if isinstance(ap, dict) and isinstance(here, dict) and here:
        walk(ap, path + [sorted(here)[0]], None, None)
    it = node.get("items")
    if isinstance(it, dict) and isinstance(here, list):
        # the first instance that is non-empty for every nested container we will descend into
        idx = next((i for i, x in enumerate(here) if not isinstance(x, dict) or all(x.get(c) for c in ("tasks", "requires", "criteria") if c in x)), 0)
        if here: walk(it, path + [idx], node, None)
walk(schema, [], None, None)
for m in muts: print("\t".join(m))
PYEOF
}

# lint one file on both runtimes → "<exit>\x1f<json errors sorted>" per runtime, raw text kept in $LN/$LP
lint_both(){   # $1 = file ; sets LNR LPR LN LP JN JP
  LN=$(node "$NLINT" "$1" 2>&1); LNR=$?
  LP=$(PY lint "$1" 2>&1); LPR=$?
  JN=$(node "$NLINT" "$1" --json 2>&1); JP=$(PY lint "$1" --json 2>&1)
}
sorted_errors(){ python3 -c "
import json, sys
try: d = json.loads(sys.stdin.read())
except Exception: print('<unparseable>'); sys.exit(0)
print(json.dumps(sorted(d.get('errors', [])), ensure_ascii=False))"; }

# ── case: lint ─────────────────────────────────────────────────────────────────────────────────
case_lint(){
  local F="$W/k" n=0 label path expect dag se sp line
  mkdir -p "$F"
  printf '%s' "$BASE" > "$F/base.json"
  lint_both "$F/base.json"
  [ "$LNR" = 0 ] && [ "$LPR" = 0 ] || fail "base: the fixture dag must lint clean on both (node=$LNR py=$LPR): $LN / $LP"
  # (k1) every derived STRUCTURE mutation is an ERROR on both runtimes, byte-identical, one attributable line
  local muts; muts=$(derive) || fail "k1: the schema derivation crashed"
  [ "$(echo "$muts" | grep -c .)" -ge 40 ] || fail "k1: the schema derives only $(echo "$muts" | grep -c .) STRUCTURE mutations — the x-hb-structure annotations are missing or partial (want >= 40)"
  while IFS=$'\t' read -r label path expect dag; do
    [ -n "$label" ] || continue
    n=$((n+1)); printf '%s' "$dag" > "$F/m.json"
    lint_both "$F/m.json"
    crashed "$LN$LP$JN$JP" && fail "k1 [$label]: a lint CRASHED: $LN / $LP"
    [ "$LNR" = 1 ] && [ "$LPR" = 1 ] || fail "k1 [$label]: a STRUCTURE violation must be a lint ERROR on both (node=$LNR py=$LPR): $LN / $LP"
    se=$(echo "$JN" | sorted_errors); sp=$(echo "$JP" | sorted_errors)
    [ "$se" = "$sp" ] || fail "k1 [$label]: the error lists differ:
node: $se
py:   $sp"
    if [ "$expect" = entry ]; then
      [ "$(echo "$se" | python3 -c "import json,sys; print(sum('criteria entry' in e for e in json.load(sys.stdin)))")" = 1 ] \
        || fail "k1 [$label]: want exactly one existing 'criteria entry' line: $se"
    else
      [ "$(echo "$se" | python3 -c "import json,sys; p=sys.argv[1]; print(sum(p in e for e in json.load(sys.stdin)))" "$path")" = 1 ] \
        || fail "k1 [$label]: want exactly one error line naming the path '$path': $se"
    fi
    echo "$se" | grep -qE '(: |\(got |= )(undefined|None)|\[object |NaN' && fail "k1 [$label]: a junk line leaked from a rule iterating a malformed value: $se"
  done <<<"$muts"
  # (k2) unreadable / empty-plan dags: fixed class bytes, both runtimes, the no-arg python CLI too
  local P="$W/k2"; mkdir -p "$P/.hb"
  k2(){   # $1 = label, $2 = the expected class text ; the dag is already at $P/.hb/dag.json (or absent)
    local f="$P/.hb/dag.json" t o r
    lint_both "$f"
    crashed "$LN$LP$JN$JP" && fail "k2 [$1]: a lint CRASHED: $LN / $LP"
    [ "$LNR" = 1 ] && [ "$LPR" = 1 ] || fail "k2 [$1]: must be a lint ERROR on both (node=$LNR py=$LPR): $LN / $LP"
    se=$(echo "$JN" | sorted_errors); sp=$(echo "$JP" | sorted_errors)
    [ "$se" = "$sp" ] || fail "k2 [$1]: the error lists differ:
node: $se
py:   $sp"
    echo "$se" | grep -qF "$2" || fail "k2 [$1]: the error does not carry the fixed bytes '$2': $se"
    for t in lint audit; do
      o=$(PY "$t" --dir "$P" 2>&1); r=$?
      crashed "$o" && fail "k2 [$1]: python no-arg 'hb $t' CRASHED: $o"
      [ "$r" = 1 ] || fail "k2 [$1]: python no-arg 'hb $t' exit $r (want 1 — never 'valid' on an unreadable plan): $o"
      echo "$o" | grep -qE 'DAG valid|gates look behavioural' && fail "k2 [$1]: python no-arg 'hb $t' called a broken dag fine: $o"
      echo "$o" | grep -qF "$2" || fail "k2 [$1]: python no-arg 'hb $t' does not name '$2': $o"
    done
  }
  rm -f "$P/.hb/dag.json";                                         k2 "missing" "dag.json unreadable: missing"
  : > "$P/.hb/dag.json";                                           k2 "empty" "dag.json unreadable: empty"
  printf '{"phases": [' > "$P/.hb/dag.json";                       k2 "truncated" "dag.json unreadable: not valid JSON"
  printf '{"phases":[],"gates":{},"x":NaN}' > "$P/.hb/dag.json";  k2 "NaN" "dag.json unreadable: not valid JSON"
  printf '{"phases":[],"gates":{},"x":Infinity}' > "$P/.hb/dag.json"; k2 "Infinity" "dag.json unreadable: not valid JSON"
  printf '\xef\xbb\xbf{"phases":[],"gates":{}}' > "$P/.hb/dag.json"; k2 "BOM" "dag.json unreadable: not valid JSON"
  printf '{"phases":[],"gates":{},"x":"\xff\xfe"}' > "$P/.hb/dag.json"; k2 "invalid UTF-8" "dag.json unreadable: not valid JSON"
  printf '{"phases":[],"gates":{},"x":"\\ud800"}' > "$P/.hb/dag.json"; k2 "lone surrogate (string)" "dag.json unreadable: not valid JSON"
  printf '{"phases":[],"gates":{},"\\udc00":1}' > "$P/.hb/dag.json"; k2 "lone surrogate (key)" "dag.json unreadable: not valid JSON"
  for v in '[]' '"x"' '5' 'null'; do printf '%s' "$v" > "$P/.hb/dag.json"; k2 "top $v" "dag.json unreadable: top level is not an object"; done
  printf '{}' > "$P/.hb/dag.json";                                k2 "{}" "phases"
  printf '{"gates":{}}' > "$P/.hb/dag.json";                      k2 "no phases" "phases"
  printf '{"phases":[]}' > "$P/.hb/dag.json";                     k2 "no gates" "gates"
  printf '{"phases":[],"gates":{}}' > "$F/empty-plan.json"; lint_both "$F/empty-plan.json"
  [ "$LNR" = 0 ] && [ "$LPR" = 0 ] || fail "k2: an EMPTY phases list must stay lint-valid on both (node=$LNR py=$LPR) — gate-timeout-portable.sh relies on it"
  # (k3) NO NEW FINDINGS: the pre-wave linters are the oracle for every existing dag
  local O="$W/oracle"; mkdir -p "$O/py"
  git -C "$ROOT" cat-file -e "$PRE^{commit}" 2>/dev/null || fail "k3: the oracle commit $PRE is not in this repository"
  git -C "$ROOT" show "$PRE:plugin/templates/hb-lint.js" > "$O/hb-lint.js" || fail "k3: cannot extract the pre-wave node lint"
  git -C "$ROOT" archive "$PRE" py/src | tar -x -C "$O/py" || fail "k3: cannot extract the pre-wave python src"
  local f pre post pn pp checked=0 allow=0
  while IFS= read -r f; do
    checked=$((checked+1))
    if ! python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if "phases" in d and "gates" in d else 1)' "$ROOT/$f"; then
      # the ALLOWLIST: a dag lacking a required root container (the adapter fixtures carry no gates)
      # gains exactly the '<key>: missing' structure error(s), first, and nothing else moves
      python3 - "$(cd "$ROOT" && node "$O/hb-lint.js" "$f" --json 2>&1)" "$(cd "$ROOT" && node "$NLINT" "$f" --json 2>&1)" "$ROOT/$f" <<'PYEOF' || fail "k3: $f — beyond the allowlisted root-key error, the lint output moved"
import json, sys
pre, post = json.loads(sys.argv[1]), json.loads(sys.argv[2]); d = json.load(open(sys.argv[3]))
miss = [f"{k}: missing" for k in ("phases", "gates") if k not in d]
assert post["errors"] == miss + pre["errors"], (pre, post)
assert post["warnings"] == pre["warnings"], (pre, post)
PYEOF
      allow=$((allow+1))
    else
    pre=$(cd "$ROOT" && node "$O/hb-lint.js" "$f" 2>&1; echo "exit=$?")
    post=$(cd "$ROOT" && node "$NLINT" "$f" 2>&1; echo "exit=$?")
    [ "$pre" = "$post" ] || fail "k3: $f — the node lint output moved:
pre:  $pre
post: $post"
    fi
    pn=$(node "$NLINT" "$ROOT/$f" --json 2>&1); pp=$(PY lint "$ROOT/$f" --json 2>&1)
    [ "$(echo "$pn" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps([sorted(d["errors"]), sorted(d["warnings"])]))' 2>&1)" = \
      "$(echo "$pp" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps([sorted(d["errors"]), sorted(d["warnings"])]))' 2>&1)" ] \
      || fail "k3: $f — python lint disagrees with node:
node: $pn
py:   $pp"
  done < <(cd "$ROOT" && python3 - <<'PYEOF'
import glob, json
import subprocess
# EVERY tracked .json in the repo (git ls-files — a recursive glob skips dot-directories like
# planning/*/.hb/), filtered by the dag predicate below
files = sorted(subprocess.run(["git", "ls-files", "*.json"], capture_output=True, text=True, check=True).stdout.split())
for f in files:
    try: d = json.load(open(f))
    except Exception: continue
    if isinstance(d, dict) and ("phases" in d or "gates" in d) and "events" not in f and "dag.schema.json" not in f: print(f)
PYEOF
)
  [ "$checked" -ge 100 ] || fail "k3: only $checked existing dags were checked — the dag predicate is broken"
  [ "$allow" -ge 1 ] || fail "k3: the root-key allowlist matched nothing — the adapter fixtures dropped out of the oracle"
  # (k4) the REVERSE pin: every key the dag-writing verbs write is declared in the schema
  local rt Q
  cat > "$W/declared.py" <<'PYEOF'
import json, sys
schema = json.load(open(sys.argv[1])); dag = json.load(open(sys.argv[2])); bad = []
def check(node, val, path):
    if not isinstance(node, dict): return
    if isinstance(val, dict):
        props = node.get("properties") or {}; ap = node.get("additionalProperties", True)
        for k, v in val.items():
            if k in props: check(props[k], v, f"{path}.{k}")
            elif isinstance(ap, dict): check(ap, v, f"{path}.{k}")
            elif ap is False: bad.append(f"{path}.{k}")
    elif isinstance(val, list) and isinstance(node.get("items"), dict):
        for i, x in enumerate(val): check(node["items"], x, f"{path}[{i}]")
check(schema, dag, "")
if bad: print("undeclared:", bad); sys.exit(1)
PYEOF
  for rt in node py; do
    Q="$W/k4-$rt"; mkdir -p "$Q"; ( cd "$Q" && bash "$ROOT/plugin/bootstrap.sh" . >/dev/null 2>&1 )
    printf '%s' "$BASE" > "$Q/.hb/dag.json"
    ( cd "$Q" && for t in t1 t2; do HB_ACTOR=doer node .hb/hb.js start $t >/dev/null && HB_ACTOR=doer node .hb/hb.js done $t >/dev/null; done && bash .hb/gate.sh G1 >/dev/null 2>&1 ) || fail "k4 ($rt): fixture could not complete P1"
    printf 'Rearm evidence for G1 (task t1): the premise died; the revised criteria were run by hand and hold.\n' > "$Q/e.md"
    if [ "$rt" = node ]; then
      ( cd "$Q" && HB_ACTOR=al node .hb/hb.js park P2 shelved for now && HB_ACTOR=al node .hb/hb.js unpark P2 && HB_ACTOR=al node .hb/hb.js park P2 kept parked \
        && HB_ACTOR=carol node .hb/hb.js regate G1 premise died && HB_ACTOR=dave node .hb/hb.js regate G1 --rearm --artifact e.md --model m-1 \
        && HB_ACTOR=carol node .hb/hb.js regate G1 premise died again && HB_ACTOR=dave node .hb/hb.js regate G1 --rearm --artifact e.md \
        && HB_ACTOR=al node .hb/hb.js unpark P2 && HB_ACTOR=al node .hb/hb.js detach P2 dependency was false && HB_ACTOR=al node .hb/hb.js reattach P2 \
        && HB_ACTOR=al node .hb/hb.js detach P2 still false ) >/dev/null 2>&1 || fail "k4 (node): a dag-writing verb refused on the fixture"
    else
      ( cd "$Q" && HB_ACTOR=al PY park P2 --reason "shelved for now" --dir "$Q" && HB_ACTOR=al PY unpark P2 --dir "$Q" && HB_ACTOR=al PY park P2 --reason "kept parked" --dir "$Q" \
        && HB_ACTOR=carol PY regate G1 --reason "premise died" --dir "$Q" && HB_ACTOR=dave PY regate G1 --rearm --artifact e.md --model m-1 --dir "$Q" \
        && HB_ACTOR=carol PY regate G1 --reason "premise died again" --dir "$Q" && HB_ACTOR=dave PY regate G1 --rearm --artifact e.md --dir "$Q" \
        && HB_ACTOR=al PY unpark P2 --dir "$Q" && HB_ACTOR=al PY detach P2 --reason "dependency was false" --dir "$Q" && HB_ACTOR=al PY reattach P2 --dir "$Q" \
        && HB_ACTOR=al PY detach P2 --reason "still false" --dir "$Q" ) >/dev/null 2>&1 || fail "k4 (py): a dag-writing verb refused on the fixture"
    fi
    python3 "$W/declared.py" "$SCHEMA" "$Q/.hb/dag.json" || fail "k4 ($rt): a dag-writing verb wrote a key the schema does not declare (see above)"
    cp "$Q/.hb/dag.json" "$W/k4-$rt-final.json"
    : <<'PYEOF'
import json, sys
schema = json.load(open(sys.argv[1])); dag = json.load(open(sys.argv[2])); bad = []
def check(node, val, path):
    if not isinstance(node, dict): return
    if isinstance(val, dict):
        props = node.get("properties") or {}; ap = node.get("additionalProperties", True)
        for k, v in val.items():
            if k in props: check(props[k], v, f"{path}.{k}")
            elif isinstance(ap, dict): check(ap, v, f"{path}.{k}")
            elif ap is False: bad.append(f"{path}.{k}")
    elif isinstance(val, list) and isinstance(node.get("items"), dict):
        for i, x in enumerate(val): check(node["items"], x, f"{path}[{i}]")
check(schema, dag, "")
if bad: print("undeclared:", bad); sys.exit(1)
PYEOF
    node "$NLINT" "$Q/.hb/dag.json" >/dev/null 2>&1 || fail "k4 ($rt): the verb-written dag does not lint clean (node): $(node "$NLINT" "$Q/.hb/dag.json" 2>&1)"
    PY lint "$Q/.hb/dag.json" >/dev/null 2>&1 || fail "k4 ($rt): the verb-written dag does not lint clean (py): $(PY lint "$Q/.hb/dag.json" 2>&1)"
  done
  # k4's teeth: a bogus key planted in the regate marker, its rearm, a phase and a task is CAUGHT
  local plant
  for plant in 'd["gates"]["G1"]["regate"]["bogus"]=1' 'd["gates"]["G1"]["regate"]["rearm"]["bogus"]=1' 'd["phases"][1]["bogus"]=1' 'd["phases"][0]["tasks"][0]["bogus"]=1'; do
    python3 -c "import json,sys; d=json.load(open(sys.argv[1])); $plant; json.dump(d, open(sys.argv[2],'w'))" "$W/k4-node-final.json" "$W/plant.json" || fail "k4 teeth: could not plant ($plant)"
    python3 "$W/declared.py" "$SCHEMA" "$W/plant.json" >/dev/null && fail "k4 teeth: the declared-key checker missed a planted key ($plant) — a schema node is open by default"
  done
  # (k7) the cross-runtime edges of the layer itself (GATE_S1 gate-time catches)
  k7(){   # $1 = label, $2 = python statement over d (a copy of BASE) ; lint lists + dag_shape objects + audit findings agree
    printf '%s' "$BASE" | python3 -c "import json,sys; d=json.load(sys.stdin); $2; print(json.dumps(d))" > "$F/k7.json" || fail "k7 [$1]: fixture"
    lint_both "$F/k7.json"
    crashed "$LN$LP$JN$JP" && fail "k7 [$1]: a lint CRASHED: $LN / $LP"
    [ "$LNR" = "$LPR" ] || fail "k7 [$1]: lint exits differ (node=$LNR py=$LPR)"
    [ "$(echo "$JN" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)))')" = "$(echo "$JP" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)))')" ] \
      || fail "k7 [$1]: lint outputs differ (unsorted — order is part of the contract):
node: $JN
py:   $JP"
    local an ap
    an=$(node "$NAUDIT" "$F/k7.json" --json 2>&1); ap=$(PY audit "$F/k7.json" --json 2>&1)
    crashed "$an$ap" && fail "k7 [$1]: an audit CRASHED: $an / $ap"
    [ "$(echo "$an" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps([d["errors"], d["warns"], sorted(json.dumps(f, sort_keys=True) for f in d["findings"]), d["parked"]]))')" = \
      "$(echo "$ap" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps([d["errors"], d["warns"], sorted(json.dumps(f, sort_keys=True) for f in d["findings"]), d["parked"]]))')" ] \
      || fail "k7 [$1]: audit results differ (findings, counts or parked list):
node: $an
py:   $ap"
    if [ -n "${3:-}" ]; then echo "$JN" | grep -qF "$3" || fail "k7 [$1]: want '$3' in: $JN"; fi
  }
  k7 "integer-like gate keys" 'd["gates"]["10"]="x"; d["gates"]["9"]="y"' 'gates.9 must be an object'
  k7 "a gate named __proto__" 'd["gates"]["__proto__"]={"criteria":[5]}' 'criteria entry 0'
  k7 "detach fields on an invalid-id phase" 'd["phases"][1].update(id=5, gate_entry=None, detached_from="G1", detached_reason="r", detached_by="a", detached_at="t")'
  echo "$JN" | grep -qE '\[(5|5\.0|undefined|None|true|True)\]' && fail "k7: a detach line rendered an invalid id: $JN"
  local v
  # 1e400 is written as raw TEXT (python would serialize the parsed infinity as invalid JSON):
  # both parsers accept it as a number, and the type-named message must agree
  printf '%s' "$BASE" | python3 -c 'import json,sys; d=json.load(sys.stdin); d["gates"]["G1"]["criteria"]=["@BIG@"]; print(json.dumps(d))' | sed 's/"@BIG@"/1e400/' > "$F/big.json"
  lint_both "$F/big.json"
  [ "$JN" = "$(echo "$JP" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin),separators=(",",":"),ensure_ascii=False))')" ] && echo "$JN" | grep -q 'criteria entry 0' \
    || fail "k7 [criteria entry 1e400]: lint outputs differ or miss the entry line:
node: $JN
py:   $JP"
  for v in 1.0 -0.0 12345678901234567890 EMOJI; do
    k7 "criteria entry $v" "d['gates']['G1']['criteria']=[('\\U0001F600'*130) if '$v'=='EMOJI' else json.loads('$v')]" 'criteria entry 0'
  done
  k7 "a task id __proto__ that requires itself" 'd["phases"][0]["tasks"].append({"id":"__proto__","title":"p","requires":["__proto__"],"description":"d"})' 'dependency cycle'
  # a --json report larger than a pipe buffer is written whole (exitCode, never exit() mid-write)
  printf '%s' "$BASE" | python3 -c 'import json,sys; d=json.load(sys.stdin); d["phases"]+=[{"id":"Z%d"%i,"gate_exit":"NOPE%d"%i,"tasks":[]} for i in range(2500)]; print(json.dumps(d))' > "$F/big-out.json"
  node "$NLINT" "$F/big-out.json" --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert len(d["errors"]) >= 2500' 2>/dev/null || fail "k7: node lint --json was truncated when piped (>64 KiB)"
  node "$NAUDIT" "$F/big-out.json" --json | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null || fail "k7: node audit --json was truncated when piped"
  local pk
  for pk in constructor toString hasOwnProperty valueOf __proto__; do
    k7 "a gate_exit referencing '$pk'" "d['phases'][1]['gate_exit']='$pk'" "undefined gate: $pk"
    k7 "detached_from '$pk'" "d['phases'][1].update(gate_entry=None, detached_from='$pk', detached_reason='r', detached_by='a', detached_at='t')" 'detached_from must name'
  done
  # audit --questions fails closed on a malformed / unreadable plan and agrees on both runtimes
  q(){   # $1 = label, $2 = file, $3 = gate, $4 = want exit
    local on op rn rp
    on=$(node "$NAUDIT" "$2" --questions "$3" 2>&1); rn=$?
    op=$(PY audit "$2" --questions "$3" 2>&1); rp=$?
    crashed "$on$op" && fail "questions [$1]: CRASHED: $on / $op"
    [ "$rn" = "$4" ] && [ "$rp" = "$4" ] || fail "questions [$1]: exits node=$rn py=$rp (want $4): $on / $op"
    [ "$on" = "$op" ] || fail "questions [$1]: outputs differ:
node: $on
py:   $op"
  }
  printf '%s' "$BASE" > "$F/qb.json"; q "clean plan" "$F/qb.json" G1 0
  q "constructor on a clean plan" "$F/qb.json" constructor 0
  printf '%s' "$BASE" | python3 -c 'import json,sys; d=json.load(sys.stdin); d["gates"]["G1"]="x"; print(json.dumps(d))' > "$F/qs.json"; q "a string gate value" "$F/qs.json" G1 1
  printf '%s' "$BASE" | python3 -c 'import json,sys; d=json.load(sys.stdin); d["gates"]="abc"; print(json.dumps(d))' > "$F/qg.json"; q "a string gates map" "$F/qg.json" 0 1
  printf '%s' "$BASE" | python3 -c 'import json,sys; d=json.load(sys.stdin); d["gates"]["G1"]["criteria"][0]["cmd"]=5; print(json.dumps(d))' > "$F/qc.json"; q "a numeric cmd (not STRUCTURE)" "$F/qc.json" G1 0
  rm -f "$F/qm.json"; q "missing file" "$F/qm.json" G1 1
  printf '{"phases": [' > "$F/qt.json"; q "truncated" "$F/qt.json" G1 1
  printf '%s' "$BASE" | python3 -c 'import json,sys; d=json.load(sys.stdin); d["gates"]["G1"]["criteria"]=[{"id":"c%d"%i,"cmd":"python3 -c 1"} for i in range(3000)]; print(json.dumps(d))' > "$F/qbig.json"
  [ "$(node "$NAUDIT" "$F/qbig.json" --questions G1 | wc -l)" -ge 3000 ] || fail "questions: a large node checklist was truncated when piped"
  # a VALID-id phase's detach rendering, and non-string fields in the tolerant rest, agree on both
  for v in 5.0 -0.0 12345678901234567890 '[1.0]' '{"a":1}' '"G9"'; do
    k7 "detached_from=$v on a valid-id phase" "d['phases'][1].update(gate_entry=None, detached_from=json.loads('$v'), detached_reason='r', detached_by='a', detached_at='t')" 'detached_from must name'
  done
  k7 "a list desc carrying a control byte" 'd["gates"]["G1"]["criteria"][0]["desc"]=["x\u001e"]'
  k7 "a list cmd carrying a control byte beside a behavioral one" 'd["gates"]["G1"]["criteria"].append({"id":"c9","cmd":["x\u001f"]})'
  k7 "an object task title" 'd["phases"][0]["tasks"][0]["title"]={"out.txt":1}; d["gates"]["G1"]["criteria"][0]["cmd"]="grep -q ok \"$PROJECT_DIR/out.txt\""'
  k7 "a LIST task title naming the gated file" 'd["phases"][0]["tasks"][0]["title"]=["out.txt"]; d["phases"][0]["tasks"][0]["description"]=["out.txt"]; d["gates"]["G1"]["criteria"][0]["cmd"]="grep -q ok \"$PROJECT_DIR/out.txt\""'
  # detached_from as raw 1e400 TEXT on a valid-id phase (python would serialize infinity as invalid JSON)
  printf '%s' "$BASE" | python3 -c 'import json,sys; d=json.load(sys.stdin); d["phases"][1].update(gate_entry=None, detached_from="@BIG@", detached_reason="r", detached_by="a", detached_at="t"); print(json.dumps(d))' | sed 's/"@BIG@"/1e400/' > "$F/bigd.json"
  lint_both "$F/bigd.json"
  [ "$JN" = "$(echo "$JP" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin),separators=(",",":"),ensure_ascii=False))')" ] && echo "$JN" | grep -q 'detached_from must name' \
    || fail "k7 [detached_from=1e400]: lint outputs differ or miss the detach line:
node: $JN
py:   $JP"
  # a giant integer literal (> python's 4300-digit int limit) gets ONE verdict on both runtimes
  printf '{"phases":[],"gates":{},"_meta":%s}' "$(printf '1%.0s' $(seq 4400))" > "$F/gint.json"
  lint_both "$F/gint.json"; [ "$LNR" = 0 ] && [ "$LPR" = 0 ] || fail "k7 [giant int in _meta]: verdicts differ (node=$LNR py=$LPR): $LP"
  printf '%s' "$BASE" | python3 -c 'import json,sys; d=json.load(sys.stdin); d["phases"][0]["id"]="@BIG@"; print(json.dumps(d))' | sed "s/\"@BIG@\"/$(printf '7%.0s' $(seq 4400))/" > "$F/gid.json"
  lint_both "$F/gid.json"
  [ "$(echo "$JN" | sorted_errors)" = "$(echo "$JP" | sorted_errors)" ] && [ "$LNR" = 1 ] && [ "$LPR" = 1 ] || fail "k7 [giant int phase id]: lint differs:
node: $JN
py:   $JP"
  printf '%s' "$BASE" | python3 -c 'import json,sys; d=json.load(sys.stdin); d["gates"]["G3"]={}; print(json.dumps(d))' > "$F/qe.json"; q "an empty gate object" "$F/qe.json" G3 0
  printf '%s' "$BASE" | python3 -c 'import json,sys; d=json.load(sys.stdin); d["gates"]["G1"]["desc"]=[]; print(json.dumps(d))' > "$F/qd1.json"; q "a list desc" "$F/qd1.json" G1 0
  printf '%s' "$BASE" | python3 -c 'import json,sys; d=json.load(sys.stdin); d["gates"]["G1"]["desc"]={"a":1}; print(json.dumps(d))' > "$F/qd2.json"; q "an object desc" "$F/qd2.json" G1 0
  k7 "parked []" 'd["phases"][1]["parked"]=[]'
  k7 "parked {}" 'd["phases"][1]["parked"]={}'
  # (k5) audit: one dag_shape finding per structure-invalid / unreadable dag, mirrored, never a crash
  audit_shape(){   # $1 = file, $2 = label
    local an ap ar pr on op
    an=$(node "$NAUDIT" "$1" --json 2>&1); ar=$?
    ap=$(PY audit "$1" --json 2>&1); pr=$?
    crashed "$an$ap" && fail "k5 [$2]: an audit CRASHED: $an / $ap"
    [ "$ar" = 1 ] && [ "$pr" = 1 ] || fail "k5 [$2]: audit must exit 1 on both (node=$ar py=$pr)"
    on=$(echo "$an" | python3 -c 'import json,sys; d=json.load(sys.stdin); s=[f for f in d["findings"] if f.get("rule")=="dag_shape"]; print(len(s), json.dumps(s, sort_keys=True))')
    op=$(echo "$ap" | python3 -c 'import json,sys; d=json.load(sys.stdin); s=[f for f in d["findings"] if f.get("rule")=="dag_shape"]; print(len(s), json.dumps(s, sort_keys=True))')
    [ "${on%% *}" = 1 ] || fail "k5 [$2]: node audit must emit exactly one dag_shape finding: $an"
    [ "$on" = "$op" ] || fail "k5 [$2]: the dag_shape findings differ:
node: $on
py:   $op"
    on=$(node "$NAUDIT" "$1" 2>&1); op=$(PY audit "$1" 2>&1)
    [ "$(echo "$on" | grep '\[dag_shape\]')" = "$(echo "$op" | grep '\[dag_shape\]')" ] || fail "k5 [$2]: the dag_shape text lines differ"
    echo "$on$op" | grep -qi 'hollow gates' && fail "k5 [$2]: an audit summary calls a structure failure 'hollow gates': $on / $op"
    return 0
  }
  while IFS=$'\t' read -r label path expect dag; do
    [ -n "$label" ] || continue
    printf '%s' "$dag" > "$F/m.json"; audit_shape "$F/m.json" "$label"
  done <<<"$muts"
  local deep
  for deep in 300 5000; do
    python3 -c "import sys; n=int(sys.argv[1]); print('{\"phases\":[],\"gates\":{},\"x\":' + '['*n + ']'*n + '}')" "$deep" > "$P/.hb/dag.json"
    k2 "nested $deep" "dag.json unreadable: nested too deeply"
    audit_shape "$P/.hb/dag.json" "nested $deep"
  done
  rm -f "$F/none.json"; audit_shape "$F/none.json" "missing file"
  printf '{"phases": [' > "$F/trunc.json"; audit_shape "$F/trunc.json" "truncated"
  printf '{}' > "$F/obj.json"; audit_shape "$F/obj.json" "{}"
  # the tolerant rest: all-garbage criteria still also get hollow_gate (test_hardening.py pins it)
  printf '%s' "$BASE" | python3 -c 'import json,sys; d=json.load(sys.stdin); d["gates"]["G1"]["criteria"]=[None,"x",5]; print(json.dumps(d))' > "$F/garbage.json"
  node "$NAUDIT" "$F/garbage.json" --json | grep -q '"hollow_gate"' || fail "k5: audit stopped running its other rules on a dag_shape plan (hollow_gate missing on all-garbage criteria)"
  # clean plans never carry dag_shape
  for f in "$F/base.json" "$ROOT/plugin/templates/dag.json" "$ROOT"/planning/*.dag.json; do
    node "$NAUDIT" "$f" --json 2>/dev/null | grep -q '"dag_shape"' && fail "k5: a clean plan carries dag_shape: $f"
    PY audit "$f" --json 2>/dev/null | grep -q '"dag_shape"' && fail "k5: a clean plan carries dag_shape (py): $f"
  done
  # (k6) parked is control flow: every non-boolean is a lint error on both
  local v
  for v in '"no"' 1 '[]' '{}'; do
    printf '%s' "$BASE" | python3 -c "import json,sys; d=json.load(sys.stdin); d['phases'][1]['parked']=json.loads(sys.argv[1]); print(json.dumps(d))" "$v" > "$F/park.json"
    lint_both "$F/park.json"
    [ "$LNR" = 1 ] && [ "$LPR" = 1 ] || fail "k6: parked=$v must be a lint ERROR on both (node=$LNR py=$LPR) — it silently ends or splits the plan otherwise"
  done
  echo "SHAPE-LINT-OK ($n derived structure mutations, $checked existing dags against the $PRE oracle)"
}

# ── case: readers ──────────────────────────────────────────────────────────────────────────────
# Every plan-interpreting reader fails CLOSED on a malformed or unreadable dag: the tick wakes
# dag_corrupted, the resolvers say deadlock dag_invalid, verbs refuse or report, gate eval exits 4.
NODE_MUT="start done fail heartbeat beat review park unpark regate detach reattach horizon constraints anchor import"
NODE_READ="state ready rebuild changed evidence drift refute-prompt"
NODE_REPORT="doctor diagnose"
NODE_EXEMPT="protocol refuters"              # never read the plan's structure
PY_MUT="start done fail heartbeat review regate detach reattach horizon park unpark constraints"
PY_READ="state ready rebuild changed evidence refute-prompt report reward bench"
PY_REPORT="doctor diagnose"
PY_EXEMPT="init protocol refuters mcp-serve lint audit tick gate exec next"   # scaffold / static / own cases (S1, r1, r2, r5, r7, r8)
MCP_STATE="tick next"; MCP_REPORT="lint audit doctor diagnose"; MCP_EXEMPT="code_context code_discover deplint"
nverb_args(){ case "$1" in
  start|done|fail|heartbeat|beat) echo "$1 t2";; review) echo "review G1 pass --artifact a.md";;
  park) echo "park P2 shelved";; unpark|reattach) echo "$1 P2";; regate) echo "regate G1 premise died";;
  detach) echo "detach P2 claim was false";; horizon) echo "horizon close --reason done";;
  constraints) echo "constraints G1 --record c.json";; anchor|changed|evidence|refute-prompt) echo "$1 G1";;
  *) echo "$1";; esac; }
pverb_args(){ case "$1" in
  start|done|fail|heartbeat) echo "$1 t2";; review) echo "review G1 pass --artifact a.md";;
  park) echo "park P2 --reason shelved";; unpark|reattach) echo "$1 P2";; regate) echo "regate G1 --reason x";;
  detach) echo "detach P2 --reason x";; horizon) echo "horizon close --reason done";;
  constraints) echo "constraints G1 --record c.json";; changed|evidence|refute-prompt) echo "$1 G1";;
  bench) echo "bench --backend script";;
  *) echo "$1";; esac; }
mkproj(){   # the template project: bootstrapped, the base dag, one completed task in the log
  local T="$1"; mkdir -p "$T"; ( cd "$T" && bash "$ROOT/plugin/bootstrap.sh" . >/dev/null 2>&1 )
  printf '%s' "$BASE" > "$T/.hb/dag.json"
  ( cd "$T" && HB_ACTOR=doer node .hb/hb.js start t1 >/dev/null && HB_ACTOR=doer node .hb/hb.js done t1 >/dev/null ) || fail "readers: template could not complete t1"
  printf 'Refutation attempt for G1 (task t1): nothing to see.\nHOLES: none\n' > "$T/a.md"; printf '[]' > "$T/c.json"
}
nev(){ wc -l < "$1/.hb/events.jsonl" 2>/dev/null | tr -d ' '; }
first_error(){   # node lint's first error for the fixture's dag (the structure layer runs first)
  node "$NLINT" "$1/.hb/dag.json" --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["errors"][0])' 2>/dev/null
}
tickj(){ if [ "$2" = node ]; then ( cd "$1" && bash .hb/tick.sh 2>&1 ); else PY tick --dir "$1" 2>&1; fi; }
core_readers(){   # $1 = project, $2 = label
  local P="$1" L="$2" rt o r e0 fe n
  fe=$(first_error "$P"); [ -n "$fe" ] || fail "readers [$L]: the fixture lints clean — not a structure fixture"
  for rt in node py; do
    for n in 1 2; do
      o=$(tickj "$P" "$rt")
      crashed "$o" && fail "readers r1 [$L] ($rt): the tick CRASHED: $o"
      echo "$o" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); a=d.get("data") or {}
assert d.get("wakeAgent") is True and a.get("reason")=="dag_corrupted" and isinstance(a.get("errors"),list) and a["errors"], d' 2>/dev/null \
        || fail "readers r1 [$L] ($rt, tick $n): want a dag_corrupted WAKE carrying the errors: $o"
      local lc; lc='node .hb/hb-lint.js .hb/dag.json'; [ "$rt" = py ] && lc='hb lint'
      echo "$o" | python3 -c 'import json,sys; a=json.loads(sys.stdin.read())["data"].get("action",""); assert sys.argv[1] in a and "immutable" not in a and "state.json" in a, a' "$lc" 2>/dev/null \
        || fail "readers r1 [$L] ($rt): the dag_corrupted action must name '$lc', never 'immutable', and warn off state.json: $o"
    done
  done
  local rn rp
  rn=$( cd "$P" && node .hb/hb-next-task.js .hb/state.json 2>&1 ); rp=$(PY next --dir "$P" 2>&1)
  crashed "$rn$rp" && fail "readers r2 [$L]: a resolver CRASHED: $rn / $rp"
  for o in "$rn" "$rp"; do
    echo "$o" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); assert d.get("type")=="deadlock" and d.get("cause")=="dag_invalid", d' 2>/dev/null \
      || fail "readers r2 [$L]: want {type: deadlock, cause: dag_invalid}: node=$rn py=$rp"
  done
  [ "$(echo "$rn" | python3 -c 'import json,sys; print(sorted(json.loads(sys.stdin.read())))')" = "$(echo "$rp" | python3 -c 'import json,sys; print(sorted(json.loads(sys.stdin.read())))')" ] \
    || fail "readers r2 [$L]: the resolvers' keys differ: $rn / $rp"
  e0=$(nev "$P")
  o=$( cd "$P" && bash .hb/gate.sh G1 2>&1 ); r=$?
  [ "$r" = 4 ] || fail "readers r5 [$L]: gate.sh G1 exit $r (want 4): $o"
  o=$(PY gate G1 --dir "$P" 2>&1); r=$?
  [ "$r" = 4 ] || fail "readers r5 [$L]: hb gate G1 exit $r (want 4): $o"
  [ "$(nev "$P")" = "$e0" ] || fail "readers r5 [$L]: a refused gate appended an event"
  for rt in node py; do
    if [ "$rt" = node ]; then o=$( cd "$P" && node .hb/hb.js doctor 2>&1 ); r=$?; else o=$(PY doctor --dir "$P" 2>&1); r=$?; fi
    crashed "$o" && fail "readers r6 [$L] ($rt): doctor CRASHED: $o"
    [ "$r" = 1 ] || fail "readers r6 [$L] ($rt): doctor exit $r (want 1): $o"
    echo "$o" | grep -qF "$fe" || fail "readers r6 [$L] ($rt): doctor does not name the structure error '$fe': $o"
    echo "$o" | grep -qF 'plan checks skipped: dag.json invalid' || fail "readers r6 [$L] ($rt): doctor does not say the plan checks were skipped: $o"
    echo "$o" | grep -qiE 'drift|rebuild|regate|detach|reproducible|differs from the event-log' && fail "readers r6 [$L] ($rt): doctor ran a plan-derived check on a broken plan: $o"
  done
  return 0
}
case_readers(){
  local T="$W/tpl" P label path expect dag n=0 v
  mkproj "$T"
  # (r0) the regression pin: the lint-clean base behaves exactly as today
  P="$W/r0"; cp -a "$T" "$P"
  [ "$(tickj "$P" node | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["data"]["reason"])')" = next_task ] || fail "readers r0: node tick is not next_task on a clean plan"
  rm -rf "$P/.hb/leases"/* 2>/dev/null
  [ "$(tickj "$P" py | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["data"]["reason"])')" = next_task ] || fail "readers r0: python tick is not next_task on a clean plan"
  ( cd "$P" && node .hb/hb.js state >/dev/null && node .hb/hb.js doctor >/dev/null && bash .hb/gate.sh --check G1 >/dev/null 2>&1 ) || fail "readers r0: node state/doctor/gate --check refused a clean plan"
  ( PY state --dir "$P" >/dev/null && PY doctor --dir "$P" >/dev/null && PY gate G1 --check --dir "$P" >/dev/null 2>&1 ) || fail "readers r0: python state/doctor/gate --check refused a clean plan"
  # the core readers on EVERY derived structure mutation and every unreadable class
  while IFS=$'\t' read -r label path expect dag; do
    [ -n "$label" ] || continue
    n=$((n+1)); P="$W/rm$n"; cp -a "$T" "$P"; printf '%s' "$dag" > "$P/.hb/dag.json"
    core_readers "$P" "$label" </dev/null; rm -rf "$P"
  done <<<"$(derive)"
  [ "$n" -ge 40 ] || fail "readers: only $n derived mutations reached the readers"
  local nmut=$n
  local cls
  for cls in missing empty truncated NaN BOM top; do
    P="$W/ru-$cls"; cp -a "$T" "$P"
    case $cls in
      missing) rm -f "$P/.hb/dag.json";; empty) : > "$P/.hb/dag.json";; truncated) printf '{"phases": [' > "$P/.hb/dag.json";;
      NaN) printf '{"phases":[],"gates":{},"x":NaN}' > "$P/.hb/dag.json";; BOM) printf '\xef\xbb\xbf{"phases":[],"gates":{}}' > "$P/.hb/dag.json";;
      top) printf '[1]' > "$P/.hb/dag.json";;
    esac
    if [ "$cls" = missing ]; then fe="dag.json unreadable: missing"; else fe=$(first_error "$P"); fi
    core_readers_unreadable "$P" "unreadable $cls" "$fe"; rm -rf "$P"
  done
  # the FULL sweep on one representative per STRUCTURE class
  rep(){   # $1 = label, $2 = python statement over d, or RAW:<text>
    P="$W/rep-$1"; rm -rf "$P"; cp -a "$T" "$P"
    case "$2" in RAW:*) printf '%s' "${2#RAW:}" > "$P/.hb/dag.json";;
      *) printf '%s' "$BASE" | python3 -c "import json,sys; d=json.load(sys.stdin); $2; print(json.dumps(d))" > "$P/.hb/dag.json";; esac
  }
  local reps='unreadable|RAW:{"phases": [
container|d["phases"][0]["tasks"]="x"
id|d["phases"][0]["tasks"][1]["id"]=5
reference|d["phases"][1]["gate_entry"]=[]
parked|d["phases"][1]["parked"]="no"'
  local rl rs verb o r e0 h0 fe
  while IFS='|' read -r rl rs; do
    rep "$rl" "$rs"; fe=$(first_error "$P"); [ -n "$fe" ] || fail "readers [$rl]: representative lints clean"
    # derived coverage: every CLI verb is classified
    for verb in $(sed -n '/^if (require.main === module)/,$p' "$ROOT/plugin/templates/hb.js" | grep -oE "^  case '[a-z-]+'" | grep -oE "'[a-z-]+'" | tr -d "'"); do
      echo " $NODE_MUT $NODE_READ $NODE_REPORT $NODE_EXEMPT " | grep -q " $verb " || fail "readers: node verb '$verb' is unclassified (mutating / read / report / exempt)"
    done
    for verb in $(PY -h 2>&1 | grep -oE '\{[a-z,-]+\}' | head -1 | tr -d '{}' | tr ',' ' '); do
      echo " $PY_MUT $PY_READ $PY_REPORT $PY_EXEMPT " | grep -q " $verb " || fail "readers: python verb '$verb' is unclassified"
    done
    # (r3) mutating verbs refuse: nonzero, no event, dag.json untouched, the error named
    for verb in $NODE_MUT; do
      e0=$(nev "$P"); h0=$(cksum < "$P/.hb/dag.json")
      o=$( cd "$P" && HB_ACTOR=someone node .hb/hb.js $(nverb_args "$verb") 2>&1 ); r=$?
      crashed "$o" && fail "readers r3 [$rl] node $verb CRASHED: $o"
      [ "$r" != 0 ] || fail "readers r3 [$rl] node $verb exited 0 on a broken plan: $o"
      [ "$(nev "$P")" = "$e0" ] || fail "readers r3 [$rl] node $verb appended an event"
      [ "$(cksum < "$P/.hb/dag.json")" = "$h0" ] || fail "readers r3 [$rl] node $verb rewrote dag.json"
      echo "$o" | grep -qF "$fe" || fail "readers r3 [$rl] node $verb does not name '$fe': $o"
    done
    for verb in $PY_MUT; do
      e0=$(nev "$P"); h0=$(cksum < "$P/.hb/dag.json")
      o=$( cd "$P" && HB_ACTOR=someone PY $(pverb_args "$verb") --dir "$P" 2>&1 ); r=$?
      crashed "$o" && fail "readers r3 [$rl] py $verb CRASHED: $o"
      [ "$r" != 0 ] || fail "readers r3 [$rl] py $verb exited 0 on a broken plan: $o"
      [ "$(nev "$P")" = "$e0" ] || fail "readers r3 [$rl] py $verb appended an event"
      [ "$(cksum < "$P/.hb/dag.json")" = "$h0" ] || fail "readers r3 [$rl] py $verb rewrote dag.json"
      echo "$o" | grep -qF "$fe" || fail "readers r3 [$rl] py $verb does not name '$fe': $o"
    done
    # (r4) read verbs: nonzero, ONE line naming the first error and the runtime's lint command
    for verb in $NODE_READ; do
      o=$( cd "$P" && node .hb/hb.js $(nverb_args "$verb") 2>&1 ); r=$?
      [ "$r" != 0 ] && [ "$(echo "$o" | grep -c .)" = 1 ] && echo "$o" | grep -qF "$fe" && echo "$o" | grep -qF 'node .hb/hb-lint.js .hb/dag.json' \
        || fail "readers r4 [$rl] node $verb: want exit!=0 and ONE line naming '$fe' and the lint command (exit $r): $o"
    done
    o=$( cd "$P" && node .hb/hb.js constraints G1 --prompt 2>&1 ); r=$?
    [ "$r" != 0 ] && echo "$o" | grep -qF "$fe" || fail "readers r4 [$rl] node constraints --prompt: $o"
    for verb in $PY_READ; do
      o=$(PY $(pverb_args "$verb") --dir "$P" 2>&1); r=$?
      [ "$r" != 0 ] && [ "$(echo "$o" | grep -c .)" = 1 ] && echo "$o" | grep -qF "$fe" && echo "$o" | grep -qF 'hb lint' \
        || fail "readers r4 [$rl] py $verb: want exit!=0 and ONE line naming '$fe' and 'hb lint' (exit $r): $o"
    done
    o=$( cd "$P" && node .hb/hb-report.js .hb 2>&1 ); r=$?
    [ "$r" != 0 ] && echo "$o" | grep -qF "$fe" || fail "readers r4 [$rl] hb-report.js: $o"
    o=$( cd "$P" && node .hb/hb-viz.js .hb 2>&1 ); r=$?
    [ "$r" != 0 ] && echo "$o" | grep -qF "$fe" || fail "readers r4 [$rl] hb-viz.js: $o"
    # (r5) every gate mode refuses with exit 4 — ahead of usage (2) and a pending regate (3)
    e0=$(nev "$P")
    for o in "--check G1" "--all" ""; do
      ( cd "$P" && bash .hb/gate.sh $o >/dev/null 2>&1 ); r=$?; [ "$r" = 4 ] || fail "readers r5 [$rl] gate.sh $o exit $r (want 4)"
    done
    for o in "G1 --check" "--all"; do PY gate $o --dir "$P" >/dev/null 2>&1; r=$?; [ "$r" = 4 ] || fail "readers r5 [$rl] hb gate $o exit $r (want 4)"; done
    if [ "$rl" != unreadable ]; then
      python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["gates"]["G1"]["regate"]={"at":"t","reason":"r","actor":"a","prev_criteria":[],"pending":True}; json.dump(d,open(sys.argv[1],"w"))' "$P/.hb/dag.json"
      ( cd "$P" && bash .hb/gate.sh G1 >/dev/null 2>&1 ); r=$?; [ "$r" = 4 ] || fail "readers r5 [$rl] gate.sh on a regate-pending gate in a broken plan exit $r (want 4, ahead of 3)"
      PY gate G1 --dir "$P" >/dev/null 2>&1; r=$?; [ "$r" = 4 ] || fail "readers r5 [$rl] hb gate on a regate-pending gate exit $r (want 4)"
      rep "$rl" "$rs"
    fi
    [ "$(nev "$P")" = "$e0" ] || fail "readers r5 [$rl]: a refused gate appended an event"
    # (r6b) diagnose names dag_corrupted
    for o in "$( cd "$P" && node .hb/hb.js diagnose 2>&1 )" "$(PY diagnose --dir "$P" 2>&1)"; do
      crashed "$o" && fail "readers r6 [$rl] diagnose CRASHED: $o"
      echo "$o" | grep -q 'dag_corrupted' || fail "readers r6 [$rl] diagnose does not name dag_corrupted: $o"
    done
    # (r7) both exec drivers stop on dag_corrupted
    o=$( cd "$P" && HB_EXEC_BACKEND=script HB_EXEC_CMD='cat >/dev/null' node .hb/hb-exec.js run 2>&1 ); r=$?
    [ "$r" != 0 ] && echo "$o" | grep -q 'HB-EXEC STOP: dag_corrupted' || fail "readers r7 [$rl] node hb-exec: $o"
    o=$( HB_EXEC_BACKEND=script HB_EXEC_CMD='cat >/dev/null' PY exec run --dir "$P" 2>&1 ); r=$?
    [ "$r" != 0 ] && echo "$o" | grep -q 'HB-EXEC STOP: dag_corrupted' || fail "readers r7 [$rl] python hb exec: $o"
    # (r8) every MCP tool per class, through the server's own dispatch
    PYTHONPATH="$PYSRC" python3 - "$P/.hb" "$fe" "$MCP_STATE" "$MCP_REPORT" "$MCP_EXEMPT" <<'MCPEOF' || fail "readers r8 [$rl]: an MCP tool misbehaved (see above)"
import json, sys
from heartbeat import mcp_server as m
hb, fe = sys.argv[1], sys.argv[2]
state, report, exempt = sys.argv[3].split(), sys.argv[4].split(), sys.argv[5].split()
bad = []
for name in sorted(m.TOOLS):
    if name in exempt: continue
    args = {"task": "t2"} if name in ("start", "done", "fail") else ({"gate": "G1", "verdict": "pass", "artifact": "a.md"} if name == "review" else ({"gate": "G1"} if name == "gate" else {}))
    res = m._handle(hb, {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": name, "arguments": args}})["result"]
    text = res["content"][0]["text"]
    if "Traceback" in text: bad.append((name, "traceback")); continue
    if name == "tick":
        d = json.loads(text); a = d.get("data") or {}
        if not (d.get("wakeAgent") is True and a.get("reason") == "dag_corrupted"): bad.append((name, text))
    elif name == "next":
        d = json.loads(text)
        if not (d.get("type") == "deadlock" and d.get("cause") == "dag_invalid"): bad.append((name, text))
    elif name in report:
        if res.get("isError") or fe not in text and "dag_corrupted" not in text: bad.append((name, text))
    else:
        if not (res.get("isError") and fe in text): bad.append((name, text))
unclassified = [n for n in m.TOOLS if n not in state + report + exempt + ["ready", "state", "report", "gate", "start", "done", "fail", "review"]]
if unclassified: bad.append(("unclassified", unclassified))
if bad: print(bad); sys.exit(1)
MCPEOF
  done <<<"$reps"
  # (r9) a corrupt state.json AND a malformed dag: the structure check runs first → dag_corrupted
  P="$W/r9"; cp -a "$T" "$P"; printf '{"phases": [' > "$P/.hb/dag.json"; printf '{broken' > "$P/.hb/state.json"
  for rt in node py; do
    [ "$(tickj "$P" "$rt" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["data"]["reason"])' 2>&1)" = dag_corrupted ] || fail "readers r9 ($rt): a corrupt state + malformed dag must wake dag_corrupted (structure before the state self-heal)"
  done
  # (r10) NO SILENT SLEEP — and no silent SECOND tick: a crashing or missing resolver wakes deadlock
  # resolver_error on EVERY tick, every exec run stops, and diagnose names the cause (both runtimes)
  is_rerr(){ python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); assert d["wakeAgent"] is True and d["data"]["reason"]=="deadlock" and "resolver_error" in json.dumps(d), d' 2>/dev/null; }
  local how
  for how in crash missing; do
    P="$W/r10-$how"; cp -a "$T" "$P"
    if [ "$how" = crash ]; then printf 'process.exit(1)\n' > "$P/.hb/hb-next-task.js"; else rm -f "$P/.hb/hb-next-task.js"; fi
    for n in 1 2 3; do o=$(tickj "$P" node); echo "$o" | is_rerr || fail "readers r10 [$how] (node tick $n): want a deadlock resolver_error WAKE every tick: $o"; done
    for n in 1 2; do
      o=$( cd "$P" && HB_EXEC_BACKEND=script HB_EXEC_CMD='cat >/dev/null' node .hb/hb-exec.js run 2>&1 ); r=$?
      [ "$r" != 0 ] && echo "$o" | grep -q 'HB-EXEC STOP: deadlock' || fail "readers r10 [$how] (node exec run $n): want a STOP, never an IDLE exit 0: $o"
    done
    o=$( cd "$P" && node .hb/hb.js diagnose deadlock 2>&1 ); echo "$o" | grep -q 'resolver_error' && echo "$o" | grep -q 'restore .hb/hb-next-task.js' || fail "readers r10 [$how]: node diagnose deadlock does not name resolver_error and its cure: $o"
    o=$(tickj "$P" node); echo "$o" | python3 -c 'import json,sys; a=json.loads(sys.stdin.read())["data"].get("action",""); assert "resolver_error" in a, a' 2>/dev/null || fail "readers r10 [$how]: the node deadlock action does not name the resolver_error cure: $o"
  done
  P="$W/r10p"; cp -a "$T" "$P"; cp -r "$PYSRC" "$W/py-r10"
  python3 - "$W/py-r10/heartbeat/resolver.py" <<'R10EOF'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("def resolve(state, dag, hbdir):", "def resolve(state, dag, hbdir):\n    raise RuntimeError('resolver exploded')\n\n\ndef _orig_resolve(state, dag, hbdir):", 1)
open(p, "w").write(s)
R10EOF
  for n in 1 2 3; do o=$(PYTHONPATH="$W/py-r10" python3 -m heartbeat.cli tick --dir "$P" 2>&1); echo "$o" | is_rerr || fail "readers r10 (python tick $n): want a deadlock resolver_error WAKE every tick: $o"; done
  for n in 1 2; do
    o=$( HB_EXEC_BACKEND=script HB_EXEC_CMD='cat >/dev/null' PYTHONPATH="$W/py-r10" python3 -m heartbeat.cli exec run --dir "$P" 2>&1 ); r=$?
    [ "$r" != 0 ] && echo "$o" | grep -q 'HB-EXEC STOP: deadlock' || fail "readers r10 (python exec run $n): want a STOP: $o"
  done
  o=$(PYTHONPATH="$W/py-r10" python3 -m heartbeat.cli diagnose deadlock --dir "$P" 2>&1); echo "$o" | grep -q 'resolver_error' && echo "$o" | grep -q 'repair the heartbeat install' || fail "readers r10: python diagnose deadlock does not name resolver_error and its cure: $o"
  o=$(PYTHONPATH="$W/py-r10" python3 -m heartbeat.cli tick --dir "$P" 2>&1); echo "$o" | python3 -c 'import json,sys; a=json.loads(sys.stdin.read())["data"].get("action",""); assert "resolver_error" in a, a' 2>/dev/null || fail "readers r10: the python deadlock action does not name the resolver_error cure: $o"
  # (r11) the structure checker itself missing: every node reader fails CLOSED with one fixed line
  local miss='dag.json could not be checked (hb-lint.js missing or outdated?)' variant
  for variant in missing outdated; do
  P="$W/r11-$variant"; cp -a "$T" "$P"; rm -f "$P/.hb/hb-lint.js"
  [ "$variant" = outdated ] && printf 'module.exports = { lint: () => ({ errors: [], warnings: [] }) };\n' > "$P/.hb/hb-lint.js"
  for o in "$( cd "$P" && node .hb/hb.js state 2>&1 )" "$( cd "$P" && HB_ACTOR=x node .hb/hb.js start t2 2>&1 )" "$( cd "$P" && node .hb/hb.js doctor 2>&1 )" \
           "$( cd "$P" && node .hb/hb-next-task.js .hb/state.json 2>&1 )" "$( node "$P/.hb/hb-report.js" "$P/.hb" 2>&1 )" "$( node "$P/.hb/hb-viz.js" "$P/.hb" 2>&1 )" \
           "$( cd "$P" && bash .hb/gate.sh G1 2>&1 )" "$(tickj "$P" node)"; do
    crashed "$o$(echo "$o" | grep -c 'node:internal' | sed 's/^0$//;s/.*[1-9].*/Cannot read prop/')" && fail "readers r11: a node reader CRASHED with the checker missing: $o"
    echo "$o" | grep -qF "$miss" || fail "readers r11 [$variant]: a node reader did not fail closed with '$miss': $o"
  done
  done
  # (r12) the human-needed stop lists carry the two integrity reasons (the hook and the MCP tick tool)
  local hk; hk=$(mkdir -p "$W/r12/.hb" && : > "$W/r12/.hb/hb.js" && CLAUDE_PROJECT_DIR="$W/r12" bash "$ROOT/plugin/hooks/heartbeat-detect.sh" | tr '\n' ' ')
  echo "$hk" | grep -q 'dag_corrupted' && echo "$hk" | grep -q 'state_corrupted' || fail "readers r12: the SessionStart hook's stop list lacks dag_corrupted/state_corrupted: $hk"
  PYTHONPATH="$PYSRC" python3 -c 'from heartbeat import mcp_server as m; d=m.TOOLS["tick"][1]; assert "dag_corrupted" in d and "state_corrupted" in d, d' || fail "readers r12: the MCP tick tool's stop list lacks dag_corrupted/state_corrupted"
  # (r13) the live viz server re-checks on EVERY request: a plan broken while it runs is refused (409)
  P="$W/r13"; cp -a "$T" "$P"
  ( cd "$P" && exec node .hb/hb-viz.js .hb --serve --port 0 > "$W/r13.url" 2>&1 ) & local vpid=$!
  local url="" i
  for i in $(seq 50); do url=$(grep -o 'http://[^ ]*' "$W/r13.url" 2>/dev/null | head -1); [ -n "$url" ] && break; sleep 0.1; done
  [ -n "$url" ] || { kill "$vpid" 2>/dev/null; fail "readers r13: the viz server did not start"; }
  vget(){ node -e "require('http').get(process.argv[1]+'/state',r=>{let d='';r.on('data',c=>d+=c).on('end',()=>{console.log(r.statusCode+' '+d.slice(0,300))})}).on('error',e=>console.log('ERR '+e.message))" "$url"; }
  o=$(vget); [ "${o%% *}" = 200 ] || { kill "$vpid"; fail "readers r13: the viz server did not serve a clean plan: $o"; }
  printf '%s' "$BASE" | python3 -c 'import json,sys; d=json.load(sys.stdin); d["phases"][0]["tasks"]="x"; print(json.dumps(d))' > "$P/.hb/dag.json"
  o=$(vget); kill "$vpid" 2>/dev/null; wait "$vpid" 2>/dev/null
  [ "${o%% *}" = 409 ] && echo "$o" | grep -qF 'phases[0].tasks must be a list' || fail "readers r13: a plan broken under the running viz server was not refused with 409 + the error: $o"
  # (r14) a resolver answer that parses but is no verdict is resolver_error — never a phantom task
  local g ev
  for g in '{}' '[]' '"x"' '5' '{"task":"t2"}' '{"type":"weird"}'; do
    P="$W/r14"; rm -rf "$P"; cp -a "$T" "$P"
    printf 'console.log(%s)\n' "JSON.stringify($g)" > "$P/.hb/hb-next-task.js"
    o=$(tickj "$P" node); echo "$o" | is_rerr || fail "readers r14 [node $g]: an unusable resolver answer must wake deadlock resolver_error: $o"
    ev=$(nev "$P")
    o=$( cd "$P" && HB_EXEC_BACKEND=script HB_EXEC_CMD='cat >/dev/null' node .hb/hb-exec.js run 2>&1 ); r=$?
    [ "$r" != 0 ] && [ "$(nev "$P")" = "$ev" ] || fail "readers r14 [node $g]: the driver must STOP with no phantom task events (exit $r, events $ev → $(nev "$P")): $o"
    cp -r "$PYSRC" "$W/py-r14"; rm -rf "$W/py-r14-x"; mv "$W/py-r14" "$W/py-r14-x"
    python3 - "$W/py-r14-x/heartbeat/resolver.py" "$g" <<'R14EOF'
import sys
p, g = sys.argv[1], sys.argv[2]; s = open(p).read()
s = s.replace("def resolve(state, dag, hbdir):", "def resolve(state, dag, hbdir):\n    import json as _j\n    return _j.loads(%r)\n\n\ndef _orig_resolve(state, dag, hbdir):" % g, 1)
open(p, "w").write(s)
R14EOF
    P="$W/r14p"; rm -rf "$P"; cp -a "$T" "$P"
    o=$(PYTHONPATH="$W/py-r14-x" python3 -m heartbeat.cli tick --dir "$P" 2>&1); echo "$o" | is_rerr || fail "readers r14 [python $g]: an unusable resolver answer must wake deadlock resolver_error: $o"
    ev=$(nev "$P")
    o=$( HB_EXEC_BACKEND=script HB_EXEC_CMD='cat >/dev/null' PYTHONPATH="$W/py-r14-x" python3 -m heartbeat.cli exec run --dir "$P" 2>&1 ); r=$?
    crashed "$o" && fail "readers r14 [python $g]: the driver CRASHED: $o"
    [ "$r" != 0 ] && [ "$(nev "$P")" = "$ev" ] || fail "readers r14 [python $g]: the driver must STOP with no phantom task events (exit $r): $o"
  done
  # (r15) a resolver_error episode never arms the once-only deadlock alert: once cured, a REAL deadlock still wakes
  for rt in node py; do
    P="$W/r15-$rt"; rm -rf "$P"; cp -a "$T" "$P"; cp "$P/.hb/hb-next-task.js" "$W/r15-good.js"
    if [ "$rt" = node ]; then printf 'process.exit(1)\n' > "$P/.hb/hb-next-task.js"; tickj "$P" node >/dev/null; tickj "$P" node >/dev/null; cp "$W/r15-good.js" "$P/.hb/hb-next-task.js"
    else PYTHONPATH="$W/py-r10" python3 -m heartbeat.cli tick --dir "$P" >/dev/null 2>&1; PYTHONPATH="$W/py-r10" python3 -m heartbeat.cli tick --dir "$P" >/dev/null 2>&1; fi
    ( cd "$P" && HB_ACTOR=doer node .hb/hb.js start t2 >/dev/null ) && rm -rf "$P/.hb/leases"/*   # an active orphan: a real deadlock
    o=$(tickj "$P" "$rt")
    echo "$o" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); assert d["wakeAgent"] is True and d["data"]["reason"]=="deadlock" and "active_orphan" in json.dumps(d), d' 2>/dev/null \
      || fail "readers r15 ($rt): after a cured resolver_error, a real deadlock must still WAKE (the episode armed the alert flag?): $o"
  done
  # (r16) one dag_corrupted event per blockage on BOTH runtimes (the wake fires every tick; the log records it once)
  for rt in node py; do
    P="$W/r16-$rt"; rm -rf "$P"; cp -a "$T" "$P"; ev=$(nev "$P")
    printf '{"phases": [' > "$P/.hb/dag.json"
    for n in 1 2 3; do tickj "$P" "$rt" >/dev/null; done
    [ "$(nev "$P")" = $((ev+1)) ] || fail "readers r16 ($rt): want exactly ONE dag_corrupted event over 3 ticks of one blockage (events $ev → $(nev "$P"))"
    printf '%s' "$BASE" > "$P/.hb/dag.json"; tickj "$P" "$rt" >/dev/null; rm -rf "$P/.hb/leases"/*
    printf '{"phases": [' > "$P/.hb/dag.json"; tickj "$P" "$rt" >/dev/null
    [ "$(grep -c '"dag_corrupted"' "$P/.hb/events.jsonl")" = 2 ] || fail "readers r16 ($rt): a NEW blockage after a sound plan must log again (want 2 dag_corrupted events)"
  done
  echo "SHAPE-READERS-OK ($nmut derived mutations through the core readers; 5 representatives through every verb, gate mode, driver and MCP tool)"
}
core_readers_unreadable(){   # like core_readers, with the expected first error given (a missing file has no lint output to ask)
  local P="$1" L="$2" fe="$3" rt o r e0
  for rt in node py; do
    o=$(tickj "$P" "$rt")
    echo "$o" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); a=d.get("data") or {}
assert d.get("wakeAgent") is True and a.get("reason")=="dag_corrupted" and a.get("errors"), d' 2>/dev/null \
      || fail "readers r1 [$L] ($rt): want a dag_corrupted WAKE carrying the errors: $o"
  done
  for o in "$( cd "$P" && node .hb/hb-next-task.js .hb/state.json 2>&1 )" "$(PY next --dir "$P" 2>&1)"; do
    echo "$o" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); assert d.get("type")=="deadlock" and d.get("cause")=="dag_invalid", d' 2>/dev/null \
      || fail "readers r2 [$L]: want deadlock dag_invalid: $o"
  done
  e0=$(nev "$P")
  ( cd "$P" && bash .hb/gate.sh G1 >/dev/null 2>&1 ); r=$?; [ "$r" = 4 ] || fail "readers r5 [$L]: gate.sh exit $r (want 4)"
  PY gate G1 --dir "$P" >/dev/null 2>&1; r=$?; [ "$r" = 4 ] || fail "readers r5 [$L]: hb gate exit $r (want 4)"
  [ "$(nev "$P")" = "$e0" ] || fail "readers r5 [$L]: a refused gate appended an event"
  for rt in node py; do
    if [ "$rt" = node ]; then o=$( cd "$P" && node .hb/hb.js doctor 2>&1 ); r=$?; else o=$(PY doctor --dir "$P" 2>&1); r=$?; fi
    [ "$r" = 1 ] && echo "$o" | grep -qF "$fe" && echo "$o" | grep -qF 'plan checks skipped: dag.json invalid' || fail "readers r6 [$L] ($rt): doctor (exit $r): $o"
    echo "$o" | grep -qiE 'drift|rebuild|regate|detach|reproducible|differs from the event-log' && fail "readers r6 [$L] ($rt): doctor ran a plan-derived check: $o"
  done
  return 0
}

# ── selftest: mutation teeth ──────────────────────────────────────────────────────────────────
strip_node(){   # $1 = file, $2 = marker
  local b; b=$(grep -c "$2" "$1" 2>/dev/null || true); [ "${b:-0}" -gt 0 ] || fail "selftest: no '$2' marker in $1"
  sed -i "/$2/d" "$1"; node --check "$1" 2>/dev/null || fail "selftest: stripped $1 no longer parses (marker on a structural line)"
}
strip_py(){   # $1 = src copy, $2 = marker
  local hits; hits=$(grep -rl "$2" "$1" --include='*.py' || true); [ -n "$hits" ] || fail "selftest: no '$2' marker under $1"
  echo "$hits" | xargs sed -i "/$2/d"
  python3 -m py_compile $hits 2>/dev/null || fail "selftest: a stripped python file no longer compiles (marker not a complete statement)"
}
# the targeted mutation: a numeric task id — lint-clean and crash-free on the pre-wave code
target(){ printf '%s' "$BASE" | python3 -c 'import json,sys; d=json.load(sys.stdin); d["phases"][0]["tasks"][0]["id"]=5; d["phases"][0]["tasks"][1]["requires"]=[]; print(json.dumps(d))'; }
selftest_lint(){
  local S="$W/st" o r
  mkdir -p "$S/n" "$S/a"; printf '%s' "$BASE" > "$S/base.json"; target > "$S/t.json"
  # sl1: node lint guards stripped → base still clean, the target lints exit 0 with no traceback
  cp "$ROOT/plugin/templates/hb-lint.js" "$S/n/"; strip_node "$S/n/hb-lint.js" "shape-guard: lint"
  node "$S/n/hb-lint.js" "$S/base.json" >/dev/null 2>&1 || fail "selftest sl1: the stripped node lint broke the base dag (wrong reason)"
  o=$(node "$S/n/hb-lint.js" "$S/t.json" 2>&1); r=$?
  crashed "$o" && fail "selftest sl1: the stripped node lint CRASHED (wrong reason): $o"
  [ "$r" = 0 ] || fail "selftest sl1: the structure error survived the node lint strip (marker not load-bearing): $o"
  # sl2: python lint guards stripped
  cp -r "$ROOT/py/src" "$S/py2"; strip_py "$S/py2" "shape-guard: lint"
  HB_PY_SRC="$S/py2" PYTHONPATH="$S/py2" python3 -m heartbeat.cli lint "$S/base.json" >/dev/null 2>&1 || fail "selftest sl2: the stripped python lint broke the base dag (wrong reason)"
  o=$(PYTHONPATH="$S/py2" python3 -m heartbeat.cli lint "$S/t.json" 2>&1); r=$?
  crashed "$o" && fail "selftest sl2: the stripped python lint CRASHED (wrong reason): $o"
  [ "$r" = 0 ] || fail "selftest sl2: the structure error survived the python lint strip: $o"
  # sa1: node audit guards stripped → no dag_shape on the target, no crash
  cp "$ROOT/plugin/templates/hb-audit.js" "$ROOT/plugin/templates/hb-lint.js" "$S/a/"; strip_node "$S/a/hb-audit.js" "shape-guard: audit"
  node "$S/a/hb-audit.js" "$S/base.json" >/dev/null 2>&1 || fail "selftest sa1: the stripped node audit broke the base dag (wrong reason)"
  o=$(node "$S/a/hb-audit.js" "$S/t.json" --json 2>&1)
  crashed "$o" && fail "selftest sa1: the stripped node audit CRASHED (wrong reason): $o"
  echo "$o" | grep -q '"dag_shape"' && fail "selftest sa1: dag_shape survived the node audit strip"
  # sa2: python audit guards stripped
  cp -r "$ROOT/py/src" "$S/py3"; strip_py "$S/py3" "shape-guard: audit"
  PYTHONPATH="$S/py3" python3 -m heartbeat.cli audit "$S/base.json" >/dev/null 2>&1 || fail "selftest sa2: the stripped python audit broke the base dag (wrong reason)"
  o=$(PYTHONPATH="$S/py3" python3 -m heartbeat.cli audit "$S/t.json" --json 2>&1)
  crashed "$o" && fail "selftest sa2: the stripped python audit CRASHED (wrong reason): $o"
  echo "$o" | grep -q '"dag_shape"' && fail "selftest sa2: dag_shape survived the python audit strip"
  echo "SHAPE-SELFTEST-LINT-OK"
}

# the readers' target: parked "no" on P2 — a STRUCTURE error every unguarded reader walks past
# without crashing (the tick would quietly dispatch t2), so a strip reddens by behavior, not a crash
target_readers(){ printf '%s' "$BASE" | python3 -c 'import json,sys; d=json.load(sys.stdin); d["phases"][1]["parked"]="no"; print(json.dumps(d))'; }
selftest_readers(){
  local S="$W/sr" T="$W/sr-tpl" o r
  mkproj "$T"
  P="$S/n"; mkdir -p "$S"; cp -a "$T" "$P"; target_readers > "$P/.hb/dag.json"
  # sr1: the node reader guards stripped from the fixture's COPIES → node state answers, the resolver hands out work
  strip_node "$P/.hb/hb.js" "shape-guard: reader"; strip_node "$P/.hb/hb-next-task.js" "shape-guard: reader"
  ( cd "$P" && node .hb/hb.js state >/dev/null 2>&1 ) || fail "selftest sr1: node state still refuses with its guards stripped (marker not load-bearing)"
  o=$( cd "$P" && node .hb/hb-next-task.js .hb/state.json 2>&1 ); crashed "$o" && fail "selftest sr1: the stripped node resolver CRASHED (wrong reason): $o"
  echo "$o" | grep -q 'dag_invalid' && fail "selftest sr1: dag_invalid survived the node resolver strip"
  # st1: the tick guard stripped from tick.sh → the tick no longer wakes dag_corrupted
  P="$S/t"; cp -a "$T" "$P"; target_readers > "$P/.hb/dag.json"; strip_node_sh "$P/.hb/tick.sh" "shape-guard: tick"
  [ "$(tickj "$P" node | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["data"]["reason"])' 2>&1)" = dag_corrupted ] && fail "selftest st1: dag_corrupted survived the tick.sh strip"
  # sr2 + st2: the python reader / tick guards stripped from a runtime COPY
  cp -r "$ROOT/py/src" "$S/py"; strip_py "$S/py" "shape-guard: reader"; strip_py "$S/py" "shape-guard: tick"
  P="$S/p"; cp -a "$T" "$P"; target_readers > "$P/.hb/dag.json"
  PYTHONPATH="$S/py" python3 -m heartbeat.cli state --dir "$P" >/dev/null 2>&1 || fail "selftest sr2: python state still refuses with its guards stripped"
  o=$(PYTHONPATH="$S/py" python3 -m heartbeat.cli tick --dir "$P" 2>&1); crashed "$o" && fail "selftest st2: the stripped python tick CRASHED (wrong reason): $o"
  echo "$o" | grep -q 'dag_corrupted' && fail "selftest st2: dag_corrupted survived the tick.py strip"
  echo "SHAPE-SELFTEST-READERS-OK"
}
strip_node_sh(){ local b; b=$(grep -c "$2" "$1" 2>/dev/null || true); [ "${b:-0}" -gt 0 ] || fail "selftest: no '$2' marker in $1"; sed -i "/$2/d" "$1"; bash -n "$1" 2>/dev/null || fail "selftest: stripped $1 no longer parses"; }

# ── dispatch ──────────────────────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--selftest" ]; then
  case "${2:-all}" in
    lint) selftest_lint;;
    readers) selftest_readers;;
    all) selftest_lint && selftest_readers && echo "DAG-SHAPE-SELFTEST-OK";;
    *) fail "unknown selftest scope: $2";;
  esac
  exit 0
fi
case "${1:-all}" in
  lint) case_lint;;
  readers) case_readers;;
  all) case_lint && case_readers && echo "DAG-SHAPE-OK";;
  *) fail "unknown case: $1";;
esac
exit 0
