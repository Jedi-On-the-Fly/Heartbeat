#!/usr/bin/env bash
# constraints-grounded.sh — a gate-time constraint must name something real. `hb constraints <gate>
# --record` refuses a set in which any constraint has no GROUNDED subject: a project-relative path that
# exists (file or directory), or one in the phase's `hb changed` list (a deleted file counts). A `:12` /
# `:12-30` line suffix and a `::symbol` / `#anchor` suffix are stripped first; an absolute path or one
# with `..` is never grounded. Free-text areas ("auth middleware") stay allowed ALONGSIDE a real path.
# Plan-time (P) constraints are not checked (they are written before the work exists). The author prompt
# states the rule; `hb exec`'s author step goes through the same record (an ungrounded author reply stops
# the run, the gate is not accepted). node ≡ python on every verdict.
#   bash tests/constraints-grounded.sh      prints CONSTRAINTS-GROUNDED-OK
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

DAG='{"phases":[{"id":"P0","title":"p0","gate_entry":null,"gate_exit":"G0","tasks":[{"id":"t0","title":"w0"}]}],
 "gates":{"G0":{"desc":"g0","review":{"prompt":"refute P0","constraints":[{"id":"P1","claim":"c1","subjects":["an area not yet written"],"violation":"v1"}]},
   "criteria":[{"id":"c","cmd":"grep -q 2 \"$PROJECT_DIR/src/a.txt\""}]}}}'
# a project whose gate G0 passed and awaits review; the phase deleted old.txt and wrote src/a.txt
mkproj() { local rt="$1" p; p="$(mktemp -d "$W/p.XXXX")"
  mkdir -p "$p/src"; printf '1\n' > "$p/src/a.txt"; printf 'x\n' > "$p/old.txt"
  if [ "$rt" = py ]; then hbpy init "$p" >/dev/null 2>&1; else bash "$ROOT/plugin/bootstrap.sh" "$p" --no-git >/dev/null 2>&1 </dev/null; fi
  printf '%s' "$DAG" > "$p/.hb/dag.json"; hb "$rt" "$p" rebuild >/dev/null 2>&1
  HB_ACTOR=doer hb "$rt" "$p" start t0 >/dev/null 2>&1; printf '2\n' > "$p/src/a.txt"; rm -f "$p/old.txt"
  HB_ACTOR=doer hb "$rt" "$p" done t0 >/dev/null 2>&1
  hb "$rt" "$p" gate G0 >/dev/null 2>&1
  echo "$p"; }

# <name> <want 0|1> <subjects JSON of G1> [subjects JSON of G2]
rec() { local name="$1" want="$2" s1="$3" s2="${4:-}" rt p out rc outs=""
  for rt in node py; do
    p="$(mkproj "$rt")"
    python3 - "$W/g.json" "$s1" "$s2" <<'EOF'
import json, sys
out, s1, s2 = sys.argv[1], sys.argv[2], sys.argv[3]
cs = [{"id": "G1", "claim": "src/a.txt says 2", "subjects": json.loads(s1), "violation": "it does not"}]
if s2: cs.append({"id": "G2", "claim": "c2", "subjects": json.loads(s2), "violation": "v2"})
json.dump(cs, open(out, "w"))
EOF
    out="$(cd "$p" && HB_ACTOR=author hb "$rt" "$p" constraints G0 --record "$W/g.json" 2>&1)"; rc=$?; [ "$rc" = 0 ] || rc=1
    [ "$rc" = "$want" ] || fail "$name ($rt): rc=$rc, want $want — $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-240)"
    if [ "$want" = 1 ]; then printf '%s' "$out" | grep -q "no subject names a real project path" || fail "$name ($rt): the refusal does not say why — $out"; fi
    outs="$outs|$(printf '%s' "${out//$p/<P>}" | tail -1)"
  done
  # node ≡ python: the same verdict line
  local n="${outs#|}"; n="${n%%|*}"; local y="${outs##*|}"
  [ "$n" = "$y" ] || fail "$name: node and python disagree: [$n] vs [$y]"; }

rec real-file       0 '["src/a.txt"]'
rec line-suffix     0 '["src/a.txt:1"]'
rec range-suffix    0 '["src/a.txt:1-3"]'
rec symbol-suffix   0 '["src/a.txt::read"]'
rec anchor-suffix   0 '["src/a.txt#top"]'
rec dot-slash       0 '["./src/a.txt"]'
rec directory       0 '["src"]'
rec dir-slash       0 '["src/"]'
rec with-area       0 '["upload validation", "src/a.txt"]'
rec deleted-file    0 '["old.txt"]'
rec area-only       1 '["user management system", "access control middleware"]'
rec missing-path    1 '["src/nope.py"]'
rec parent-escape   1 '["../outside.txt"]'
rec absolute        1 '["/etc/passwd"]'
rec one-of-two      1 '["src/a.txt"]' '["an area only"]'
rec both-grounded   0 '["src/a.txt"]' '["src"]'

# the author prompt states the rule, both runtimes
for rt in node py; do
  p="$(mkproj "$rt")"
  hb "$rt" "$p" constraints G0 --prompt 2>/dev/null | grep -q "at least one must be a project-relative path" \
    || fail "author prompt ($rt): the grounding rule is not stated"
done

# hb exec: an author reply whose constraints name nothing real stops the run; the gate is not accepted
for rt in node py; do
  for c in "no|user management system" "yes|src/a.txt"; do
    want="${c%%|*}"; p="$(mktemp -d "$W/x.XXXX")"; mkdir -p "$p/src"; printf '1\n' > "$p/src/a.txt"
    if [ "$rt" = py ]; then hbpy init "$p" >/dev/null 2>&1; else bash "$ROOT/plugin/bootstrap.sh" "$p" --no-git >/dev/null 2>&1 </dev/null; fi
    printf '%s' "$DAG" > "$p/.hb/dag.json"; hb "$rt" "$p" rebuild >/dev/null 2>&1
    cat > "$p/agent.sh" <<EOF2
#!/usr/bin/env bash
mode="\${!#}"; cat >/dev/null
case "\$mode" in
  execute) printf '2\n' > src/a.txt; echo '{"ok":true,"summary":"wrote src/a.txt"}' ;;
  author)  echo '{"ok":true,"constraints":[{"id":"G1","claim":"src/a.txt says 2","subjects":["${c#*|}"],"violation":"it does not"}]}' ;;
  refute)  printf '%s\n' '{"refuted":false,"findings":"Refutation of P0 / t0 / G0: ran the criterion, read src/a.txt.\nP1: NOT-REPRODUCED — cat src/a.txt shows 2\nG1: NOT-REPRODUCED — cat src/a.txt shows 2\n\nCLEAR"}' ;;
  *)       echo '{"error":"unsupported"}' ;;
esac
EOF2
    if [ "$rt" = py ]; then (cd "$p" && HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $p/agent.sh" timeout 120 python3 -m heartbeat.cli exec run --dir "$p" >"$W/exec.out" 2>&1)
    else (cd "$p" && HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $p/agent.sh" timeout 120 node .hb/hb-exec.js run >"$W/exec.out" 2>&1); fi
    if grep -Eq '"event": ?"review_passed"' "$p/.hb/events.jsonl"; then acc=yes; else acc=no; fi
    [ "$acc" = "$want" ] || fail "exec ($rt, subject '${c#*|}'): accepted=$acc, want $want — $(tail -3 "$W/exec.out" | tr '\n' ' ')"
    if [ "$want" = no ]; then grep -q "no subject names a real project path" "$W/exec.out" || fail "exec ($rt): the stop does not say why — $(tail -3 "$W/exec.out" | tr '\n' ' ')"; fi
  done
done
echo "CONSTRAINTS-GROUNDED-OK"
