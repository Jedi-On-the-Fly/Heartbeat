#!/usr/bin/env bash
# Proof: HeartBeat owns the "before" of every phase. It records an anchor (the project's path set +
# sha256 per file, + HEAD when in git) at the first task start — through ANY entry point (node CLI,
# python CLI, python MCP `start`, `hb exec` in either runtime) — and at every gate ACCEPTANCE (a
# review-less pass, or `review pass`; never at a deterministic pass that still owes a review).
# `hb changed <gate> [--json]` reports added/modified/deleted between the phase's entry anchor and:
# the working tree while the gate is pending (uncommitted + untracked work included), the gate's own
# anchor once accepted (later phases' edits never leak in). Listing: inside a git worktree
# `git ls-files -co --exclude-standard` (read-only), outside git a walk with a fixed exclusion list
# (.hb .git node_modules __pycache__ .venv). node ≡ python on path set + hashes and change lists.
# Acceptance anchors are write-once (re-running an accepted gate never moves them); the start anchor
# survives concurrent first starts (both runtimes); in git with autocommit ON the acceptance anchor's
# commit is the restore-point commit (taken after it). Prints GATE-ANCHORS-OK.
# `--selftest` (1) perturbs the real observations (drops an untracked file, leaks an ignored one,
# removes an anchor, …) and proves the checker rejects each, and (2) runs this proof against MUTANT
# copies of the real code (acceptance-anchor hooks removed, write-once removed, anchor moved before
# the restore commit) — each must go RED. Prints SELFTEST-OK.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
unset HB_DIR DAG_FILE EVENTS_FILE HB_ACTOR 2>/dev/null || true
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
command -v git     >/dev/null 2>&1 || { echo "git absent";     exit 1; }
fail() { echo "FAIL: $*" >&2; exit 1; }

export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
hbpy() { python3 -m heartbeat.cli "$@"; }

DAG='{"phases":[
 {"id":"P0","title":"p0","gate_entry":null,"gate_exit":"G0","tasks":[{"id":"T1","title":"t1"}]},
 {"id":"P1","title":"p1","gate_entry":"G0","gate_exit":"G1","tasks":[{"id":"T2","title":"t2"}]}],
 "gates":{
 "G0":{"desc":"g0","criteria":[{"id":"c","cmd":"test -s \"$PROJECT_DIR/a.txt\""}]},
 "G1":{"desc":"g1","review":{"prompt":"refute P1"},"criteria":[{"id":"c","cmd":"test -s \"$PROJECT_DIR/new.txt\""}]}}}'

# hb <rt> <project> <args…> — one verb, either runtime
hb() {
  local rt="$1" p="$2"; shift 2
  if [ "$rt" = py ]; then hbpy "$@" --dir "$p"; else
    case "$1" in gate) shift; bash "$p/.hb/gate.sh" "$@";; *) node "$p/.hb/hb.js" "$@";; esac
  fi
}
mkproject() { # <rt> <mode git|nogit> → path
  local rt="$1" mode="$2" p; p="$(mktemp -d "$work/p.XXXX")"
  printf 'alpha\n' > "$p/a.txt"; printf 'beta\n' > "$p/b.txt"; printf 'gamma\n' > "$p/c.txt"
  if [ "$mode" = git ]; then
    printf 'ign.txt\n' > "$p/.gitignore"; printf 'ignored\n' > "$p/ign.txt"
    git -C "$p" init -q && git -C "$p" add -A && git -C "$p" commit -qm base
  else
    mkdir -p "$p/node_modules/m" "$p/__pycache__"; printf 'x\n' > "$p/node_modules/m/i.js"; printf 'x\n' > "$p/__pycache__/c.pyc"
  fi
  if [ "$rt" = py ]; then hbpy init "$p" >/dev/null 2>&1; else bash "$ROOT/plugin/bootstrap.sh" "$p" --no-git >/dev/null 2>&1 </dev/null; fi
  printf '%s' "$DAG" > "$p/.hb/dag.json"
  hb "$rt" "$p" rebuild >/dev/null 2>&1
  printf '%s' "$p"
}
anchor() { local f="$1/.hb/anchors/$2.json"; [ -f "$f" ] && cat "$f" || echo null; }
changed() { local o; o="$(hb "$1" "$2" changed "$3" --json 2>/dev/null)" || o=null; [ -n "$o" ] || o=null; printf '%s' "$o"; }

# scenario <rt> <mode> → one JSON observation object on stdout
scenario() {
  local rt="$1" mode="$2" p; p="$(mkproject "$rt" "$mode")"
  # git mode runs with autocommit ON: the acceptance anchor must be taken after the restore commit
  if [ "$mode" = git ]; then unset HB_NO_GIT; else export HB_NO_GIT=1; fi
  local base; base="$(git -C "$p" rev-parse HEAD 2>/dev/null || echo none)"
  local o="$work/obs.$rt.$mode"; mkdir -p "$o"
  HB_ACTOR=doer hb "$rt" "$p" start T1 >/dev/null 2>&1
  anchor "$p" _start > "$o/start.json"
  # phase P0's work: uncommitted edit, untracked new file, deletion, ignored/excluded churn
  printf 'alpha2\n' > "$p/a.txt"; printf 'new\n' > "$p/new.txt"; rm -f "$p/b.txt"
  if [ "$mode" = git ]; then printf 'ignored2\n' > "$p/ign.txt"; else printf 'y\n' > "$p/node_modules/m/i.js"; fi
  HB_ACTOR=doer hb "$rt" "$p" done T1 >/dev/null 2>&1
  changed "$rt" "$p" G0 > "$o/changed_g0_pending.json"
  hb "$rt" "$p" gate G0 >/dev/null 2>&1
  anchor "$p" G0 > "$o/g0.json"
  # phase P1's work — must not leak into the (now accepted) G0 report
  HB_ACTOR=doer hb "$rt" "$p" start T2 >/dev/null 2>&1
  printf 'new2\n' > "$p/new.txt"; printf 'late\n' > "$p/late.txt"
  HB_ACTOR=doer hb "$rt" "$p" done T2 >/dev/null 2>&1
  changed "$rt" "$p" G0 > "$o/changed_g0_accepted.json"
  hb "$rt" "$p" gate G0 >/dev/null 2>&1          # re-run the accepted gate: its anchor must not move
  changed "$rt" "$p" G0 > "$o/changed_g0_rerun.json"
  changed "$rt" "$p" G1 > "$o/changed_g1_pending.json"
  hb "$rt" "$p" gate G1 >/dev/null 2>&1
  anchor "$p" G1 > "$o/g1_review_pending.json"
  printf 'Refutation attempt on P1 / T2: new.txt checked non-empty and real; could not refute G1.\n' > "$p/rev.md"
  HB_ACTOR=refuter hb "$rt" "$p" review G1 pass --artifact rev.md >/dev/null 2>&1
  anchor "$p" G1 > "$o/g1.json"
  # expected hashes, computed independently of HeartBeat
  python3 - "$p" > "$o/truth.json" <<'EOF'
import hashlib, json, os, sys
p = sys.argv[1]
print(json.dumps({f: hashlib.sha256(open(os.path.join(p, f), "rb").read()).hexdigest()
                  for f in ("a.txt", "c.txt", "new.txt", "late.txt")}))
EOF
  local head=null g0new=false
  if [ "$mode" = git ]; then
    head="\"$(git -C "$p" rev-parse HEAD)\""
    local c0; c0="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("commit") or "")' "$o/g0.json" 2>/dev/null)"
    [ -n "$c0" ] && [ "$c0" != "$base" ] && git -C "$p" cat-file -e "$c0:new.txt" 2>/dev/null && g0new=true
  fi
  export HB_NO_GIT=1
  python3 - "$o" "$rt" "$mode" "$head" "$g0new" <<'EOF'
import json, os, sys
o, rt, mode, head, g0new = sys.argv[1:6]
def load(n):
    try: return json.load(open(os.path.join(o, n + ".json")))
    except Exception: return "UNPARSEABLE"
obs = {k: load(k) for k in ("start", "changed_g0_pending", "g0", "changed_g0_accepted", "changed_g0_rerun",
                            "changed_g1_pending", "g1_review_pending", "g1", "truth")}
obs.update(rt=rt, mode=mode, head=json.loads(head), g0_commit_is_restore_point=(g0new == "true"))
print(json.dumps(obs, sort_keys=True))
EOF
  rm -rf "$p"
}

# entry-point coverage: _start must be taken whichever surface emits the first task_started
entry_points() { # → JSON {surface: bool}
  local p r=""
  p="$(mkproject py nogit)"; HB_ACTOR=doer python3 -c "
import sys; from heartbeat import mcp_server as m
m.TOOLS['start'][0](sys.argv[1] + '/.hb', {'task': 'T1'})" "$p" >/dev/null 2>&1
  r="$r\"py-mcp\":$([ -f "$p/.hb/anchors/_start.json" ] && echo true || echo false),"; rm -rf "$p"
  local stub="$work/bin"; mkdir -p "$stub"
  printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null 2>&1 || true' 'echo "{\"ok\":false,\"summary\":\"stub declines\"}"' > "$stub/stub"; chmod +x "$stub/stub"
  for rt in py node; do
    p="$(mkproject "$rt" nogit)"
    if [ "$rt" = py ]; then PATH="$stub:$PATH" HB_EXEC_CMD=stub HB_EXEC_MAX_ITERS=1 HB_EXEC_ATTEMPT_CAP=1 hbpy exec run --dir "$p" >/dev/null 2>&1
    else PATH="$stub:$PATH" HB_EXEC_CMD=stub HB_EXEC_MAX_ITERS=1 HB_EXEC_ATTEMPT_CAP=1 node "$p/.hb/hb-exec.js" run >/dev/null 2>&1; fi
    r="$r\"$rt-exec\":$([ -f "$p/.hb/anchors/_start.json" ] && echo true || echo false),"; rm -rf "$p"
  done
  # concurrent first starts: 8 at once, 4 trials — the start anchor must never be lost
  local ok trial
  ok=true; for trial in 1 2 3 4; do
    p="$(mkproject py nogit)"
    python3 -c "
import sys, threading; from heartbeat import mcp_server as m
ts = [threading.Thread(target=m.TOOLS['start'][0], args=(sys.argv[1] + '/.hb', {'task': 'X%d' % i})) for i in range(8)]
[t.start() for t in ts]; [t.join() for t in ts]" "$p" >/dev/null 2>&1
    [ -f "$p/.hb/anchors/_start.json" ] || ok=false; rm -rf "$p"
  done; r="$r\"py-parallel\":$ok,"
  ok=true; for trial in 1 2 3 4; do
    p="$(mkproject node nogit)"
    for i in 1 2 3 4 5 6 7 8; do node "$p/.hb/hb.js" start "X$i" >/dev/null 2>&1 & done; wait
    [ -f "$p/.hb/anchors/_start.json" ] || ok=false; rm -rf "$p"
  done; r="$r\"node-parallel\":$ok,"
  printf '{%s}' "${r%,}"
}

CHECK='
import json, sys
def check(all_obs, entries):
    """Return the first violated property, or None."""
    for s, ok in entries.items():
        if ok is not True: return "no _start anchor when the first task_started came through " + s
    by = {}
    for o in all_obs:
        key = o["rt"] + "/" + o["mode"]; by[(o["rt"], o["mode"])] = o
        for k in ("start", "g0", "g1"):
            a = o[k]
            if not isinstance(a, dict) or not isinstance(a.get("files"), dict): return key + ": missing/invalid anchor " + k
            if not a.get("ts"): return key + ": anchor " + k + " has no ts"
            if any(f == ".hb" or f.startswith(".hb/") or f.startswith(".git/") for f in a["files"]): return key + ": .hb/.git listed in " + k
            if o["mode"] == "git" and "ign.txt" in a["files"]: return key + ": git-ignored file in " + k
            if o["mode"] == "nogit" and any(f.split("/")[0] in ("node_modules", "__pycache__") for f in a["files"]): return key + ": excluded dir in " + k
        if not {"a.txt", "b.txt", "c.txt"} <= set(o["start"]["files"]): return key + ": _start misses a base file"
        if "new.txt" in o["start"]["files"]: return key + ": _start taken too late"
        t = o["truth"]
        if o["g0"]["files"].get("c.txt") != t["c.txt"] or o["g1"]["files"].get("new.txt") != t["new.txt"] or o["g1"]["files"].get("late.txt") != t["late.txt"]:
            return key + ": anchor hashes are not sha256 of the file"
        if "b.txt" in o["g0"]["files"] or "new.txt" not in o["g0"]["files"]: return key + ": G0 anchor is not the tree at acceptance"
        if o["mode"] == "git":
            if o["g1"].get("commit") != o["head"]: return key + ": G1 anchor commit is not HEAD"
        elif o["g1"].get("commit") is not None: return key + ": commit outside git must be null"
        if o["g1_review_pending"] is not None: return key + ": G1 anchored at the deterministic pass while a review was still owed"
        def trio(c):
            if not isinstance(c, dict): return None
            return (sorted(c.get("added") or []), sorted(c.get("modified") or []), sorted(c.get("deleted") or []))
        if trio(o["changed_g0_pending"]) != (["new.txt"], ["a.txt"], ["b.txt"]): return key + ": changed G0 (pending) wrong: " + str(trio(o["changed_g0_pending"]))
        if trio(o["changed_g0_accepted"]) != (["new.txt"], ["a.txt"], ["b.txt"]): return key + ": changed G0 (accepted) leaked later work: " + str(trio(o["changed_g0_accepted"]))
        if trio(o["changed_g0_rerun"]) != (["new.txt"], ["a.txt"], ["b.txt"]): return key + ": re-running accepted G0 moved its anchor: " + str(trio(o["changed_g0_rerun"]))
        if o["mode"] == "git" and not o["g0_commit_is_restore_point"]: return key + ": G0 anchor commit is not the restore-point commit (anchor taken before the commit?)"
        if trio(o["changed_g1_pending"]) != (["late.txt"], ["new.txt"], []): return key + ": changed G1 (pending) wrong: " + str(trio(o["changed_g1_pending"]))
    for mode in ("git", "nogit"):
        n, p = by.get(("node", mode)), by.get(("py", mode))
        if not n or not p: return "missing runtime for " + mode
        for k in ("start", "g0", "g1"):
            if n[k]["files"] != p[k]["files"]: return "parity: " + mode + " anchor " + k + " differs node vs python"
        for k in ("changed_g0_pending", "changed_g0_accepted", "changed_g0_rerun", "changed_g1_pending"):
            if {x: sorted(n[k].get(x) or []) for x in ("added", "modified", "deleted")} != {x: sorted(p[k].get(x) or []) for x in ("added", "modified", "deleted")}:
                return "parity: " + mode + " " + k + " differs node vs python"
    return None
'

obs_file="$work/all.json"; ent_file="$work/entries.json"
{ echo '['; first=1
  for rt in node py; do for mode in git nogit; do
    [ $first = 1 ] || echo ','; first=0; scenario "$rt" "$mode"
  done; done; echo ']'; } > "$obs_file"
entry_points > "$ent_file"

if [ "${1:-}" = "--selftest" ]; then
  python3 - "$obs_file" "$ent_file" <<EOF || exit 1
$CHECK
import copy
obs = json.load(open(sys.argv[1])); ent = json.load(open(sys.argv[2]))
if check(obs, ent) is not None:
    print("FAIL: selftest needs a green baseline; got: " + check(obs, ent), file=sys.stderr); sys.exit(1)
def m(name, f):
    o, e = copy.deepcopy(obs), copy.deepcopy(ent); f(o, e)
    if check(o, e) is None:
        print("FAIL: selftest: perturbation slipped past: " + name, file=sys.stderr); sys.exit(1)
m("drop untracked from changed",  lambda o, e: o[0]["changed_g0_pending"]["added"].remove("new.txt"))
m("drop uncommitted edit",        lambda o, e: o[0]["changed_g0_pending"]["modified"].remove("a.txt"))
m("drop deletion",                lambda o, e: o[1]["changed_g0_pending"]["deleted"].remove("b.txt"))
m("leak later work into G0",      lambda o, e: o[0]["changed_g0_accepted"]["added"].append("late.txt"))
m("leak ignored file",            lambda o, e: o[0]["g0"]["files"].__setitem__("ign.txt", "0"))
m("leak excluded dir",            lambda o, e: o[1]["start"]["files"].__setitem__("node_modules/m/i.js", "0"))
m("list .hb",                     lambda o, e: o[2]["g1"]["files"].__setitem__(".hb/state.json", "0"))
m("wrong hash",                   lambda o, e: o[3]["g1"]["files"].__setitem__("new.txt", "0" * 64))
m("no _start",                    lambda o, e: o[2].__setitem__("start", None))
m("anchored while review owed",   lambda o, e: o[0].__setitem__("g1_review_pending", o[0]["g1"]))
m("no acceptance anchor",         lambda o, e: o[3].__setitem__("g1", None))
m("wrong commit",                 lambda o, e: o[0]["g1"].__setitem__("commit", "deadbeef"))
m("parity drift",                 lambda o, e: o[2]["g0"]["files"].__setitem__("zz.txt", "0"))
m("MCP start not anchored",       lambda o, e: e.__setitem__("py-mcp", False))
m("exec start not anchored",      lambda o, e: e.__setitem__("node-exec", False))
m("anchor moved by a re-run",     lambda o, e: o[1]["changed_g0_rerun"]["added"].append("late.txt"))
m("anchor before restore commit", lambda o, e: o[0].__setitem__("g0_commit_is_restore_point", False))
m("parallel start lost",          lambda o, e: e.__setitem__("py-parallel", False))
EOF
  # (2) real-code mutants: the SAME proof, run against a mutated copy of the tree, must go RED
  mutant() { # <label> <file> <old> <new>
    local m="$work/mut"; rm -rf "$m"; mkdir -p "$m/docs/howto" "$m/py"
    cp -r "$ROOT/plugin" "$m/"; cp -r "$ROOT/py/src" "$m/py/"; cp -r "$ROOT/docs/howto/gate-examples" "$m/docs/howto/"
    python3 -c 'import sys; p, a, b = sys.argv[1:4]; s = open(p).read(); sys.exit(1) if s.count(a) != 1 else open(p, "w").write(s.replace(a, b))' \
      "$m/$2" "$3" "$4" || fail "selftest: mutant '$1' did not apply (the code moved — update the mutant)"
    if bash "$m/docs/howto/gate-examples/gate-anchors.sh" >/dev/null 2>&1; then fail "selftest: mutant '$1' still passes — that property is not load-bearing"; fi
    echo "  mutant caught: $1"
  }
  mutant "node review-pass anchor removed" plugin/templates/hb.js "    tryAnchor(gate);   // acceptance anchor" "    // (mutant) no acceptance anchor"
  mutant "gate.sh acceptance anchor removed" plugin/templates/gate.sh 'node "$HB_DIR/hb.js" anchor "$GATE" >/dev/null || true' ': mutant'
  mutant "node write-once removed" plugin/templates/hb.js "  if (readAnchor(name)) return true;
" ""
  mutant "python write-once removed" py/src/heartbeat/anchors.py "    if read_anchor(hbdir, name) is not None:
        return True
    try:" "    try:"
  mutant "node anchor before the restore commit" plugin/templates/gate.sh '  git_snapshot "$GATE"
  node "$HB_DIR/hb.js" anchor "$GATE" >/dev/null || true' '  node "$HB_DIR/hb.js" anchor "$GATE" >/dev/null || true
  git_snapshot "$GATE"'
  echo "SELFTEST-OK"; exit 0
fi

python3 - "$obs_file" "$ent_file" <<EOF || exit 1
$CHECK
obs = json.load(open(sys.argv[1])); ent = json.load(open(sys.argv[2]))
bad = check(obs, ent)
if bad: print("FAIL: " + bad, file=sys.stderr); sys.exit(1)
print("anchors: 4 scenarios (node/py × git/no-git) + 3 entry points hold")
print("GATE-ANCHORS-OK")
EOF
