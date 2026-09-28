#!/usr/bin/env bash
# Proof: the CONSTRAINED refute prompt. For a constrained gate, `hb refute-prompt <gate>` — with or
# without a review profile — is the unchanged compose followed by a block carrying the phase's
# `hb changed` list, every constraint id exactly once in stable order (plan-time P ids, then the
# gate-time G ids recorded in THIS review cycle), the per-id answer format
#   <ID>: VIOLATED | NOT-REPRODUCED | N/A — <evidence or reason>
# and the triage rule "an exploitable side finding means REFUTED, whatever the scope". A recorded set
# whose bytes no longer match its event is refused (fail closed), and a set from an EARLIER cycle is
# never used. `refute-prompt <gate> --free` composes the unconstrained breadth review (the same
# compose + the change list + the free-review instructions, WITHOUT the constraint block); --free on an
# unconstrained gate is refused. An unconstrained gate's prompt is untouched (golden fixtures).
# Profiles accept author_model / free_model (strings, verbatim) and free_review (bool) in JSON and
# SKILL format; SKILL 'false'/'no'/'0'/'off' → false, identically in both runtimes; `--json` exposes
# model, author_model, free_review, free_model. node ≡ python byte-for-byte on every prompt.
# Prints CONSTRAINED-REFUTE-OK. `--selftest`: perturbed observations + reason-checked mutants.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
unset HB_DIR DAG_FILE EVENTS_FILE HB_ACTOR HB_REFUTER 2>/dev/null || true
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
fail() { echo "FAIL: $*" >&2; exit 1; }
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
hbpy() { python3 -m heartbeat.cli "$@"; }

# G0: constrained + profile; G1: constrained, NO profile; G2: unconstrained + profile
DAG='{"phases":[
 {"id":"P0","title":"p0","gate_entry":null,"gate_exit":"G0","tasks":[{"id":"t0","title":"w0"}]},
 {"id":"P1","title":"p1","gate_entry":"G0","gate_exit":"G1","tasks":[{"id":"t1","title":"w1"}]},
 {"id":"P2","title":"p2","gate_entry":"G1","gate_exit":"G2","tasks":[{"id":"t2","title":"w2"}]}],
 "gates":{
 "G0":{"desc":"g0","review":{"prompt":"REVIEW-G0","profile":"prof","constraints":[
   {"id":"P2","claim":"CL-P2","subjects":["a.txt"],"violation":"V-P2"},
   {"id":"P1","claim":"CL-P1","subjects":["a.txt"],"violation":"V-P1"}]},
   "criteria":[{"id":"c","cmd":"grep -q 2 \"$PROJECT_DIR/a.txt\""}]},
 "G1":{"desc":"g1","review":{"prompt":"REVIEW-G1","constraints":[{"id":"P1","claim":"CL-Q1","subjects":["a.txt"],"violation":"V-Q1"}]},
   "criteria":[{"id":"c","cmd":"grep -q 2 \"$PROJECT_DIR/a.txt\""}]},
 "G2":{"desc":"g2","review":{"prompt":"REVIEW-G2","profile":"prof"},"criteria":[{"id":"c","cmd":"grep -q 2 \"$PROJECT_DIR/a.txt\""}]}}}'
G='[{"id":"G1","claim":"CL-G1","subjects":["a.txt"],"violation":"V-G1"},{"id":"G2","claim":"CL-G2","subjects":["n.txt"],"violation":"V-G2"}]'

hb() { local rt="$1" p="$2"; shift 2
  if [ "$rt" = py ]; then hbpy "$@" --dir "$p"; else
    case "$1" in gate) shift; bash "$p/.hb/gate.sh" "$@";; *) node "$p/.hb/hb.js" "$@";; esac; fi; }

scenario() { # <rt> → JSON observations
  local rt="$1" p o; p="$(mktemp -d "$work/p.XXXX")"; o="$work/o.$rt"; mkdir -p "$o"
  printf '1\n' > "$p/a.txt"; printf 'same\n' > "$p/k.txt"
  if [ "$rt" = py ]; then hbpy init "$p" >/dev/null 2>&1; else bash "$ROOT/plugin/bootstrap.sh" "$p" --no-git >/dev/null 2>&1 </dev/null; fi
  printf '%s' "$DAG" > "$p/.hb/dag.json"; mkdir -p "$p/.hb/refuters"
  printf '%s' '{"persona":"PERSONA-MARK","questions":["Q-EXTRA"],"model":"RM","author_model":"AM","free_review":true,"free_model":"FM"}' > "$p/.hb/refuters/prof.json"
  hb "$rt" "$p" rebuild >/dev/null 2>&1
  HB_ACTOR=doer hb "$rt" "$p" start t0 >/dev/null 2>&1; printf '2\n' > "$p/a.txt"; printf 'n\n' > "$p/n.txt"
  HB_ACTOR=doer hb "$rt" "$p" done t0 >/dev/null 2>&1
  hb "$rt" "$p" refute-prompt G0 > "$o/g0_plan.txt" 2>&1                    # before any gate-time set
  hb "$rt" "$p" gate G0 >/dev/null 2>&1
  printf '%s' "$G" > "$o/g.json"; HB_ACTOR=author hb "$rt" "$p" constraints G0 --record "$o/g.json" >/dev/null 2>&1
  hb "$rt" "$p" refute-prompt G0 > "$o/g0_full.txt" 2>&1
  hb "$rt" "$p" refute-prompt G0 --json > "$o/g0.json" 2>&1
  hb "$rt" "$p" refute-prompt G0 --free > "$o/g0_free.txt" 2>&1; echo $? > "$o/g0_free.rc"
  hb "$rt" "$p" refute-prompt G2 > "$o/g2.txt" 2>&1
  hb "$rt" "$p" refute-prompt G2 --free > /dev/null 2>&1; echo $? > "$o/g2_free.rc"
  # tampered recorded set → refused (fail closed)
  cp "$p/.hb/constraints/G0.json" "$o/keep.json"; printf '[]' > "$p/.hb/constraints/G0.json"
  hb "$rt" "$p" refute-prompt G0 > /dev/null 2>&1; echo $? > "$o/tampered.rc"; cp "$o/keep.json" "$p/.hb/constraints/G0.json"
  # a NEW cycle (review fail → re-pass) does not reuse the old gate-time set
  HB_ACTOR=refuter hb "$rt" "$p" review G0 fail "hole" >/dev/null 2>&1; hb "$rt" "$p" gate G0 >/dev/null 2>&1
  hb "$rt" "$p" refute-prompt G0 > "$o/g0_newcycle.txt" 2>&1
  # G1: constrained, no profile
  printf 'x\n' > "$p/.hb/r.md"
  HB_ACTOR=author hb "$rt" "$p" constraints G0 --record "$o/g.json" >/dev/null 2>&1
  printf 'Refutation of P0 / t0 / G0: a.txt checked, could not refute.\nP1: NOT-REPRODUCED — probe\nP2: NOT-REPRODUCED — probe\nG1: NOT-REPRODUCED — probe\nG2: NOT-REPRODUCED — probe\n' > "$p/rev.md"
  HB_ACTOR=refuter hb "$rt" "$p" review G0 pass --artifact rev.md >/dev/null 2>&1
  HB_ACTOR=doer hb "$rt" "$p" start t1 >/dev/null 2>&1; HB_ACTOR=doer hb "$rt" "$p" done t1 >/dev/null 2>&1
  hb "$rt" "$p" refute-prompt G1 > "$o/g1.txt" 2>&1
  # profile field coercion: SKILL format strings
  mkdir -p "$p/.hb/refuters/sk"; rm -f "$p/.hb/refuters/prof.json"
  printf -- '---\nname: prof\nmodel: RM2\nauthor_model: AM2\nfree_review: false\nfree_model: FM2\n---\nPERSONA-MARK\n\n## Checklist\n- Q-EXTRA\n' > "$p/.hb/refuters/prof.md"
  hb "$rt" "$p" refute-prompt G2 --json > "$o/skill_false.json" 2>&1
  sed -i.bak 's/free_review: false/free_review: yes/' "$p/.hb/refuters/prof.md"
  hb "$rt" "$p" refute-prompt G2 --json > "$o/skill_yes.json" 2>&1
  sed -i.bak 's/free_review: yes/free_review: 0/' "$p/.hb/refuters/prof.md"
  hb "$rt" "$p" refute-prompt G2 --json > "$o/skill_zero.json" 2>&1
  python3 - "$o" "$rt" <<'EOF'
import json, os, sys
o, rt = sys.argv[1:3]
rd = lambda n: open(os.path.join(o, n), encoding="utf-8", errors="replace").read() if os.path.exists(os.path.join(o, n)) else None
def js(n):
    try: return json.loads(rd(n))
    except Exception: return None
print(json.dumps({"rt": rt, "g0_plan": rd("g0_plan.txt"), "g0_full": rd("g0_full.txt"), "g0_json": js("g0.json"),
                  "g0_free": rd("g0_free.txt"), "g0_free_rc": rd("g0_free.rc").strip(), "g2": rd("g2.txt"),
                  "g2_free_rc": rd("g2_free.rc").strip(), "tampered_rc": rd("tampered.rc").strip(),
                  "g0_newcycle": rd("g0_newcycle.txt"), "g1": rd("g1.txt"),
                  "skill_false": js("skill_false.json"), "skill_yes": js("skill_yes.json"), "skill_zero": js("skill_zero.json")}))
EOF
  rm -rf "$p"
}

CHECK='
import json, sys, re
FMT = "<ID>: VIOLATED | NOT-REPRODUCED | N/A — <evidence or reason>"
TRIAGE = "an exploitable side finding means refuted, whatever the scope"   # compared case-insensitively
def ids_in_order(text, ids):
    pos = []
    for i in ids:
        hits = [m.start() for m in re.finditer(r"(?m)^  - " + i + r": ", text)]
        if len(hits) != 1: return None
        pos.append(hits[0])
    return pos == sorted(pos)
def check(obs):
    by = {o["rt"]: o for o in obs}
    for rt, o in by.items():
        k = rt
        full, plan = o["g0_full"] or "", o["g0_plan"] or ""
        for t, name in ((plan, "plan-only"), (full, "with gate-time set")):
            if "PERSONA-MARK" not in t or "Q-EXTRA" not in t or "REVIEW-G0" not in t: return k + ": " + name + " prompt lost the base compose"
            if FMT not in t: return k + ": " + name + " prompt lacks the per-id answer format"
            if TRIAGE not in t.lower(): return k + ": " + name + " prompt lacks the triage rule"
            if "M a.txt" not in t or "A n.txt" not in t: return k + ": " + name + " prompt lacks the hb changed list"
            if "k.txt" in t: return k + ": " + name + " prompt lists an unchanged file"
        if not ids_in_order(plan, ["P1", "P2"]) or "CL-G1" in plan: return k + ": plan-only prompt: ids not exactly P1,P2 in stable order"
        if not ids_in_order(full, ["P1", "P2", "G1", "G2"]): return k + ": prompt does not list P1,P2,G1,G2 exactly once, in order"
        if not full.startswith(plan.split("\n\n## What this phase changed")[0]): return k + ": the constrained prompt does not START with the unchanged compose"
        nc = o["g0_newcycle"] or ""
        if "CL-G1" in nc or not ids_in_order(nc, ["P1", "P2"]): return k + ": a new review cycle reused the previous cycle gate-time set"
        if o["tampered_rc"] == "0": return k + ": a tampered recorded set was used instead of refused"
        fr = o["g0_free"] or ""
        if o["g0_free_rc"] != "0": return k + ": --free failed on a constrained gate"
        if "PERSONA-MARK" not in fr or "M a.txt" not in fr or TRIAGE not in fr.lower(): return k + ": --free lacks persona / change list / triage rule"
        if FMT in fr or "CL-P1" in fr or "CL-G1" in fr: return k + ": --free carries the constraint block"
        if o["g2_free_rc"] == "0": return k + ": --free accepted an unconstrained gate"
        if FMT in (o["g2"] or "") or TRIAGE in (o["g2"] or "").lower(): return k + ": an unconstrained gate got the constraint block"
        g1 = o["g1"] or ""
        if not g1.startswith("REVIEW-G1") or FMT not in g1 or not ids_in_order(g1, ["P1"]): return k + ": a constrained gate WITHOUT a profile lacks the block"
        j = o["g0_json"]
        if not isinstance(j, dict): return k + ": refute-prompt --json unparseable"
        if (j.get("model"), j.get("author_model"), j.get("free_review"), j.get("free_model")) != ("RM", "AM", True, "FM"):
            return k + ": --json profile fields not verbatim: " + json.dumps({x: j.get(x) for x in ("model", "author_model", "free_review", "free_model")})
        if j.get("prompt") != full.rstrip("\n"): return k + ": --json prompt is not the text prompt"
        for n, want in (("skill_false", False), ("skill_yes", True), ("skill_zero", False)):
            s = o[n]
            if not isinstance(s, dict) or s.get("free_review") is not want: return k + ": SKILL free_review coercion wrong for " + n + ": " + json.dumps(s and s.get("free_review"))
        if (o["skill_false"] or {}).get("author_model") != "AM2" or (o["skill_false"] or {}).get("free_model") != "FM2": return k + ": SKILL author_model/free_model not verbatim"
    n, p = by.get("node"), by.get("py")
    if not n or not p: return "missing runtime"
    for f in ("g0_plan", "g0_full", "g0_free", "g0_newcycle", "g1", "g2"):
        if n[f] != p[f]: return "parity: " + f + " differs node vs python"
    for f in ("g0_json", "skill_false", "skill_yes", "skill_zero"):
        if n[f] != p[f]: return "parity: " + f + " --json differs node vs python"
    return None
'

obs_file="$work/obs.json"
{ echo '['; scenario node; echo ','; scenario py; echo ']'; } > "$obs_file"
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
m("an id listed twice",       lambda: get("node").__setitem__("g0_full", get("node")["g0_full"] + "\n  - P1: again"))
m("free carries constraints", lambda: get("py").__setitem__("g0_free", get("py")["g0_free"] + "\n  CL-P1"))
m("triage rule missing",      lambda: get("node").__setitem__("g0_plan", get("node")["g0_plan"].replace("whatever the scope", "")))
m("bool coerced wrong",       lambda: get("py")["skill_false"].__setitem__("free_review", True))
m("model substituted",        lambda: get("node")["g0_json"].__setitem__("free_model", "default"))
m("old cycle reused",         lambda: get("py").__setitem__("g0_newcycle", get("py")["g0_full"]))
m("unconstrained changed",    lambda: get("node").__setitem__("g2", get("node")["g2"] + "\n<ID>: VIOLATED | NOT-REPRODUCED | N/A — <evidence or reason>"))
EOF
  mutant() { # <label> <file> <old> <new> <expected failure fragment>
    local m="$work/mut"; rm -rf "$m"; mkdir -p "$m/docs/howto" "$m/py"
    cp -r "$ROOT/plugin" "$m/"; cp -r "$ROOT/py/src" "$m/py/"; cp -r "$ROOT/docs/howto/gate-examples" "$m/docs/howto/"
    python3 -c 'import sys; p, a, b = sys.argv[1:4]; s = open(p).read(); sys.exit(1) if s.count(a) != 1 else open(p, "w").write(s.replace(a, b))' \
      "$m/$2" "$3" "$4" || fail "selftest: mutant '$1' did not apply (the code moved — update the mutant)"
    local out; if out="$(bash "$m/docs/howto/gate-examples/constrained-refute.sh" 2>&1)"; then fail "selftest: mutant '$1' still passes — not load-bearing"; fi
    case "$out" in *"$5"*) ;; *) fail "selftest: mutant '$1' failed for the WRONG reason: $out";; esac
    echo "  mutant caught: $1"
  }
  mutant "node leaves out the gate-time set" plugin/templates/refuter_profiles.js "  const all = cs.slice().sort(byId).concat(hbjs.recordedConstraints(gate).slice().sort(byId));" "  const all = cs.slice().sort(byId);" \
    "node: prompt does not list P1,P2,G1,G2"
  mutant "python unsorted plan ids" py/src/heartbeat/refuter_profiles.py '    allc = sorted(cs, key=by_id) + sorted(cons.recorded_constraints(hbdir, dag, gate), key=by_id)' '    allc = list(cs) + sorted(cons.recorded_constraints(hbdir, dag, gate), key=by_id)' \
    "py: plan-only prompt: ids not exactly P1,P2 in stable order"
  mutant "node free review keeps the constraints" plugin/templates/refuter_profiles.js '  if (free) {
    parts.push("## Free review' '  if (false) {
    parts.push("## Free review' \
    "node: --free carries the constraint block"
  mutant "python ignores the tampered set" py/src/heartbeat/constraints.py '    if hashlib.sha256(raw).hexdigest() != ev.get("sha256"):
        raise ValueError(f"the recorded constraints of {gate} changed' '    if False:
        raise ValueError(f"the recorded constraints of {gate} changed' \
    "py: a tampered recorded set was used"
  mutant "python reads SKILL false as true" py/src/heartbeat/refuter_profiles.py '        "free_review": _to_bool(d.get("free_review")),' '        "free_review": bool(d.get("free_review")),' \
    "py: SKILL free_review coercion wrong for skill_false"
  mutant "node constrains an unconstrained gate" plugin/templates/refuter_profiles.js "  const constrained = Array.isArray(cs) && cs.length > 0;" "  const constrained = true;" \
    "unconstrained gate"
  mutant "python drops a profile field from --json" py/src/heartbeat/cli.py '                                  "free_model": prof.get("free_model")}))' '                                  }))' \
    "py: --json profile fields not verbatim"
  echo "SELFTEST-OK"; exit 0
fi

python3 - "$obs_file" <<EOF || exit 1
$CHECK
bad = check(json.load(open(sys.argv[1])))
if bad: print("FAIL: " + bad, file=sys.stderr); sys.exit(1)
print("constrained refute: plan-only / full / free / new cycle / no-profile / unconstrained / coercion × 2 runtimes hold")
print("CONSTRAINED-REFUTE-OK")
EOF
