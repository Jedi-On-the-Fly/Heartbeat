#!/usr/bin/env bash
# Proof: on a CONSTRAINED gate, `hb review <gate> pass` enforces the answers — at the shared layer
# (node hb.js review; python review_policy.accept_review, which the CLI, the MCP `review` tool and the
# executor all call). A pass is REFUSED when:
#   - no gate-time set was recorded in this review cycle;
#   - any constraint id (plan-time P + this cycle's gate-time G) has no answer line
#       <ID>: VIOLATED | NOT-REPRODUCED | N/A — <evidence or reason>
#     (prose mentioning an id is not an answer), or is answered twice, or an UNKNOWN id is answered;
#   - any answer is VIOLATED (case- and markdown-insensitive: "- **P1**: `violated`" counts);
#   - a NOT-REPRODUCED has no evidence, or an N/A no reason;
#   - the gate profile sets free_review and no `hb review <gate> free --artifact` was recorded in THIS
#     cycle by an actor other than the pass's reviewer. `review free` itself refuses a doer, an
#     unconstrained gate, a gate not awaiting review, a thin/uncited artifact. Answers in the free
#     artifact never count for the constrained ones.
# Each refusal names the offending id (or the missing step) and the fix. A valid pass records the
# per-status answer counts and the ids it answered; `hb doctor` re-checks the stored artifact against
# them. An unconstrained gate behaves exactly as before (golden fixtures, T166). node ≡ python on every
# verdict; the python MCP tool enforces the same. Prints REVIEW-ANSWERS-OK. `--selftest`: perturbed
# observations + reason-checked mutants of the real code. Prints SELFTEST-OK.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
unset HB_DIR DAG_FILE EVENTS_FILE HB_ACTOR HB_REFUTER 2>/dev/null || true
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
fail() { echo "FAIL: $*" >&2; exit 1; }
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
hbpy() { python3 -m heartbeat.cli "$@"; }

DAG='{"phases":[{"id":"P0","title":"p0","gate_entry":null,"gate_exit":"G0","tasks":[{"id":"t0","title":"w0"}]}],
 "gates":{"G0":{"desc":"g0","review":{"prompt":"refute P0","profile":"fr","constraints":[
   {"id":"P1","claim":"c1","subjects":["a.txt"],"violation":"v1"},{"id":"P2","claim":"c2","subjects":["a.txt"],"violation":"v2"}]},
   "criteria":[{"id":"c","cmd":"grep -q 2 \"$PROJECT_DIR/a.txt\""}]}}}'
GSET='[{"id":"G1","claim":"g1","subjects":["a.txt"],"violation":"w1"},{"id":"G2","claim":"g2","subjects":["a.txt"],"violation":"w2"}]'
HEAD='Refutation attempt on P0 / t0 / G0: I ran the gate criteria and probed a.txt myself.'
ok_lines() { printf -- '- **P1**: NOT-REPRODUCED — ran grep on a.txt, holds\nP2: N/A — covered by P1 on this phase\nG1: NOT-REPRODUCED — tried an empty a.txt, rejected\nG2: NOT-REPRODUCED — probe: cat a.txt shows 2\n'; }

hb() { local rt="$1" p="$2"; shift 2
  if [ "$rt" = py ]; then hbpy "$@" --dir "$p"; else
    case "$1" in gate) shift; bash "$p/.hb/gate.sh" "$@";; *) node "$p/.hb/hb.js" "$@";; esac; fi; }

scenario() { # <rt> → JSON observations
  local rt="$1" p o; p="$(mktemp -d "$work/p.XXXX")"; o="$work/o.$rt"; mkdir -p "$o"
  printf '1\n' > "$p/a.txt"
  if [ "$rt" = py ]; then hbpy init "$p" >/dev/null 2>&1; else bash "$ROOT/plugin/bootstrap.sh" "$p" --no-git >/dev/null 2>&1 </dev/null; fi
  printf '%s' "$DAG" > "$p/.hb/dag.json"; mkdir -p "$p/.hb/refuters"
  printf '%s' '{"persona":"FR persona","free_review":true}' > "$p/.hb/refuters/fr.json"
  hb "$rt" "$p" rebuild >/dev/null 2>&1
  HB_ACTOR=doer hb "$rt" "$p" start t0 >/dev/null 2>&1; printf '2\n' > "$p/a.txt"; HB_ACTOR=doer hb "$rt" "$p" done t0 >/dev/null 2>&1
  hb "$rt" "$p" gate G0 >/dev/null 2>&1
  # try <name> <actor> <verdict pass|free> <artifact body>  → name \t rc \t first line of stderr
  try() { local name="$1" who="$2" v="$3" body="$4" out rc
    printf '%s\n' "$body" > "$p/art.md"
    out="$(HB_ACTOR="$who" hb "$rt" "$p" review G0 "$v" --artifact art.md 2>&1)"; rc=$?
    [ "$rc" = 0 ] || rc=1
    printf '%s\t%s\t%s\n' "$name" "$rc" "$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-300)" >> "$o/v.tsv"; }
  try no-record     refuter pass "$HEAD
$(ok_lines)"
  printf '%s' "$GSET" > "$o/g.json"; HB_ACTOR=author hb "$rt" "$p" constraints G0 --record "$o/g.json" >/dev/null 2>&1
  try missing-id    refuter pass "$HEAD
$(ok_lines | grep -v '^G2')"
  try prose-only    refuter pass "$HEAD
$(ok_lines | grep -v '^P2')
Regarding P2 I think it is NOT-REPRODUCED as well."
  try no-evidence   refuter pass "$HEAD
$(ok_lines | sed 's/^G1: .*/G1: NOT-REPRODUCED/')"
  try na-no-reason  refuter pass "$HEAD
$(ok_lines | sed 's/^P2: .*/P2: N\/A —   /')"
  try violated-md   refuter pass "$HEAD
$(ok_lines | sed 's/^G2: .*/- **G2**: `violated` — cat a.txt shows 1 after a restart/')"
  try duplicate     refuter pass "$HEAD
$(ok_lines)
P1: NOT-REPRODUCED — second look"
  try unknown       refuter pass "$HEAD
$(ok_lines)
G9: NOT-REPRODUCED — made up"
  try free-missing  refuter pass "$HEAD
$(ok_lines)"
  try free-doer     doer    free "Free review of P0 / t0 / G0: looked in breadth at a.txt and the gate, nothing found."
  try free-thin     freer   free "fine"
  try free-ok       freer   free "Free review of P0 / t0 / G0: looked in breadth at a.txt and the gate, nothing found.
P1: NOT-REPRODUCED — free answers never count"
  # a new cycle: the earlier cycle's free review does not carry over
  HB_ACTOR=refuter hb "$rt" "$p" review G0 fail "hole" >/dev/null 2>&1; hb "$rt" "$p" gate G0 >/dev/null 2>&1
  HB_ACTOR=author hb "$rt" "$p" constraints G0 --record "$o/g.json" >/dev/null 2>&1
  try free-old      refuter pass "$HEAD
$(ok_lines)"
  try free-self     refuter free "Free review of P0 / t0 / G0: looked in breadth at a.txt and the gate, nothing found."
  try free-same     refuter pass "$HEAD
$(ok_lines)"
  if [ "$rt" = py ]; then   # the MCP review tool goes through the same enforcement
    printf '%s\n' "$HEAD" "$(ok_lines | grep -v '^G2')" > "$p/mcp.md"
    python3 -c "
import sys, json; from heartbeat import mcp_server as m
r = m.TOOLS['review'][0](sys.argv[1] + '/.hb', {'gate': 'G0', 'verdict': 'pass', 'artifact': sys.argv[1] + '/mcp.md'})
print('mcp-missing\t' + ('0' if r.get('ok') else '1') + '\t' + (r.get('stderr') or '')[:300])" "$p" >> "$o/v.tsv" 2>/dev/null
  else printf 'mcp-missing\t1\t(python only)\n' >> "$o/v.tsv"; fi
  try free-ok2      freer   free "Free review of P0 / t0 / G0: looked in breadth at a.txt and the gate, nothing found."
  try valid         refuter pass "$HEAD
$(ok_lines)"
  cp "$p/.hb/events.jsonl" "$o/events.jsonl"
  hb "$rt" "$p" doctor > "$o/doctor_clean.txt" 2>&1
  sed -i.bak '/^G1: /d' "$p/.hb/reviews/G0.md"; hb "$rt" "$p" doctor > "$o/doctor_edited.txt" 2>&1
  python3 - "$o" "$rt" <<'EOF'
import json, os, sys
o, rt = sys.argv[1:3]
rd = lambda n: open(os.path.join(o, n), encoding="utf-8", errors="replace").read() if os.path.exists(os.path.join(o, n)) else ""
v = {}
for l in rd("v.tsv").splitlines():
    parts = l.split("\t")
    v[parts[0]] = {"rc": parts[1], "msg": parts[2] if len(parts) > 2 else ""}
evs = [json.loads(l) for l in rd("events.jsonl").splitlines() if l.strip()]
rp = [e for e in evs if e.get("event") == "review_passed"]
fr = [e for e in evs if e.get("event") == "free_review_recorded"]
print(json.dumps({"rt": rt, "v": v, "passed": rp[-1] if rp else None, "free": fr,
                  "doctor_clean": rd("doctor_clean.txt"), "doctor_edited": rd("doctor_edited.txt")}))
EOF
  rm -rf "$p"
}

CHECK='
import json, sys
# name → (expected rc, fragment the refusal must contain)
EXPECT = {
  "no-record":    ("1", "no gate-time constraints were recorded"),
  "missing-id":   ("1", "G2"),
  "prose-only":   ("1", "P2"),
  "no-evidence":  ("1", "G1"),
  "na-no-reason": ("1", "P2"),
  "violated-md":  ("1", "G2 is answered VIOLATED"),
  "duplicate":    ("1", "P1"),
  "unknown":      ("1", "G9"),
  "free-missing": ("1", "free review"),
  "free-doer":    ("1", "executed this phase"),
  "free-thin":    ("1", "thin"),
  "free-ok":      ("0", ""),
  "free-old":     ("1", "free review"),
  "free-self":    ("0", ""),
  "free-same":    ("1", "free review"),
  "mcp-missing":  ("1", ""),
  "free-ok2":     ("0", ""),
  "valid":        ("0", ""),
}
def check(obs):
    by = {o["rt"]: o for o in obs}
    for rt, o in by.items():
        fx = o.get("fixtures") or {}
        if fx.get("edges"): return rt + ": fixtures: hostile answer sets ACCEPTED: " + ",".join(fx["edges"])
        if fx.get("legit"): return rt + ": fixtures: honest answer sets REFUSED: " + ",".join(fx["legit"])
        for name, (rc, frag) in EXPECT.items():
            got = o["v"].get(name)
            if got is None: return rt + ": case " + name + " did not run"
            if got["rc"] != rc: return rt + ": " + name + " rc=" + got["rc"] + " (want " + rc + "): " + got["msg"]
            if rc == "1" and frag and frag.lower() not in got["msg"].lower(): return rt + ": " + name + " refused for the wrong reason: " + got["msg"]
        if rt == "py" and "G2" not in o["v"]["mcp-missing"]["msg"]: return "py: the MCP review tool did not enforce the answers: " + o["v"]["mcp-missing"]["msg"]
        e = o["passed"]
        if not e: return rt + ": no review_passed recorded"
        if e.get("answers") != {"violated": 0, "not_reproduced": 3, "na": 1}: return rt + ": review_passed answer counts wrong: " + json.dumps(e.get("answers"))
        if sorted(e.get("constraint_ids") or []) != ["G1", "G2", "P1", "P2"]: return rt + ": review_passed constraint_ids wrong: " + json.dumps(e.get("constraint_ids"))
        if len(o["free"]) != 3 or any(f.get("actor") not in ("freer", "refuter") for f in o["free"]): return rt + ": free_review_recorded events wrong: " + json.dumps(o["free"])
        if "no longer" in o["doctor_clean"] or ("G0" in o["doctor_clean"] and "answer" in o["doctor_clean"]): return rt + ": doctor flagged an intact review"
        if not any("G0" in l and "answer" in l and "✗" in l for l in o["doctor_edited"].splitlines()): return rt + ": doctor missed an edited review artifact"
    n, p = by.get("node"), by.get("py")
    if not n or not p: return "missing runtime"
    nv = {k: v["rc"] for k, v in n["v"].items() if k != "mcp-missing"}; pv = {k: v["rc"] for k, v in p["v"].items() if k != "mcp-missing"}
    if nv != pv: return "parity: verdicts differ " + json.dumps(nv) + " vs " + json.dumps(pv)
    if n["passed"].get("answers") != p["passed"].get("answers"): return "parity: answer counts differ"
    return None
'

# the parser itself on the pinned hostile / honest fixtures (both runtimes): every hostile set refused,
# every honest layout accepted
fixtures() {
  local FX="$ROOT/tests/fixtures/review-answers"
  node -e 'const h=require(process.argv[1]);const fs=require("fs");const r={};for(const k of ["edges","legit"]){const cs=JSON.parse(fs.readFileSync(process.argv[2]+"/"+k+".json","utf8"));r[k]=cs.filter(([n,b])=>(k==="edges")===(h.checkAnswers(b,["P1"]).errors.length===0)).map(([n])=>n);}console.log(JSON.stringify(r))' "$ROOT/plugin/templates/hb.js" "$FX" > "$work/fx.node"
  python3 -c 'import json,sys;from heartbeat.review_policy import check_answers;r={}
for k in ("edges","legit"):
    cs=json.load(open(sys.argv[1]+"/"+k+".json",encoding="utf-8"));r[k]=[n for n,b in cs if (k=="edges")==(not check_answers(b,["P1"])[0])]
print(json.dumps(r))' "$FX" > "$work/fx.py"
}
fixtures

obs_file="$work/obs.json"
{ echo '['; scenario node; echo ','; scenario py; echo ']'; } > "$obs_file"
python3 - "$obs_file" "$work/fx.node" "$work/fx.py" <<'EOF'
import json, sys
o = json.load(open(sys.argv[1]))
for rt, f in (("node", sys.argv[2]), ("py", sys.argv[3])):
    try: fx = json.load(open(f))
    except Exception: fx = {"edges": ["UNREADABLE"], "legit": ["UNREADABLE"]}
    next(x for x in o if x["rt"] == rt)["fixtures"] = fx
json.dump(o, open(sys.argv[1], "w"))
EOF
[ -n "${HB_PROOF_DUMP:-}" ] && cp "$obs_file" "$HB_PROOF_DUMP"

if [ "${1:-}" = "--selftest" ]; then
  python3 - "$obs_file" <<EOF || exit 1
$CHECK
import copy
obs = json.load(open(sys.argv[1]))
b = check(obs)
if b: print("FAIL: selftest needs a green baseline; got: " + b, file=sys.stderr); sys.exit(1)
def get(rt): return next(o for o in obs if o["rt"] == rt)
def m(label, f):
    global obs
    saved = copy.deepcopy(obs); f()
    if check(obs) is None: print("FAIL: selftest: perturbation slipped past: " + label, file=sys.stderr); sys.exit(1)
    obs = saved
m("violated accepted",   lambda: get("node")["v"].__setitem__("violated-md", {"rc": "0", "msg": ""}))
m("wrong reason",        lambda: get("py")["v"].__setitem__("missing-id", {"rc": "1", "msg": "something else"}))
m("mcp not enforced",    lambda: get("py")["v"].__setitem__("mcp-missing", {"rc": "0", "msg": ""}))
m("counts wrong",        lambda: get("node")["passed"].__setitem__("answers", {"violated": 0, "not_reproduced": 4, "na": 0}))
m("doctor blind",        lambda: get("py").__setitem__("doctor_edited", "healthy"))
m("old free counted",    lambda: get("node")["v"].__setitem__("free-old", {"rc": "0", "msg": ""}))
EOF
  mutant() { # <label> <file> <old> <new> <expected failure fragment>
    local m="$work/mut"; rm -rf "$m"; mkdir -p "$m/docs/howto" "$m/py"
    cp -r "$ROOT/plugin" "$m/"; cp -r "$ROOT/py/src" "$m/py/"; cp -r "$ROOT/docs/howto/gate-examples" "$m/docs/howto/"
    mkdir -p "$m/tests/fixtures"; cp -r "$ROOT/tests/fixtures/review-answers" "$m/tests/fixtures/"
    python3 -c 'import sys; p, a, b = sys.argv[1:4]; s = open(p).read(); sys.exit(1) if s.count(a) != 1 else open(p, "w").write(s.replace(a, b))' \
      "$m/$2" "$3" "$4" || fail "selftest: mutant '$1' did not apply (the code moved — update the mutant)"
    local out; if out="$(bash "$m/docs/howto/gate-examples/review-answers.sh" 2>&1)"; then fail "selftest: mutant '$1' still passes — not load-bearing"; fi
    local frag hit=0; IFS='|' read -ra frags <<< "$5"   # alternatives: any listed reason is the expected one
    for frag in "${frags[@]}"; do case "$out" in *"$frag"*) hit=1;; esac; done
    [ "$hit" = 1 ] || fail "selftest: mutant '$1' failed for the WRONG reason: $out"
    echo "  mutant caught: $1"
  }
  mutant "node accepts a VIOLATED answer" plugin/templates/hb.js "    if (st === 'VIOLATED') { counts.violated++; errors.push(" "    if (st === 'VIOLATED') { counts.violated++; if (0) errors.push(" \
    "node: violated-md|node: fixtures"
  mutant "python ignores markdown decoration" py/src/heartbeat/review_policy.py '        l = re.sub(r"[*`_]", "", _ANSWER_CTRL.sub("", raw)).strip(" \t")' '        l = raw.strip()' \
    "py: violated-md|py: fixtures"
  mutant "node free review not required" plugin/templates/hb.js "      if (prof && prof.free_review) {" "      if (false) {" \
    "node: free-missing|node: fixtures"
  mutant "python counts an old-cycle free review" py/src/heartbeat/review_policy.py '            ok = any(i > start and e.get("event") == "free_review_recorded"' '            ok = any(e.get("event") == "free_review_recorded"' \
    "py: free-old|py: fixtures"
  mutant "node free reviewer may be the pass reviewer" plugin/templates/hb.js "                                              norm(e.actor || '') !== norm(reviewer));" "                                              true);" \
    "node: free-same|node: fixtures"
  mutant "python accepts a missing id" py/src/heartbeat/review_policy.py '            errors.append(f"{cid} has no answer line ({ANSWER_FORMAT})")' '            pass' \
    "py: missing-id|py: fixtures"
  mutant "node doctor skips the answers re-check" plugin/templates/hb.js "      if (!Array.isArray(e.constraint_ids)) continue;" "      continue;" \
    "node: doctor missed an edited review artifact|node: fixtures"
  mutant "python word check dropped" py/src/heartbeat/review_policy.py '    if word_lines and not counts["violated"]:' '    if False:' \
    "py: fixtures: hostile answer sets ACCEPTED|py: fixtures"
  mutant "node reads comments out of the word check" plugin/templates/hb.js "  for (const mode of ['keep', 'drop'])" "  for (const mode of ['drop'])" \
    "node: fixtures|node: "
  mutant "python reads comments out of the word check" py/src/heartbeat/review_policy.py '    word_lines = sum(1 for mode in ("keep", "drop") for line' '    word_lines = sum(1 for mode in ("drop",) for line' \
    "py: fixtures|py: "
  mutant "node folds styled letters instead of refusing them" plugin/templates/hb.js "  if (ANSWER_STYLED.test(String(body))) errors.push(" "  if (false) errors.push(" \
    "node: fixtures"
  mutant "python keeps an unclosed comment visible" py/src/heartbeat/review_policy.py 're.sub(r"<!--.*?(?:-->|\Z)", "", t, flags=re.S)' 're.sub(r"<!--.*?-->", "", t, flags=re.S)' \
    "py: fixtures"
  mutant "python pass without a recorded set" py/src/heartbeat/review_policy.py '        if not recorded:
            return 1, "", (f"review pass refused on {gate}: no gate-time' '        if False:
            return 1, "", (f"review pass refused on {gate}: no gate-time' \
    "py: no-record|py: fixtures"
  echo "SELFTEST-OK"; exit 0
fi

python3 - "$obs_file" <<EOF || exit 1
$CHECK
bad = check(json.load(open(sys.argv[1])))
if bad: print("FAIL: " + bad, file=sys.stderr); sys.exit(1)
print("review answers: 18 verdicts + counts + doctor × 2 runtimes (+ MCP) hold")
print("REVIEW-ANSWERS-OK")
EOF
