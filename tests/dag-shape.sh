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
#   bash tests/dag-shape.sh [case]           cases: lint (k1-k6)
#   bash tests/dag-shape.sh --selftest [lint]
# Prints SHAPE-LINT-OK for the lint case, SHAPE-SELFTEST-LINT-OK for its teeth.
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

# ── dispatch ──────────────────────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--selftest" ]; then
  case "${2:-all}" in lint|all) selftest_lint;; *) fail "unknown selftest scope: $2";; esac
  exit 0
fi
case "${1:-lint}" in
  lint) case_lint;;
  *) fail "unknown case: $1";;
esac
exit 0
