#!/usr/bin/env bash
# review-holes.sh — a review pass that has no constraint answers must still say, in a checkable line,
# that the reviewer found no hole. On an UNCONSTRAINED gate (`hb review <gate> pass --artifact`) and for
# the FREE review of a constrained gate (`hb review <gate> free --artifact`), the artifact's visible text
# must carry a line
#       HOLES: none
# (markdown-insensitive, case-insensitive; several are fine — a panel's pass joins its CLEAR panelists).
# No such line, or any HOLES line that lists anything, refuses the pass: a hole is a finding — record it with `hb review <gate> fail "<finding>"`.
# Text inside an HTML comment is not visible and does not count. The refute prompts of those reviews ask
# for the line; `hb exec` goes through the same check (a reviewer reply without it stops the run, the
# gate is not accepted). A pass records holes:"none" + the artifact's sha256, and `hb doctor` re-checks
# the stored artifact. node ≡ python on every verdict and on the shared checker.
#   bash tests/review-holes.sh      prints REVIEW-HOLES-OK
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
unset HB_DIR DAG_FILE EVENTS_FILE HB_ACTOR HB_REFUTER 2>/dev/null || true
command -v node >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || { echo "node/python3 absent"; exit 1; }
fail() { echo "FAIL: $*"; exit 1; }
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
hbpy() { python3 -m heartbeat.cli "$@"; }
hb() { local rt="$1" p="$2"; shift 2
  if [ "$rt" = py ]; then hbpy "$@" --dir "$p"; else
    case "$1" in gate) shift; bash "$p/.hb/gate.sh" "$@";; *) node "$p/.hb/hb.js" "$@";; esac; fi; }

PLAIN='{"phases":[{"id":"P0","title":"p0","gate_entry":null,"gate_exit":"G0","tasks":[{"id":"t0","title":"w0"}]}],
 "gates":{"G0":{"desc":"g0","review":{"prompt":"refute P0"},"criteria":[{"id":"c","cmd":"grep -q 2 \"$PROJECT_DIR/a.txt\""}]}}}'
CONSTR='{"phases":[{"id":"P0","title":"p0","gate_entry":null,"gate_exit":"G0","tasks":[{"id":"t0","title":"w0"}]}],
 "gates":{"G0":{"desc":"g0","review":{"prompt":"refute P0","profile":"fr","constraints":[{"id":"P1","claim":"c1","subjects":["a.txt"],"violation":"v1"}]},
   "criteria":[{"id":"c","cmd":"grep -q 2 \"$PROJECT_DIR/a.txt\""}]}}}'
HEAD='Refutation attempt on P0 / t0 / G0: I ran the gate criteria and probed a.txt myself (empty file, missing file, a 1).'

# a project whose gate G0 passed its criteria and awaits review; <rt> <dag> [profile json]
mkproj() { local rt="$1" dag="$2" prof="${3:-}" p; p="$(mktemp -d "$W/p.XXXX")"
  printf '1\n' > "$p/a.txt"
  if [ "$rt" = py ]; then hbpy init "$p" >/dev/null 2>&1; else bash "$ROOT/plugin/bootstrap.sh" "$p" --no-git >/dev/null 2>&1 </dev/null; fi
  printf '%s' "$dag" > "$p/.hb/dag.json"
  if [ -n "$prof" ]; then mkdir -p "$p/.hb/refuters"; printf '%s' "$prof" > "$p/.hb/refuters/fr.json"; fi
  hb "$rt" "$p" rebuild >/dev/null 2>&1
  HB_ACTOR=doer hb "$rt" "$p" start t0 >/dev/null 2>&1; printf '2\n' > "$p/a.txt"; HB_ACTOR=doer hb "$rt" "$p" done t0 >/dev/null 2>&1
  hb "$rt" "$p" gate G0 >/dev/null 2>&1
  echo "$p"; }

# 1. the unconstrained pass: <name> <want 0|1> <body>
plain() { local name="$1" want="$2" body="$3" rt p out rc got=""
  for rt in node py; do
    p="$(mkproj "$rt" "$PLAIN")"; printf '%s\n' "$body" > "$p/art.md"
    out="$(cd "$p" && HB_ACTOR=refuter hb "$rt" "$p" review G0 pass --artifact art.md 2>&1)"; rc=$?; [ "$rc" = 0 ] || rc=1
    [ "$rc" = "$want" ] || fail "plain/$name ($rt): rc=$rc, want $want — $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-240)"
    if [ "$want" = 1 ]; then printf '%s' "$out" | grep -q "HOLES" || fail "plain/$name ($rt): the refusal does not name HOLES — $out"; fi
    got="$got$rc"
  done; }
plain no-holes-line  1 "$HEAD"
plain holes-none     0 "$HEAD
HOLES: none"
plain holes-bold     0 "$HEAD

**HOLES:** none."
plain holes-lower    0 "$HEAD
- holes: None"
plain holes-listed   1 "$HEAD
HOLES:
- a.txt is re-read after the check, so a later write is never seen"
plain holes-inline   1 "$HEAD
HOLES: a.txt is re-read after the check"
plain holes-twice    0 "$HEAD
HOLES: none
HOLES: none"
plain holes-comment  1 "$HEAD
<!-- HOLES: none -->"
plain holes-none-and-more 1 "$HEAD
HOLES: none, except that a.txt is re-read after the check"
# a fail needs no HOLES line (the finding is the note)
for rt in node py; do
  p="$(mkproj "$rt" "$PLAIN")"
  (cd "$p" && HB_ACTOR=refuter hb "$rt" "$p" review G0 fail "a.txt is re-read after the check" >/dev/null 2>&1) || fail "plain/fail ($rt): a fail verdict was refused"
done

# 2. the free review of a constrained gate
for rt in node py; do
  for c in "1|Free review of P0 / t0 / G0: looked in breadth at a.txt and the gate criteria, tried an empty and a missing a.txt." \
           "0|Free review of P0 / t0 / G0: looked in breadth at a.txt and the gate criteria, tried an empty and a missing a.txt.
HOLES: none" \
           "1|Free review of P0 / t0 / G0: looked in breadth at a.txt and the gate criteria, tried an empty and a missing a.txt.
HOLES:
- the criterion greps any 2, so 12 passes"; do
    want="${c%%|*}"; p="$(mkproj "$rt" "$CONSTR" '{"persona":"FR","free_review":true}')"
    printf '[{"id":"G1","claim":"g1","subjects":["a.txt"],"violation":"w1"}]' > "$W/g.json"
    HB_ACTOR=author hb "$rt" "$p" constraints G0 --record "$W/g.json" >/dev/null 2>&1 || fail "free ($rt): setup — constraints not recorded"
    printf '%s\n' "${c#*|}" > "$p/free.md"
    out="$(cd "$p" && HB_ACTOR=freer hb "$rt" "$p" review G0 free --artifact free.md 2>&1)"; rc=$?; [ "$rc" = 0 ] || rc=1
    [ "$rc" = "$want" ] || fail "free ($rt): rc=$rc, want $want — $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-240)"
  done
done

# 3. the prompts ask for the line: the unconstrained refute prompt and the free prompt, both runtimes;
#    the constrained (answers) prompt does not
for rt in node py; do
  p="$(mkproj "$rt" "$PLAIN")"
  hb "$rt" "$p" refute-prompt G0 2>/dev/null | grep -q "HOLES: none" || fail "prompt ($rt): the unconstrained refute prompt does not ask for HOLES: none"
  p="$(mkproj "$rt" "$CONSTR" '{"persona":"FR","free_review":true}')"
  printf '[{"id":"G1","claim":"g1","subjects":["a.txt"],"violation":"w1"}]' > "$W/g.json"
  HB_ACTOR=author hb "$rt" "$p" constraints G0 --record "$W/g.json" >/dev/null 2>&1
  hb "$rt" "$p" refute-prompt G0 --free 2>/dev/null | grep -q "HOLES: none" || fail "prompt ($rt): the free refute prompt does not ask for HOLES: none"
  hb "$rt" "$p" refute-prompt G0 2>/dev/null | grep -q "HOLES: none" && fail "prompt ($rt): the constrained (answers) prompt asks for HOLES too"
done

# 4. the shared checker: node ≡ python on a case list
python3 - "$ROOT" <<'EOF' || fail "checker: node and python disagree"
import json, subprocess, sys
root = sys.argv[1]; sys.path.insert(0, root + "/py/src")
from heartbeat.review_policy import check_holes
cases = ["HOLES: none", "holes: NONE.", "**HOLES:** none", "> - HOLES: none", "HOLES:none", "HOLES : none", "HOLES: none!",
         "", "HOLES:", "HOLES: -", "HOLES: none\nHOLES: none", "HOLES: nothing", "HOLES: none found", "HOLES:\n- x",
         "<!-- HOLES: none -->", "HOLES: n​one", "HOLES： none", "HOLES: none <!-- but a.txt is stale -->",
         "`HOLES: none`", "HOLE: none", "HOLES: n/a", "text\nHOLES: none\nmore text"]
node = subprocess.run(["node", "-e", "const {checkHoles}=require(process.argv[1]);const cs=JSON.parse(require('fs').readFileSync(0,'utf8'));"
                       "process.stdout.write(JSON.stringify(cs.map(c=>checkHoles(c).length===0)))", root + "/plugin/templates/hb.js"],
                      input=json.dumps(cases), capture_output=True, text=True)
if node.returncode: sys.exit("node: " + node.stderr[:400])
n = json.loads(node.stdout); p = [not check_holes(c) for c in cases]
bad = [(c, a, b) for c, a, b in zip(cases, n, p) if a != b]
if bad: sys.exit("disagree: %r" % bad[:5])
want = {"HOLES: none": True, "HOLES:": False, "HOLES:\n- x": False, "<!-- HOLES: none -->": False, "HOLES: none\nHOLES: none": True,
        "HOLES: none found": False, "HOLE: none": False}
for c, w in want.items():
    if (not check_holes(c)) is not w: sys.exit("check_holes(%r) accepted=%r, want %r" % (c, not check_holes(c), w))
EOF

# 5. hb exec: a reviewer reply without the line stops the run and the gate is not accepted; with it, accepted
for rt in node py; do
  for c in "no|Tried an empty and a missing a.txt; the criterion rejects both.\n\nCLEAR" \
           "yes|Tried an empty and a missing a.txt; the criterion rejects both.\nHOLES: none\n\nCLEAR"; do
    want="${c%%|*}"; p="$(mktemp -d "$W/x.XXXX")"
    if [ "$rt" = py ]; then hbpy init "$p" >/dev/null 2>&1; else bash "$ROOT/plugin/bootstrap.sh" "$p" --no-git >/dev/null 2>&1 </dev/null; fi
    printf '%s' "$PLAIN" > "$p/.hb/dag.json"; hb "$rt" "$p" rebuild >/dev/null 2>&1
    cat > "$p/agent.sh" <<EOF2
#!/usr/bin/env bash
mode="\${!#}"; cat >/dev/null
case "\$mode" in
  execute) printf '2\n' > a.txt; echo '{"ok":true,"summary":"wrote a.txt"}' ;;
  refute)  python3 -c 'import json,sys; print(json.dumps({"refuted": False, "findings": "Refutation attempt on P0 / t0 / G0: " + sys.argv[1].replace("\\\\n", "\n")}))' "${c#*|}" ;;
  *)       echo '{"error":"unsupported"}' ;;
esac
EOF2
    if [ "$rt" = py ]; then (cd "$p" && HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $p/agent.sh" timeout 120 python3 -m heartbeat.cli exec run --dir "$p" >"$W/exec.out" 2>&1)
    else (cd "$p" && HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $p/agent.sh" timeout 120 node .hb/hb-exec.js run >"$W/exec.out" 2>&1); fi
    if grep -Eq '"event": ?"review_passed"' "$p/.hb/events.jsonl"; then acc=yes; else acc=no; fi
    [ "$acc" = "$want" ] || fail "exec ($rt): accepted=$acc, want $want — $(tail -3 "$W/exec.out" | tr '\n' ' ')"
  done
done
# 5b. a panel keeps refute_if: under majority, 1 of 3 panelists refutes (listing its hole), 2 clear →
#     the gate is accepted; the pass artifact holds the CLEAR panelists' findings only, and the outvoted
#     panelist's finding is recorded as the pass note (not dropped)
PANEL='{"phases":[{"id":"P0","title":"p0","gate_entry":null,"gate_exit":"G0","tasks":[{"id":"t0","title":"w0"}]}],
 "gates":{"G0":{"desc":"g0","review":{"prompt":"refute P0","profile":"pn"},"criteria":[{"id":"c","cmd":"grep -q 2 \"$PROJECT_DIR/a.txt\""}]}}}'
for rt in node py; do
  p="$(mktemp -d "$W/n.XXXX")"
  if [ "$rt" = py ]; then hbpy init "$p" >/dev/null 2>&1; else bash "$ROOT/plugin/bootstrap.sh" "$p" --no-git >/dev/null 2>&1 </dev/null; fi
  printf '%s' "$PANEL" > "$p/.hb/dag.json"; mkdir -p "$p/.hb/refuters"
  printf '%s' '{"persona":"PN","verdict":{"panel":3,"refute_if":"majority"}}' > "$p/.hb/refuters/pn.json"; hb "$rt" "$p" rebuild >/dev/null 2>&1
  cat > "$p/agent.sh" <<'EOF2'
#!/usr/bin/env bash
mode="${!#}"; cat >/dev/null
case "$mode" in
  execute) printf '2\n' > a.txt; echo '{"ok":true,"summary":"wrote a.txt"}' ;;
  refute)  n=$(( $(cat .panel 2>/dev/null || echo 0) + 1 )); echo "$n" > .panel
           if [ "$n" = 1 ]; then echo '{"refuted":true,"findings":"Refutation of P0 / t0 / G0: DISSENT-MARK a.txt holds 12 too.\nHOLES:\n- the criterion greps any 2"}'
           else echo '{"refuted":false,"findings":"Refutation of P0 / t0 / G0: tried an empty and a missing a.txt; rejected.\nHOLES: none"}'; fi ;;
  *)       echo '{"error":"unsupported"}' ;;
esac
EOF2
  if [ "$rt" = py ]; then (cd "$p" && HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $p/agent.sh" timeout 120 python3 -m heartbeat.cli exec run --dir "$p" >"$W/exec.out" 2>&1)
  else (cd "$p" && HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $p/agent.sh" timeout 120 node .hb/hb-exec.js run >"$W/exec.out" 2>&1); fi
  python3 - "$p" "$rt" <<'EOF2' || fail "panel ($rt): $(tail -3 "$W/exec.out" | tr '\n' ' ')"
import json, sys
p, rt = sys.argv[1], sys.argv[2]
ev = [json.loads(l) for l in open(p + "/.hb/events.jsonl") if l.strip()]
rp = [e for e in ev if e.get("event") == "review_passed"]
if not rp: sys.exit("not accepted under majority (1 of 3 refuted)")
if "DISSENT-MARK" not in (rp[-1].get("note") or ""): sys.exit("the outvoted panelist's finding is not the pass note: %r" % rp[-1].get("note"))
art = open(p + "/.hb/" + rp[-1]["artifact"]).read()
if "DISSENT-MARK" in art or "greps any 2" in art: sys.exit("the pass artifact carries the outvoted panelist's hole")
EOF2
done

# 6. doctor re-checks the stored artifact of an unconstrained pass (it can rot): intact → quiet; the
#    HOLES line edited away → flagged
for rt in node py; do
  p="$(mkproj "$rt" "$PLAIN")"; printf '%s\nHOLES: none\n' "$HEAD" > "$p/art.md"
  (cd "$p" && HB_ACTOR=refuter hb "$rt" "$p" review G0 pass --artifact art.md >/dev/null 2>&1) || fail "doctor ($rt): setup pass refused"
  d="$(hb "$rt" "$p" doctor 2>&1)"   # doctor exits non-zero on problems: capture, then look (pipefail)
  printf '%s' "$d" | grep -q "HOLES line no longer holds" && fail "doctor ($rt): flagged an intact artifact"
  printf '%s\n' "$HEAD" > "$p/.hb/reviews/G0.md"
  d="$(hb "$rt" "$p" doctor 2>&1)"
  printf '%s' "$d" | grep -q "HOLES line no longer holds" || fail "doctor ($rt): an altered stored artifact was not flagged"
done
echo "REVIEW-HOLES-OK"
