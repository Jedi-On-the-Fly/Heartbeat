#!/usr/bin/env bash
# Proof: `hb exec` runs the constraint-first review UNATTENDED, in both executors. At review_pending on a
# CONSTRAINED gate the driver dispatches, in order:
#   author  (backend mode `author`, reply {"ok":bool,"constraints":[…]}) → recorded via hb constraints
#           --record as a distinct author actor;
#   refute  (the constrained prompt — every id + answer format);
#   refute  with payload.review = "free" (the --free prompt) when the profile sets free_review → recorded
#           via hb review <gate> free as a distinct free actor;
#   then the SAME enforced `review pass` as the interactive path.
# Each dispatch carries its own profile model verbatim (author_model / model / free_model), and an unset
# one falls back to the executor's existing refute default (HB_REFUTE_MODEL) — never a substituted name.
# A refused pass (a VIOLATED answer, a missing id) is recorded as review_failed with the refusal reason
# and the run stops (escalation) — never an uncaught crash, never a pass. A panel checks each
# panelist's answers on their own (one VIOLATED panelist refuses). A malformed author reply escalates
# (review_error) and records nothing. An UNCONSTRAINED gate follows the old path (no author, no free).
# node ≡ python on the recorded event sequence. Prints EXEC-CONSTRAINED-REVIEW-OK.
# `--selftest`: perturbed observations + reason-checked mutants. Prints SELFTEST-OK.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
unset HB_DIR DAG_FILE EVENTS_FILE HB_ACTOR HB_REFUTER HB_REFUTE_MODEL HB_EXEC_MODEL HB_EXEC_BACKEND 2>/dev/null || true
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
fail() { echo "FAIL: $*" >&2; exit 1; }
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
hbpy() { python3 -m heartbeat.cli "$@"; }

# The stub backend: logs "mode<TAB>review<TAB>model" per call; behaviour steered by env.
bindir="$work/bin"; mkdir -p "$bindir"
cat > "$bindir/stub" <<'STUB'
#!/usr/bin/env python3
import json, os, re, sys
mode = sys.argv[-1] if len(sys.argv) > 1 else "execute"
p = json.load(sys.stdin)
log = os.environ["STUB_LOG"]
review = p.get("review") or ""
with open(log, "a") as f:
    f.write("%s\t%s\t%s\n" % (mode, review, os.environ.get("HB_EXEC_MODEL", "")))
n = sum(1 for _ in open(log))
if mode == "execute":
    open(os.path.join(os.getcwd(), "a.txt"), "w").write("2\n")
    print(json.dumps({"ok": True, "summary": "wrote a.txt"})); sys.exit(0)
if mode == "author":
    if os.environ.get("STUB_AUTHOR") == "bare":   # a bare array instead of {"ok","constraints"}
        print(json.dumps([{"id": "G1", "claim": "c", "subjects": ["a.txt"], "violation": "v"}])); sys.exit(0)
    if os.environ.get("STUB_AUTHOR") == "bad":
        print(json.dumps({"ok": False, "error": "the model produced no constraint list"})); sys.exit(0)
    print(json.dumps({"ok": True, "constraints": [{"id": "G1", "claim": "a.txt says 2", "subjects": ["a.txt"], "violation": "a.txt says anything else"}]}))
    sys.exit(0)
# refute (constrained or free)
if os.environ.get("STUB_REFUTE") == "null":
    print("null"); sys.exit(0)
if os.environ.get("STUB_REFUTE") == "list-findings":
    print(json.dumps({"refuted": False, "findings": ["a", "list"]})); sys.exit(0)
head = "Refutation of P0 / t0 / G0: ran the gate criterion and inspected a.txt myself."
if review == "free" and os.environ.get("STUB_FREE") == "refute":
    print(json.dumps({"refuted": True, "findings": "Free review of P0 / t0 / G0: an exploitable hole found in breadth."})); sys.exit(0)
if review == "free":
    print(json.dumps({"refuted": False, "findings": "Free review of P0 / t0 / G0: looked in breadth at a.txt; nothing exploitable."})); sys.exit(0)
ids = re.findall(r"(?m)^  - ([PG][0-9]+): ", p.get("prompt", ""))
refutes = [l for l in open(log) if l.startswith("refute\t\t")]
violate = os.environ.get("STUB_VIOLATE") == "1" or (os.environ.get("STUB_VIOLATE_PANELIST") and len(refutes) == int(os.environ["STUB_VIOLATE_PANELIST"]))
lines = [head] + ["%s: %s — probe: cat a.txt" % (i, "VIOLATED" if (violate and k == 0) else "NOT-REPRODUCED") for k, i in enumerate(ids)]
print(json.dumps({"refuted": False, "findings": "\n".join(lines)}))
STUB
chmod +x "$bindir/stub"

DAG_C='{"phases":[{"id":"P0","title":"p0","gate_entry":null,"gate_exit":"G0","tasks":[{"id":"t0","title":"write a.txt"}]}],
 "gates":{"G0":{"desc":"g0","review":{"prompt":"refute P0","profile":"cp","constraints":[{"id":"P1","claim":"a.txt says 2","subjects":["a.txt"],"violation":"it does not"}]},
   "criteria":[{"id":"c","cmd":"grep -q 2 \"$PROJECT_DIR/a.txt\""}]}}}'
DAG_U='{"phases":[{"id":"P0","title":"p0","gate_entry":null,"gate_exit":"G0","tasks":[{"id":"t0","title":"write a.txt"}]}],
 "gates":{"G0":{"desc":"g0","review":{"prompt":"refute P0 / t0 / G0","profile":"cp"},"criteria":[{"id":"c","cmd":"grep -q 2 \"$PROJECT_DIR/a.txt\""}]}}}'

# run <rt> <name> <dag> <profile-json> [ENV=V …] → observation JSON
run() {
  local rt="$1" name="$2" dag="$3" prof="$4"; shift 4
  local p o; p="$(mktemp -d "$work/p.XXXX")"; o="$work/o.$rt.$name"; mkdir -p "$o"; : > "$o/log"
  if [ "$rt" = py ]; then hbpy init "$p" >/dev/null 2>&1; else bash "$ROOT/plugin/bootstrap.sh" "$p" --no-git >/dev/null 2>&1 </dev/null; fi
  printf '%s' "$dag" > "$p/.hb/dag.json"; mkdir -p "$p/.hb/refuters"; printf '%s' "$prof" > "$p/.hb/refuters/cp.json"
  printf '1\n' > "$p/a.txt"
  local rc
  if [ "$rt" = py ]; then hbpy rebuild --dir "$p" >/dev/null 2>&1
    ( cd "$p" && env "$@" PATH="$bindir:$PATH" STUB_LOG="$o/log" HB_EXEC_CMD=stub HB_EXEC_MAX_ITERS=30 python3 -m heartbeat.cli exec run --dir "$p" > "$o/out" 2>&1 ); rc=$?
  else node "$p/.hb/hb.js" rebuild >/dev/null 2>&1
    ( cd "$p" && env "$@" PATH="$bindir:$PATH" STUB_LOG="$o/log" HB_EXEC_CMD=stub HB_EXEC_MAX_ITERS=30 node "$p/.hb/hb-exec.js" run > "$o/out" 2>&1 ); rc=$?
  fi
  python3 - "$o" "$p" "$rt" "$name" "$rc" <<'EOF'
import json, os, sys
o, p, rt, name, rc = sys.argv[1:6]
evs = [json.loads(l) for l in open(os.path.join(p, ".hb", "events.jsonl")) if l.strip()]
keep = ("constraints_recorded", "free_review_recorded", "review_passed", "review_failed", "gate_passed")
seq = [e["event"] for e in evs if e.get("event") in keep]
calls = [l.rstrip("\n").split("\t") for l in open(os.path.join(o, "log")) if l.strip()]
cr = [e for e in evs if e.get("event") == "constraints_recorded"]
rf = [e for e in evs if e.get("event") == "review_failed"]
print(json.dumps({"rt": rt, "name": name, "rc": int(rc), "seq": seq, "calls": calls,
                  "fail_model": rf[-1].get("model") if rf else "NO-FAIL",
                  "author_actor": cr[0].get("actor") if cr else None, "author_model": cr[0].get("model") if cr else None,
                  "fail_note": rf[-1].get("note", "") if rf else "", "out": open(os.path.join(o, "out"), errors="replace").read()[-600:]}))
EOF
  rm -rf "$p"
}
PROF_FULL='{"persona":"CP","author_model":"AM","model":"RM","free_review":true,"free_model":"FM"}'
PROF_NOAUTH='{"persona":"CP","model":"RM"}'
PROF_PANEL='{"persona":"CP","model":"RM","verdict":{"panel":2,"refute_if":"any"}}'
PROF_PANEL_NEG='{"persona":"CP","model":"RM","verdict":{"panel":-1}}'
PROF_PANEL_STR='{"persona":"CP","model":"RM","verdict":{"panel":"2x"}}'
PROF_MODEL_NUM='{"persona":"CP","author_model":5}'
PROF_FREE_NOMODEL='{"persona":"CP","model":"RM","free_review":true}'
PROF_PANEL_BIG='{"persona":"CP","model":"RM","verdict":{"panel":51}}'

obs_file="$work/obs.json"
{ echo '['; first=1
  sep() { [ $first = 1 ] || echo ','; first=0; }
  # only the selftest's own mutant runs may restrict the scenarios (EC_MUTANT_RUN); never the main proof
  want() { [ -z "${EC_MUTANT_RUN:-}" ] || [ -z "${EC_CASES:-}" ] && return 0; case " $EC_CASES " in *" $1 "*) return 0;; esac; return 1; }
  for rt in node py; do
    want happy && sep && run "$rt" happy         "$DAG_C" "$PROF_FULL"   X=1
    want violated && sep && run "$rt" violated      "$DAG_C" "$PROF_FULL"   STUB_VIOLATE=1
    want author-bad && sep && run "$rt" author-bad    "$DAG_C" "$PROF_FULL"   STUB_AUTHOR=bad
    want default-model && sep && run "$rt" default-model "$DAG_C" "$PROF_NOAUTH" HB_REFUTE_MODEL=DEF
    want panel && sep && run "$rt" panel         "$DAG_C" "$PROF_PANEL"  STUB_VIOLATE_PANELIST=2
    want unconstrained && sep && run "$rt" unconstrained "$DAG_U" "$PROF_FULL"   X=1
    # hostile replies / profiles: escalate review_error — never a crash, never a pass, identical in both
    want author-bare && sep && run "$rt" author-bare    "$DAG_C" "$PROF_NOAUTH" STUB_AUTHOR=bare
    want refute-null && sep && run "$rt" refute-null    "$DAG_C" "$PROF_NOAUTH" STUB_REFUTE=null
    want findings-list && sep && run "$rt" findings-list  "$DAG_C" "$PROF_NOAUTH" STUB_REFUTE=list-findings
    want panel-negative && sep && run "$rt" panel-negative "$DAG_C" "$PROF_PANEL_NEG" X=1
    want panel-string && sep && run "$rt" panel-string   "$DAG_C" "$PROF_PANEL_STR" X=1
    want free-refutes && sep && run "$rt" free-refutes "$DAG_C" "$PROF_FREE_NOMODEL" STUB_FREE=refute
    want panel-too-big && sep && run "$rt" panel-too-big "$DAG_C" "$PROF_PANEL_BIG" X=1
    want model-number && sep && run "$rt" model-number   "$DAG_C" "$PROF_MODEL_NUM" X=1
  done; echo ']'; } > "$obs_file"
[ -n "${HB_PROOF_DUMP:-}" ] && cp "$obs_file" "$HB_PROOF_DUMP"

CHECK='
import json, sys, re
def check(obs):
    by = {(o["rt"], o["name"]): o for o in obs}
    for (rt, name), o in by.items():
        k = rt + "/" + name
        modes = [(c[0], c[1]) for c in o["calls"] if c[0] != "execute"]
        models = {(c[0], c[1]): c[2] for c in o["calls"] if c[0] != "execute"}
        if "Traceback" in o["out"] or re.search(r"\n\s+at \S+ \(", o["out"]) or "node:internal" in o["out"]: return k + ": the executor crashed: " + o["out"][-300:]
        if name == "happy":
            if modes != [("author", ""), ("refute", ""), ("refute", "free")]: return k + ": dispatch order wrong: " + str(modes)
            if models != {("author", ""): "AM", ("refute", ""): "RM", ("refute", "free"): "FM"}: return k + ": per-role models not verbatim: " + str(models)
            if o["seq"] != ["gate_passed", "constraints_recorded", "free_review_recorded", "review_passed"]: return k + ": event sequence wrong: " + str(o["seq"])
            if not (o["author_actor"] or "").endswith(":author") or o["author_model"] != "AM": return k + ": author actor/model wrong: " + str((o["author_actor"], o["author_model"]))
            if o["rc"] != 0: return k + ": the run did not complete"
        elif name == "violated":
            if "review_passed" in o["seq"] or "review_failed" not in o["seq"]: return k + ": a VIOLATED answer did not become review_failed: " + str(o["seq"])
            if "VIOLATED" not in o["fail_note"]: return k + ": review_failed lacks the refusal reason: " + o["fail_note"][:200]
            if o["rc"] == 0: return k + ": the run did not stop (escalate) after the refused pass"
        elif name == "author-bad":
            if "constraints_recorded" in o["seq"] or "review_passed" in o["seq"]: return k + ": a malformed author reply was recorded / passed: " + str(o["seq"])
            if o["rc"] == 0 or "review_error" not in o["out"]: return k + ": a malformed author reply did not escalate review_error"
        elif name == "default-model":
            if models.get(("author", "")) != "DEF": return k + ": unset author_model did not fall back to the executor default: " + str(models)
            if ("refute", "free") in models: return k + ": free review dispatched although the profile does not ask for it"
            if o["seq"] != ["gate_passed", "constraints_recorded", "review_passed"]: return k + ": event sequence wrong: " + str(o["seq"])
        elif name == "panel":
            if [m for m in modes if m == ("refute", "")] != [("refute", "")] * 2: return k + ": the panel did not run 2 refuters: " + str(modes)
            if "review_passed" in o["seq"] or "review_failed" not in o["seq"]: return k + ": one VIOLATED panelist did not refuse: " + str(o["seq"])
        elif name == "free-refutes":
            if "review_passed" in o["seq"] or "review_failed" not in o["seq"]: return k + ": a refuting free review did not become review_failed"
            if o["fail_model"] is not None: return k + ": the free reviewer ran with no model but its refusal records " + json.dumps(o["fail_model"])
        elif name in ("author-bare", "refute-null", "findings-list", "panel-negative", "panel-string", "panel-too-big", "model-number"):
            if "review_passed" in o["seq"]: return k + ": a hostile reply/profile led to a PASS"
            if o["rc"] == 0 or "review_error" not in o["out"]: return k + ": a hostile reply/profile did not escalate review_error: " + o["out"][-200:]
        elif name == "unconstrained":
            if modes != [("refute", "")]: return k + ": an unconstrained gate left the old path: " + str(modes)
            if o["seq"] != ["gate_passed", "review_passed"]: return k + ": event sequence wrong: " + str(o["seq"])
    import os
    if not os.environ.get("EC_MUTANT_RUN"):
        expected = {"happy", "violated", "author-bad", "default-model", "panel", "unconstrained", "author-bare", "refute-null",
                    "findings-list", "panel-negative", "panel-string", "model-number", "free-refutes", "panel-too-big"}
        if set(n for _, n in by) != expected: return "scenarios missing from the run: " + str(sorted(expected - set(n for _, n in by)))
    for name in set(n for _, n in by):
        n, p = by.get(("node", name)), by.get(("py", name))
        if not n or not p: return "missing runtime for " + name
        if n["seq"] != p["seq"]: return "parity: event sequence differs for " + name + ": " + str(n["seq"]) + " vs " + str(p["seq"])
        if n.get("fail_model") != p.get("fail_model"): return "parity: review_failed.model differs for " + name + ": " + json.dumps(n.get("fail_model")) + " vs " + json.dumps(p.get("fail_model"))
        if [c[:2] for c in n["calls"]] != [c[:2] for c in p["calls"]]: return "parity: dispatches differ for " + name
    return None
'

if [ "${1:-}" = "--selftest" ]; then
  python3 - "$obs_file" <<EOF || exit 1
$CHECK
import copy
obs = json.load(open(sys.argv[1]))
b = check(obs)
if b: print("FAIL: selftest needs a green baseline; got: " + b, file=sys.stderr); sys.exit(1)
def get(rt, n): return next(o for o in obs if o["rt"] == rt and o["name"] == n)
def m(label, f):
    global obs
    saved = copy.deepcopy(obs); f()
    if check(obs) is None: print("FAIL: selftest: perturbation slipped past: " + label, file=sys.stderr); sys.exit(1)
    obs = saved
m("model substituted",   lambda: get("node", "happy")["calls"][1].__setitem__(2, "default"))
m("violated passed",     lambda: get("py", "violated").__setitem__("seq", ["gate_passed", "constraints_recorded", "free_review_recorded", "review_passed"]))
m("crash",               lambda: get("node", "violated").__setitem__("out", "node:internal/child_process boom"))
m("free skipped",        lambda: get("py", "happy").__setitem__("calls", [c for c in get("py", "happy")["calls"] if c[1] != "free"]))
m("parity drift",        lambda: get("py", "unconstrained").__setitem__("seq", ["gate_passed"]))
EOF
  mutant() { # <label> <file> <old> <new> <expected failure fragment> [<scenarios to run>]
    local m="$work/mut"; rm -rf "$m"; mkdir -p "$m/docs/howto" "$m/py"
    cp -r "$ROOT/plugin" "$m/"; cp -r "$ROOT/py/src" "$m/py/"; cp -r "$ROOT/docs/howto/gate-examples" "$m/docs/howto/"
    python3 -c 'import sys; p, a, b = sys.argv[1:4]; s = open(p).read(); sys.exit(1) if s.count(a) != 1 else open(p, "w").write(s.replace(a, b))' \
      "$m/$2" "$3" "$4" || fail "selftest: mutant '$1' did not apply (the code moved — update the mutant)"
    local out; if out="$(EC_MUTANT_RUN=1 EC_CASES="${6:-}" bash "$m/docs/howto/gate-examples/exec-constrained-review.sh" 2>&1)"; then fail "selftest: mutant '$1' still passes — not load-bearing"; fi
    case "$out" in *"$5"*) ;; *) fail "selftest: mutant '$1' failed for the WRONG reason: $out";; esac
    echo "  mutant caught: $1"
  }
  mutant "node skips the author" plugin/templates/hb-exec.js "  if (!hbjs.reviewCycle(hbjs_dag(), gate).recorded) {" "  if (false) {" \
    "node/happy: dispatch order wrong" "happy"
  mutant "python substitutes the refute model for the author" py/src/heartbeat/executor.py '    models = {"author": (prof.get("author_model") if prof else None) or dflt,' '    models = {"author": (prof.get("model") if prof else None) or dflt,' \
    "py/happy: per-role models not verbatim" "happy"
  mutant "node crashes instead of recording a refusal" plugin/templates/hb-exec.js "  const refuse = (reason, model = models.refute) => {   // a refused review is a recorded failure, never a crash" "  const refuse = (reason, model = models.refute) => { throw new Error('mutant: ' + reason);" \
    "the executor crashed" "violated"
  mutant "python lets a VIOLATED answer through" py/src/heartbeat/executor.py '        errs, _counts = review_policy.check_answers(t, ids)' '        errs = []' \
    "py/panel" "violated panel"
  mutant "node checks only the first panelist" plugin/templates/hb-exec.js "  for (let i = 0; i < texts.length; i++) {" "  for (let i = 0; i < 1; i++) {" \
    "node/panel" "panel"
  mutant "python records a malformed author reply" py/src/heartbeat/executor.py '        if not isinstance(ra, dict) or ra.get("ok") is not True or not isinstance(ra.get("constraints"), list):' '        if False:' \
    "py/author-bad" "author-bad"
  mutant "python trusts a non-dict author reply" py/src/heartbeat/executor.py '        if not isinstance(ra, dict) or ra.get("ok") is not True' '        if ra.get("ok") is not True' \
    "py/author-bare" "author-bare"
  mutant "node reads a string panel with parseInt" plugin/templates/hb-exec.js "    : (typeof pv === 'string' && /^[0-9]+\$/.test(pv) && parseInt(pv, 10) >= 1) ? parseInt(pv, 10) : null;" "    : (typeof pv === 'string' && parseInt(pv, 10) >= 1) ? parseInt(pv, 10) : null;" \
    "node/panel-string" "panel-string"
  mutant "node skips the free review" plugin/templates/hb-exec.js "  if (prof && prof.free_review) {" "  if (false) {" \
    "node/happy" "happy"
  echo "SELFTEST-OK"; exit 0
fi

python3 - "$obs_file" <<EOF || exit 1
$CHECK
bad = check(json.load(open(sys.argv[1])))
if bad: print("FAIL: " + bad, file=sys.stderr); sys.exit(1)
print("exec constrained review: 14 scenarios × 2 executors hold")
print("EXEC-CONSTRAINED-REVIEW-OK")
EOF
