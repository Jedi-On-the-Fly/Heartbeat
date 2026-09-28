#!/usr/bin/env bash
# Proof: a review gate can declare PLAN-TIME constraints — `gates.<G>.review.constraints` =
# [{id P<n>, claim, subjects:[…], violation}] — and the static tools know them, identically in both
# runtimes:
#   - a well-formed list lints clean (and validates against plugin/dag.schema.json);
#   - a malformed one is a lint ERROR naming the gate and the id: not a list, an entry that is not
#     an object, a bad id (gate-time G-ids are reserved), a duplicate id within the gate, a missing /
#     empty claim / violation, subjects not a non-empty list of non-empty strings, and `constraints`
#     placed on the gate instead of inside `review`. The same P-id in two gates is fine;
#   - hb-audit WARNS `unconstrained_review` for a live review gate without constraints — a warning,
#     never an error — and says nothing for a constrained one or a review-less gate;
#   - a DAG without any constraints lints exactly as before.
# Prints CONSTRAINTS-SCHEMA-OK. `--selftest` perturbs the real observations and runs the proof against
# MUTANT copies of the real code (a lint rule removed in either runtime, the warning made an error) —
# each must go RED. Prints SELFTEST-OK.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
unset HB_DIR DAG_FILE EVENTS_FILE 2>/dev/null || true
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
fail() { echo "FAIL: $*" >&2; exit 1; }
export PYTHONPATH="$ROOT/py/src"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# case name → a DAG (python builds them so the JSON is exact)
python3 - "$work" <<'EOF'
import copy, json, os, sys
out = sys.argv[1]
C = lambda i, **kw: {**{"id": i, "claim": "the claim " + i, "subjects": ["src/a.py"], "violation": "a concrete counter-example for " + i}, **kw}
base = {"phases": [{"id": "P0", "title": "p0", "gate_entry": None, "gate_exit": "G0", "tasks": [{"id": "t0", "title": "build src/a.py"}]},
                   {"id": "P1", "title": "p1", "gate_entry": "G0", "gate_exit": "G1", "tasks": [{"id": "t1", "title": "build src/a.py"}]}],
        "gates": {"G0": {"desc": "g0", "review": {"prompt": "refute P0"}, "criteria": [{"id": "c", "cmd": "grep -q ok \"$PROJECT_DIR/src/a.py\""}]},
                  "G1": {"desc": "g1", "criteria": [{"id": "c", "cmd": "grep -q ok \"$PROJECT_DIR/src/a.py\""}]}}}
def dag(f):
    d = copy.deepcopy(base); f(d); return d
cases = {
  "no-constraints":   dag(lambda d: None),
  "valid":            dag(lambda d: d["gates"]["G0"]["review"].__setitem__("constraints", [C("P1"), C("P2")])),
  "same-id-2-gates":  dag(lambda d: (d["gates"]["G0"]["review"].__setitem__("constraints", [C("P1")]),
                                     d["gates"]["G1"].__setitem__("review", {"prompt": "r", "constraints": [C("P1")]}))),
  "not-a-list":       dag(lambda d: d["gates"]["G0"]["review"].__setitem__("constraints", {"id": "P1"})),
  "not-an-object":    dag(lambda d: d["gates"]["G0"]["review"].__setitem__("constraints", ["P1"])),
  "bad-id":           dag(lambda d: d["gates"]["G0"]["review"].__setitem__("constraints", [C("G1")])),
  "dup-id":           dag(lambda d: d["gates"]["G0"]["review"].__setitem__("constraints", [C("P1"), C("P1")])),
  "missing-claim":    dag(lambda d: d["gates"]["G0"]["review"].__setitem__("constraints", [{k: v for k, v in C("P1").items() if k != "claim"}])),
  "empty-violation":  dag(lambda d: d["gates"]["G0"]["review"].__setitem__("constraints", [C("P1", violation="  ")])),
  "bad-subjects":     dag(lambda d: d["gates"]["G0"]["review"].__setitem__("constraints", [C("P1", subjects="src/a.py")])),
  "empty-subjects":   dag(lambda d: d["gates"]["G0"]["review"].__setitem__("constraints", [C("P1", subjects=[])])),
  "gate-level":       dag(lambda d: d["gates"]["G0"].__setitem__("constraints", [C("P1")])),
}
for k, v in cases.items():
    json.dump(v, open(os.path.join(out, k + ".json"), "w"))
EOF
CASES="no-constraints valid same-id-2-gates not-a-list not-an-object bad-id dup-id missing-claim empty-violation bad-subjects empty-subjects gate-level"

observe() { # <case> → {case, node:{lint, audit}, py:{lint, audit}, schema}
  local c="$1" f="$work/$1.json"
  local nl nl_rc na pl pl_rc pa
  nl="$(node "$ROOT/plugin/templates/hb-lint.js" "$f" --json 2>/dev/null)"; nl_rc=$?
  na="$(node "$ROOT/plugin/templates/hb-audit.js" "$f" --json 2>/dev/null)"
  pl="$(python3 -m heartbeat.cli lint "$f" --json 2>/dev/null)"; pl_rc=$?
  pa="$(python3 -m heartbeat.cli audit "$f" --json 2>/dev/null)"
  python3 - "$c" "$nl" "$nl_rc" "$na" "$pl" "$pl_rc" "$pa" "$f" "$ROOT/plugin/dag.schema.json" <<'EOF'
import json, sys
c, nl, nlrc, na, pl, plrc, pa, f, schema = sys.argv[1:10]
def j(s):
    try: return json.loads(s)
    except Exception: return None
def lint(s, rc):
    d = j(s)
    return {"errors": sorted(d.get("errors") or []), "rc": int(rc)} if isinstance(d, dict) else None
def audit(s):
    d = j(s)
    if not isinstance(d, dict): return None
    return {"errors": d.get("errors"), "findings": sorted([x.get("severity"), x.get("rule"), x.get("gate")] for x in d.get("findings") or [] if x.get("rule") == "unconstrained_review")}
# schema: structural (no dependency) + jsonschema when installed
sc = json.load(open(schema))
rv = sc["properties"]["gates"]["additionalProperties"]["properties"]["review"]
cs = (rv.get("properties") or {}).get("constraints") or {}
item = cs.get("items") or {}
structural = cs.get("type") == "array" and set(item.get("required") or []) >= {"id", "claim", "subjects", "violation"}
valid = None
try:
    import jsonschema
    try: jsonschema.validate(json.load(open(f)), sc); valid = True
    except jsonschema.ValidationError: valid = False
except ImportError:
    pass
print(json.dumps({"case": c, "node": {"lint": lint(nl, nlrc), "audit": audit(na)}, "py": {"lint": lint(pl, plrc), "audit": audit(pa)},
                  "schema_structural": structural, "schema_valid": valid}))
EOF
}

CHECK='
import json, sys, re
BAD = {"not-a-list": None, "not-an-object": None, "bad-id": "G1", "dup-id": "P1", "missing-claim": "P1",
       "empty-violation": "P1", "bad-subjects": "P1", "empty-subjects": "P1", "gate-level": None}
def check(obs):
    by = {o["case"]: o for o in obs}
    for c, o in by.items():
        for rt in ("node", "py"):
            k = rt + "/" + c; L, A = o[rt]["lint"], o[rt]["audit"]
            if L is None or A is None: return k + ": lint/audit output unparseable"
            cerr = [e for e in L["errors"] if "constraint" in e]
            if c in BAD:
                if not cerr or L["rc"] == 0: return k + ": malformed constraints not a lint ERROR"
                if not any("G0" in e for e in cerr): return k + ": the error does not name the gate"
                if BAD[c] and not any(BAD[c] in e for e in cerr): return k + ": the error does not name the id " + BAD[c]
            else:
                if L["errors"] or L["rc"] != 0: return k + ": a well-formed DAG does not lint clean: " + str(L["errors"])
            if A["errors"] not in (0, None) and c in ("no-constraints", "valid", "same-id-2-gates"): return k + ": audit errors on a sound DAG"
            unc = A["findings"]
            if c == "no-constraints":
                if unc != [["warn", "unconstrained_review", "G0"]]: return k + ": unconstrained review gate G0 not WARNED exactly once (G1 has no review): " + str(unc)
            if c in ("valid",):
                if unc: return k + ": constrained gate still warned unconstrained_review"
            if c == "same-id-2-gates" and unc: return k + ": both gates constrained, still warned"
        if o["node"] != o["py"]: return "parity: " + c + " node " + json.dumps(o["node"]) + " vs py " + json.dumps(o["py"])
        if not o["schema_structural"]: return "schema: review.constraints (array of {id, claim, subjects, violation}) missing from plugin/dag.schema.json"
        if o["schema_valid"] is not None:
            if c in ("valid", "no-constraints", "same-id-2-gates") and o["schema_valid"] is not True: return "schema: " + c + " rejected by dag.schema.json"
            if c in ("not-a-list", "not-an-object", "missing-claim", "bad-subjects", "gate-level") and o["schema_valid"] is not False: return "schema: " + c + " accepted by dag.schema.json"
    return None
'

obs_file="$work/obs.json"
{ echo '['; first=1; for c in $CASES; do [ $first = 1 ] || echo ','; first=0; observe "$c"; done; echo ']'; } > "$obs_file"
[ -n "${HB_PROOF_DUMP:-}" ] && cp "$obs_file" "$HB_PROOF_DUMP"

if [ "${1:-}" = "--selftest" ]; then
  python3 - "$obs_file" <<EOF || exit 1
$CHECK
import copy
obs = json.load(open(sys.argv[1]))
b = check(obs)
if b: print("FAIL: selftest needs a green baseline; got: " + b, file=sys.stderr); sys.exit(1)
def get(c): return next(o for o in obs if o["case"] == c)
def m(label, f):
    global obs
    saved = copy.deepcopy(obs); f()
    if check(obs) is None: print("FAIL: selftest: perturbation slipped past: " + label, file=sys.stderr); sys.exit(1)
    obs = saved
m("dup id accepted",          lambda: get("dup-id")["node"].__setitem__("lint", {"errors": [], "rc": 0}))
m("error names no id",        lambda: get("bad-id")["py"]["lint"].__setitem__("errors", ["[G0] constraint: bad"]))
m("warning missing",          lambda: get("no-constraints")["node"]["audit"].__setitem__("findings", []))
m("warning on constrained",   lambda: get("valid")["py"]["audit"].__setitem__("findings", [["warn", "unconstrained_review", "G0"]]))
m("warning is an error",      lambda: get("no-constraints")["py"]["audit"].__setitem__("findings", [["error", "unconstrained_review", "G0"]]))
m("parity drift",             lambda: get("missing-claim")["py"]["lint"]["errors"].append("[G0] constraint P1: extra"))
m("schema lacks constraints", lambda: get("valid").__setitem__("schema_structural", False))
EOF
  mutant() { # <label> <file> <old> <new> <expected failure fragment> — RED, for the EXPECTED reason
    local m="$work/mut"; rm -rf "$m"; mkdir -p "$m/docs/howto" "$m/py"
    cp -r "$ROOT/plugin" "$m/"; cp -r "$ROOT/py/src" "$m/py/"; cp -r "$ROOT/docs/howto/gate-examples" "$m/docs/howto/"
    python3 -c 'import sys; p, a, b = sys.argv[1:4]; s = open(p).read(); sys.exit(1) if s.count(a) != 1 else open(p, "w").write(s.replace(a, b))' \
      "$m/$2" "$3" "$4" || fail "selftest: mutant '$1' did not apply (the code moved — update the mutant)"
    local out; if out="$(bash "$m/docs/howto/gate-examples/constraints-schema.sh" 2>&1)"; then fail "selftest: mutant '$1' still passes — not load-bearing"; fi
    case "$out" in *"$5"*) ;; *) fail "selftest: mutant '$1' failed for the WRONG reason: $out";; esac
    echo "  mutant caught: $1"
  }
  mutant "node duplicate-id check removed" plugin/templates/hb-lint.js "      else if (seen.has(c.id)) errors.push(" "      else if (false) errors.push(" \
    "dup-id: malformed constraints not a lint ERROR"
  mutant "python subjects check removed" py/src/heartbeat/lint.py '            if not isinstance(subj, list) or not subj' '            if False and not subj' \
    "py/bad-subjects: malformed constraints not a lint ERROR"
  mutant "python accepts G-ids at plan time" py/src/heartbeat/lint.py 're.fullmatch(r"P[0-9]+", cid)' 're.fullmatch(r"[PG][0-9]+", cid)' \
    "py/bad-id: malformed constraints not a lint ERROR"
  mutant "node gate-level constraints ignored" plugin/templates/hb-lint.js "    if (Object.prototype.hasOwnProperty.call(gv, 'constraints'))" "    if (false)" \
    "node/gate-level: malformed constraints not a lint ERROR"
  mutant "node warning made an error" plugin/templates/hb-audit.js "      F('warn', 'unconstrained_review', p.id," "      F('error', 'unconstrained_review', p.id," \
    "audit errors on a sound DAG"
  mutant "python warning dropped" py/src/heartbeat/audit.py '        if rv and not (isinstance(rv.get("constraints"), list) and rv["constraints"]):' '        if False:' \
    "py/no-constraints: unconstrained review gate G0 not WARNED"
  mutant "schema lacks constraints" plugin/dag.schema.json '              "constraints": {' '              "constraintz": {' \
    "schema: review.constraints"
  echo "SELFTEST-OK"; exit 0
fi

python3 - "$obs_file" <<EOF || exit 1
$CHECK
bad = check(json.load(open(sys.argv[1])))
if bad: print("FAIL: " + bad, file=sys.stderr); sys.exit(1)
print("constraints schema: 12 cases × lint + audit × 2 runtimes hold")
print("CONSTRAINTS-SCHEMA-OK")
EOF
