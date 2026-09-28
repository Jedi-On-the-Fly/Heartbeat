#!/usr/bin/env bash
# Proof: restore points fail LOUDLY. At gate acceptance (a review-less pass, or `review pass`), a
# failed git commit or tag is reported on stderr and recorded as a restore_point_failed
# {gate, step, error} event — never swallowed. 'Nothing to commit' is not a failure;
# HB_NO_GIT=1 / HB_GIT_AUTOCOMMIT=0 / no repo skip git quietly (the acceptance anchor is still
# written). The acceptance event records the git policy in force as git:{autocommit:bool}.
# A failed add/commit SKIPS the tag (a tag on the pre-phase HEAD would make `git reset --hard <GATE>`
# silently discard the phase's work). `hb doctor` flags a gate whose LAST acceptance is followed by a
# restore_point_failed, and a gate accepted after anchors existed (a _start anchor is present) that has no
# acceptance anchor, and — when its recorded policy was autocommit-on — no tag; it never flags a
# pending gate or a project whose history predates anchors (no _start), and never reports a missing
# tag when git itself is absent from PATH (tag state unknown). Both runtimes; the doctor
# lines are identical node ≡ python. Prints RESTORE-POINTS-OK.
# `--selftest` (1) perturbs the real observations and proves the checker rejects each, and (2) runs
# this proof against MUTANT copies of the real code (a swallowed tag failure, a missing policy
# field, doctor's anchor check removed) — each must go RED. Prints SELFTEST-OK.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
unset HB_DIR DAG_FILE EVENTS_FILE HB_ACTOR HB_NO_GIT HB_GIT_AUTOCOMMIT 2>/dev/null || true
[ -n "${RP_MUTANT_RUN:-}" ] || unset RP_CASES
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
command -v git     >/dev/null 2>&1 || { echo "git absent";     exit 1; }
[ "$(id -u)" != 0 ] || { echo "run as a non-root user (the failure cases rely on file permissions)"; exit 1; }
fail() { echo "FAIL: $*" >&2; exit 1; }

export PYTHONPATH="$ROOT/py/src" STUCK_TICKS=999 HB_ROT_CHECK=0
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
work="$(mktemp -d)"; trap 'chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"' EXIT
hbpy() { python3 -m heartbeat.cli "$@"; }

DAG='{"phases":[
 {"id":"P0","title":"p0","gate_entry":null,"gate_exit":"G0","tasks":[{"id":"T1","title":"t1"}]},
 {"id":"P1","title":"p1","gate_entry":"G0","gate_exit":"G1","tasks":[{"id":"T2","title":"t2"}]}],
 "gates":{
 "G0":{"desc":"g0","criteria":[{"id":"c","cmd":"test -s \"$PROJECT_DIR/a.txt\""}]},
 "G1":{"desc":"g1","review":{"prompt":"refute P1"},"criteria":[{"id":"c","cmd":"test -s \"$PROJECT_DIR/a.txt\""}]}}}'

hb() {
  local rt="$1" p="$2"; shift 2
  if [ "$rt" = py ]; then hbpy "$@" --dir "$p"; else
    case "$1" in gate) shift; bash "$p/.hb/gate.sh" "$@";; *) node "$p/.hb/hb.js" "$@";; esac
  fi
}
# mkproject <rt> <git|nogit> [ignore-hb] → path (HeartBeat installed, base committed when git)
mkproject() {
  local rt="$1" mode="$2" ign="${3:-}" p; p="$(mktemp -d "$work/p.XXXX")"
  printf 'alpha\n' > "$p/a.txt"
  if [ "$rt" = py ]; then HB_NO_GIT=1 hbpy init "$p" >/dev/null 2>&1; else bash "$ROOT/plugin/bootstrap.sh" "$p" --no-git >/dev/null 2>&1 </dev/null; fi
  printf '%s' "$DAG" > "$p/.hb/dag.json"
  hb "$rt" "$p" rebuild >/dev/null 2>&1
  if [ "$mode" = git ]; then
    [ -n "$ign" ] && printf '.hb/\n' > "$p/.gitignore"
    git -C "$p" init -q && git -C "$p" add -A && git -C "$p" commit -qm base
  fi
  printf '%s' "$p"
}
# accept <rt> <p> <G0|G1> → runs the phase and accepts its gate; stderr of the ACCEPTING step on stdout
accept() {
  local rt="$1" p="$2" g="$3" t=T1; [ "$g" = G1 ] && t=T2
  HB_ACTOR=doer hb "$rt" "$p" start "$t" >/dev/null 2>&1; HB_ACTOR=doer hb "$rt" "$p" done "$t" >/dev/null 2>&1
  if [ "$g" = G0 ]; then hb "$rt" "$p" gate G0 2>&1 >/dev/null; return; fi
  hb "$rt" "$p" gate G1 >/dev/null 2>&1
  printf 'Refutation attempt on P1 / T2: a.txt is non-empty; could not refute G1.\n' > "$p/.rev.md"
  HB_ACTOR=refuter hb "$rt" "$p" review G1 pass --artifact .rev.md 2>&1 >/dev/null
}
events() { python3 -c '
import json, sys
evs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
print(json.dumps([{k: e.get(k) for k in ("event", "gate", "step", "git")} for e in evs
                  if e.get("event") in ("gate_passed", "review_passed", "restore_point_failed")]))' "$1/.hb/events.jsonl"; }
doctor_lines() { hb "$1" "$2" doctor 2>&1 | grep -E 'no acceptance anchor|no git tag|restore point failed' | sed 's/^ *//' ; }

# case <rt> <name> → one JSON observation {name, rt, stderr, events, anchor, doctor[]}
obs_case() {
  local rt="$1" name="$2" p err="" env=()
  case "$name" in
    tag-fail|commit-fail|nothing-to-commit|clean|review-tag-fail|review-commit-fail|reaccept-tag-fail|unreadable-file|upgraded-commit-fail|doctor-*) p="$(mkproject "$rt" git "$([ "$name" = nothing-to-commit ] && echo ign)")";;
    no-repo) p="$(mkproject "$rt" nogit)";;
    no-git-env|autocommit-off) p="$(mkproject "$rt" git)";;
  esac
  case "$name" in
    no-git-env) export HB_NO_GIT=1;; autocommit-off) export HB_GIT_AUTOCOMMIT=0;;
  esac
  case "$name" in
    tag-fail) chmod a-w "$p/.git/refs/tags";;          # `git tag -f G0` cannot create its ref lock
    commit-fail) git -C "$p" config commit.gpgsign true; git -C "$p" config gpg.program false;;   # the commit itself fails
    upgraded-commit-fail) git -C "$p" config commit.gpgsign true; git -C "$p" config gpg.program false;;   # + no _start (below)
    unreadable-file) printf 's\n' > "$p/secret.txt"; chmod 000 "$p/secret.txt";;   # git add fails; the anchor must still be written
  esac
  case "$name" in
    review-tag-fail) accept "$rt" "$p" G0 >/dev/null; chmod a-w "$p/.git/refs/tags"; err="$(accept "$rt" "$p" G1)";;
    review-commit-fail) accept "$rt" "$p" G0 >/dev/null; git -C "$p" config commit.gpgsign true; git -C "$p" config gpg.program false
      err="$(accept "$rt" "$p" G1)";;
    reaccept-tag-fail) accept "$rt" "$p" G0 >/dev/null; printf 'more\n' >> "$p/a.txt"; git -C "$p" tag -d G0 >/dev/null 2>&1
      chmod a-w "$p/.git/refs/tags"; err="$(hb "$rt" "$p" gate G0 2>&1 >/dev/null)";;   # the LAST acceptance's restore point fails
    upgraded-commit-fail) # a project upgraded mid-plan: its log predates anchors, so there is no _start
      HB_ACTOR=doer hb "$rt" "$p" start T1 >/dev/null 2>&1; rm -f "$p/.hb/anchors/_start.json"
      err="$(accept "$rt" "$p" G0)";;
    *) err="$(accept "$rt" "$p" G0)";;
  esac
  local anc=false; [ -f "$p/.hb/anchors/G0.json" ] && anc=true
  chmod u+w "$p/.git/refs/tags" 2>/dev/null || true
  local tagged=false; git -C "$p" rev-parse -q --verify refs/tags/G0 >/dev/null 2>&1 && tagged=true
  local tagged1=false; git -C "$p" rev-parse -q --verify refs/tags/G1 >/dev/null 2>&1 && tagged1=true
  local dl=""
  case "$name" in
    clean|tag-fail|commit-fail|review-tag-fail|review-commit-fail|reaccept-tag-fail|unreadable-file|upgraded-commit-fail) dl="$(doctor_lines "$rt" "$p")";;
    doctor-no-git-on-path) git -C "$p" tag -d G0 >/dev/null 2>&1
      local nb="$work/nogitbin"; mkdir -p "$nb"; ln -sf "$(command -v node)" "$nb/node"; ln -sf "$(command -v python3)" "$nb/python3"
      ln -sf "$(command -v bash)" "$nb/bash"
      dl="$(PATH="$nb" hb "$rt" "$p" doctor 2>&1 | grep -E 'no acceptance anchor|no git tag|restore point failed|hb doctor:' | sed 's/^ *//')";;
    doctor-no-anchor) rm -f "$p/.hb/anchors/G0.json"; dl="$(doctor_lines "$rt" "$p")";;
    doctor-no-tag) git -C "$p" tag -d G0 >/dev/null 2>&1; dl="$(doctor_lines "$rt" "$p")";;
    doctor-legacy) # a pre-anchor history: no anchors, no tag, and events WITHOUT the git policy field
      rm -f "$p/.hb/anchors/_start.json" "$p/.hb/anchors/G0.json"; git -C "$p" tag -d G0 >/dev/null 2>&1
      python3 -c 'import json,sys;p=sys.argv[1];evs=[json.loads(l) for l in open(p) if l.strip()];[e.pop("git",None) for e in evs];open(p,"w").write("".join(json.dumps(e)+"\n" for e in evs))' "$p/.hb/events.jsonl"
      dl="$(doctor_lines "$rt" "$p")";;
    doctor-pending) HB_ACTOR=doer hb "$rt" "$p" start T2 >/dev/null 2>&1; HB_ACTOR=doer hb "$rt" "$p" done T2 >/dev/null 2>&1
      hb "$rt" "$p" gate G1 >/dev/null 2>&1; dl="$(doctor_lines "$rt" "$p")";;
    autocommit-off) dl="$(doctor_lines "$rt" "$p")";;
  esac
  unset HB_NO_GIT HB_GIT_AUTOCOMMIT
  chmod u+w "$p/.git/refs/tags" 2>/dev/null || true
  python3 - "$name" "$rt" "$err" "$(events "$p")" "$anc" "$dl" "$tagged" "$tagged1" <<'EOF'
import json, sys
name, rt, err, evs, anc, dl, tagged, tagged1 = sys.argv[1:9]
print(json.dumps({"name": name, "rt": rt, "stderr": err, "events": json.loads(evs), "anchor": anc == "true", "tagged": tagged == "true", "tagged1": tagged1 == "true",
                  "doctor": [l for l in dl.splitlines() if l.strip()]}))
EOF
  chmod -R u+rw "$p" 2>/dev/null; rm -rf "$p"
}

NAMES="tag-fail commit-fail nothing-to-commit no-repo no-git-env autocommit-off review-tag-fail review-commit-fail reaccept-tag-fail unreadable-file upgraded-commit-fail clean doctor-no-anchor doctor-no-tag doctor-legacy doctor-pending doctor-no-git-on-path"

CHECK='
import json, sys
def check(all_obs):
    by = {(o["rt"], o["name"]): o for o in all_obs}
    for (rt, name), o in by.items():
        k = rt + "/" + name
        ev = o["events"]
        rpf = [e for e in ev if e["event"] == "restore_point_failed"]
        acc = [e for e in ev if (e["event"] == "gate_passed" and e["gate"] == "G0") or e["event"] == "review_passed"]
        if not acc: return k + ": no acceptance event"
        pol = acc[-1].get("git")
        if name == "doctor-legacy":   # its events were rewritten to the pre-1.32 shape (no policy field)
            if pol is not None: return k + ": legacy fixture still carries a policy field"
            pol = {"autocommit": True}
        if not isinstance(pol, dict) or not isinstance(pol.get("autocommit"), bool): return k + ": acceptance event has no git:{autocommit:bool}"
        want_pol = name not in ("no-repo", "no-git-env", "autocommit-off")
        if pol["autocommit"] != want_pol: return k + ": recorded autocommit=" + str(pol["autocommit"]) + ", expected " + str(want_pol)
        if not o["anchor"] and not name.startswith("doctor-"): return k + ": acceptance anchor missing"
        if name == "tag-fail":
            if not any(e["step"] == "tag" and e["gate"] == "G0" for e in rpf): return k + ": tag failure not recorded as restore_point_failed(step=tag)"
            if "restore point" not in o["stderr"] or "tag" not in o["stderr"]: return k + ": tag failure not reported on stderr"
        elif name == "commit-fail":
            if not any(e["step"] == "commit" and e["gate"] == "G0" for e in rpf): return k + ": commit failure not recorded as restore_point_failed(step=commit)"
            if "restore point" not in o["stderr"] or "commit" not in o["stderr"]: return k + ": commit failure not reported on stderr"
            if o["tagged"]: return k + ": tagged the PRE-phase HEAD after a failed commit (git reset --hard G0 would discard the phase)"
            if any(e["step"] == "tag" for e in rpf): return k + ": tag attempted after a failed commit"
        elif name == "review-commit-fail":
            if not any(e["step"] == "commit" and e["gate"] == "G1" for e in rpf): return k + ": review-pass commit failure not recorded"
            if o["tagged1"]: return k + ": review pass tagged the PRE-phase HEAD after a failed commit"
            if not any("G1" in l and "restore point failed" in l for l in o["doctor"]): return k + ": doctor missed the failed review-pass commit"
        elif name == "upgraded-commit-fail":
            if not any("G0" in l and "restore point failed" in l for l in o["doctor"]): return k + ": doctor hid a new restore failure because the log predates anchors"
        elif name == "unreadable-file":
            if not any(e["step"] == "add" and e["gate"] == "G0" for e in rpf): return k + ": the failed git add was not recorded"
            if not any("G0" in l and "restore point failed" in l for l in o["doctor"]): return k + ": doctor missed the failed add (an unreadable file must not disable doctor)"
        elif name == "reaccept-tag-fail":
            if not any(e["step"] == "tag" and e["gate"] == "G0" for e in rpf): return k + ": the re-acceptance tag failure not recorded"
        elif name == "review-tag-fail":
            if not any(e["step"] == "tag" and e["gate"] == "G1" for e in rpf): return k + ": review-pass tag failure not recorded"
            if "restore point" not in o["stderr"]: return k + ": review-pass tag failure not reported on stderr"
        else:
            if rpf: return k + ": spurious restore_point_failed " + json.dumps(rpf)
            if "restore point" in o["stderr"]: return k + ": spurious restore-point report on stderr"
        d = o["doctor"]
        if name == "doctor-no-anchor" and not any("G0" in l and "no acceptance anchor" in l for l in d): return k + ": doctor missed the accepted gate without an anchor"
        if name == "doctor-no-tag" and not any("G0" in l and "no git tag" in l for l in d): return k + ": doctor missed the accepted gate without a tag"
        if name in ("tag-fail", "commit-fail", "reaccept-tag-fail") and not any("G0" in l and "restore point failed" in l for l in d):
            return k + ": doctor missed the failed restore point of the LAST acceptance: " + str(d)
        if name == "review-tag-fail" and not any("G1" in l and "restore point failed" in l for l in d): return k + ": doctor missed the failed review-pass restore point"
        if name == "doctor-no-git-on-path":
            if not any("hb doctor:" in l for l in d): return k + ": doctor did not run to its verdict with git absent from PATH: " + str(d)
            if any("no git tag" in l for l in d): return k + ": doctor claimed a missing tag with git absent from PATH"
            d = [l for l in d if "hb doctor:" not in l]
        if name in ("clean", "doctor-legacy", "doctor-pending", "autocommit-off", "doctor-no-git-on-path") and d: return k + ": doctor flagged a healthy/legacy/pending/opted-out project: " + str(d)
    for name in set(n for _, n in by):
        n, p = by.get(("node", name)), by.get(("py", name))
        if not n or not p: return "missing runtime for " + name
        if n["doctor"] != p["doctor"]: return "parity: doctor lines differ for " + name + ": " + str(n["doctor"]) + " vs " + str(p["doctor"])
        if [(e["event"], e["gate"], e["step"]) for e in n["events"]] != [(e["event"], e["gate"], e["step"]) for e in p["events"]]:
            return "parity: event sequence differs for " + name
    return None
'

# Only the selftest's own mutant runs may restrict the cases (RP_MUTANT_RUN is set by mutant());
# an inherited RP_CASES can never shrink the main proof.
[ -n "${RP_MUTANT_RUN:-}" ] && NAMES="${RP_CASES:-$NAMES}"
NCASES=$(set -- $NAMES; echo $#)
obs_file="$work/all.json"
{ echo '['; first=1
  for rt in node py; do for nm in $NAMES; do [ $first = 1 ] || echo ','; first=0; obs_case "$rt" "$nm"; done; done
  echo ']'; } > "$obs_file"

[ -n "${HB_PROOF_DUMP:-}" ] && cp "$obs_file" "$HB_PROOF_DUMP"   # debugging aid: keep the raw observations

if [ "${1:-}" = "--selftest" ]; then
  python3 - "$obs_file" <<EOF || exit 1
$CHECK
import copy
obs = json.load(open(sys.argv[1]))
b = check(obs)
if b is not None: print("FAIL: selftest needs a green baseline; got: " + b, file=sys.stderr); sys.exit(1)
def find(rt, name): return next(o for o in obs if o["rt"] == rt and o["name"] == name)
def m(label, f):
    global obs
    saved = copy.deepcopy(obs); f()
    if check(obs) is None: print("FAIL: selftest: perturbation slipped past: " + label, file=sys.stderr); sys.exit(1)
    obs = saved
m("swallowed tag failure",   lambda: find("node", "tag-fail").__setitem__("events", [e for e in find("node", "tag-fail")["events"] if e["event"] != "restore_point_failed"]))
m("silent commit failure",   lambda: find("py", "commit-fail").__setitem__("stderr", ""))
m("nothing-to-commit noisy", lambda: find("node", "nothing-to-commit")["events"].append({"event": "restore_point_failed", "gate": "G0", "step": "commit", "git": None}))
m("policy missing",          lambda: [e.pop("git", None) for e in find("py", "clean")["events"]])
m("policy wrong",            lambda: [e.__setitem__("git", {"autocommit": True}) for e in find("node", "autocommit-off")["events"] if e.get("git")])
m("doctor misses anchor",    lambda: find("node", "doctor-no-anchor").__setitem__("doctor", []))
m("doctor flags legacy",     lambda: find("py", "doctor-legacy")["doctor"].append("G0 accepted but has no acceptance anchor"))
m("doctor parity drift",     lambda: find("py", "doctor-no-tag").__setitem__("doctor", find("py", "doctor-no-tag")["doctor"] + ["extra"]))
EOF
  # mutant <label> <file> <old> <new> <cases> <expected failure fragment>: the proof, restricted to the
  # cases the mutation concerns (speed), must go RED — and for the EXPECTED reason (never vacuously).
  mutant() {
    local m="$work/mut"; rm -rf "$m"; mkdir -p "$m/docs/howto" "$m/py"
    cp -r "$ROOT/plugin" "$m/"; cp -r "$ROOT/py/src" "$m/py/"; cp -r "$ROOT/docs/howto/gate-examples" "$m/docs/howto/"
    python3 -c 'import sys; p, a, b = sys.argv[1:4]; s = open(p).read(); sys.exit(1) if s.count(a) != 1 else open(p, "w").write(s.replace(a, b))' \
      "$m/$2" "$3" "$4" || fail "selftest: mutant '$1' did not apply (the code moved — update the mutant)"
    local out; if out="$(RP_MUTANT_RUN=1 RP_CASES="$5" bash "$m/docs/howto/gate-examples/restore-points.sh" 2>&1)"; then fail "selftest: mutant '$1' still passes — not load-bearing"; fi
    case "$out" in *"$6"*) ;; *) fail "selftest: mutant '$1' failed for the WRONG reason: $out";; esac
    echo "  mutant caught: $1"
  }
  mutant "gate.sh tag failure swallowed" plugin/templates/gate.sh 'then restore_point_failed "$1" tag "$(echo "$err" | tail -1)"; fi' 'then :; fi' \
    tag-fail "tag failure not recorded"
  mutant "gate.sh nothing-to-commit treated as a failure" plugin/templates/gate.sh '  if ! git -C "$PROJECT_DIR" diff --cached --quiet >/dev/null 2>&1; then' '  if true; then' \
    nothing-to-commit "spurious restore_point_failed"
  mutant "python review-pass policy field dropped" py/src/heartbeat/review_policy.py '          "git": {"autocommit": _g.git_policy(hb)}}' '          }' \
    review-tag-fail "acceptance event has no git"
  mutant "python commit failure swallowed" py/src/heartbeat/gate.py '        if err:
            return failed("commit", err)' '        pass' \
    commit-fail "commit failure not recorded"
  mutant "node doctor anchor check removed" plugin/templates/hb.js "      if (anchored && !readAnchor(g)) problems.push(" "      if (false) problems.push(" \
    doctor-no-anchor "doctor missed the accepted gate without an anchor"
  mutant "node tags after a failed commit" plugin/templates/hb.js "    if (err) return failed('commit', err);" "    if (err) failed('commit', err);" \
    review-commit-fail "review pass tagged the PRE-phase HEAD"
  mutant "gate.sh tags after a failed commit" plugin/templates/gate.sh 'restore_point_failed "$1" commit "$(echo "$err" | tail -1)"; reproject; return 0; fi' 'restore_point_failed "$1" commit "$(echo "$err" | tail -1)"; fi' \
    commit-fail "tagged the PRE-phase HEAD"
  mutant "python doctor ignores a restore failure after the last acceptance" py/src/heartbeat/doctor.py '        elif ev == "restore_point_failed" and g in acc:' '        elif False:' \
    reaccept-tag-fail "doctor missed the failed restore point of the LAST acceptance"
  mutant "node doctor ignores git absent from PATH" plugin/templates/hb.js "      else if (gitOk && e.git && e.git.autocommit === true) {" "      else if (e.git && e.git.autocommit === true) {" \
    doctor-no-git-on-path "doctor claimed a missing tag with git absent"
  mutant "node anchor aborts on an unreadable file" plugin/templates/hb.js "    try { files[r] = hashFile(abs); } catch (e) { continue; }" "    files[r] = hashFile(abs);" \
    unreadable-file "acceptance anchor missing"
  mutant "python restore check hidden behind the _start guard" py/src/heartbeat/doctor.py '        if g in rpf:' '        if anchored and g in rpf:' \
    upgraded-commit-fail "doctor hid a new restore failure"
  mutant "python doctor flags legacy history" py/src/heartbeat/doctor.py '        if anchored and anchors.read_anchor(hbdir, g) is None:' '        if anchors.read_anchor(hbdir, g) is None:' \
    doctor-legacy "doctor flagged a healthy/legacy"
  echo "SELFTEST-OK"; exit 0
fi

python3 - "$obs_file" <<EOF || exit 1
$CHECK
bad = check(json.load(open(sys.argv[1])))
if bad: print("FAIL: " + bad, file=sys.stderr); sys.exit(1)
print("restore points: $NCASES cases × 2 runtimes hold")
print("RESTORE-POINTS-OK")
EOF
