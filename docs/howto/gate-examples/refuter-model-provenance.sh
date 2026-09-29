#!/usr/bin/env bash
# Proof: review events carry WHICH MODEL reviewed — so "is the cheaper refuter catching as
# much?" becomes answerable from the log (the repo's honest measurement: catches from truth,
# extended with the capability axis).
#   1. `review <gate> pass|fail … --model M` records model:M on the event — BOTH runtimes,
#      BOTH verdicts (the catch side of impact needs fail too).
#   2. omitting --model records model:null — honest, never fabricated.
#   3. the automated exec refute path AUTO-STAMPS the resolved profile.model (no flag) —
#      both executors, driven via a stub script backend (run, not source-grepped).
#   4. the MCP review tool accepts model and it reaches the event (MCP is a first-class
#      review surface; fail rides the same accept_review path).
#   5. refuter-impact breaks down caught/cleared per model on a MIXED null/named fixture —
#      the null-key trap is exactly where the runtimes would diverge — node ≡ python.
#   6. the review-pass guards still refuse on BOTH runtimes (artifact still required) and
#      doctor's Sev-1 artifact-rot check is behaviorally unchanged.
# --selftest: the checks are load-bearing. Prints REFUTER-PROVENANCE-OK.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
unset HB_DIR PROJECT_DIR GATE G HB_ACTOR HB_REFUTER 2>/dev/null || true
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }

mkproj(){ # $1 dir — two review-gated phases: G0 profiled (model m-auto), G1 profile-less
  mkdir -p "$1/.hb/refuters" "$1/.hb/reviews" "$1/.hb/executors"
  cp "$ROOT/plugin/templates/hb.js" "$ROOT/plugin/templates/hb-audit.js" \
     "$ROOT/plugin/templates/hb-lint.js" "$ROOT/plugin/templates/hb-next-task.js" \
     "$ROOT/plugin/templates/hb-report.js" "$ROOT/plugin/templates/hb-exec.js" \
     "$ROOT/plugin/templates/refuter_profiles.js" "$1/.hb/"
  cp "$ROOT/plugin/templates/gate.sh" "$ROOT/plugin/templates/tick.sh" "$1/.hb/"
  printf '%s' '{"phases":[{"id":"P0","gate_entry":null,"gate_exit":"G0","tasks":[{"id":"T1","title":"t1","requires":[]}]},{"id":"P1","gate_entry":"G0","gate_exit":"G1","tasks":[{"id":"T2","title":"t2","requires":[]}]}],"gates":{"G0":{"desc":"g0","review":{"prompt":"Refute P0 done","profile":"prov"},"criteria":[{"id":"c","cmd":"true"}]},"G1":{"desc":"g1","review":{"prompt":"Refute P1 done"},"criteria":[{"id":"c","cmd":"true"}]}}}' > "$1/.hb/dag.json"
  printf '%s' '{"persona":"PROV refuter","model":"m-auto"}' > "$1/.hb/refuters/prov.json"
  printf '%s\n' '{"event":"initialized"}' > "$1/.hb/events.jsonl"
  printf 'This refutation examined P0 and gate G0 in depth and could not refute completion.\nHOLES: none\n' > "$1/art.md"
}
# last review event of a type → its model field rendered as `null` or the value; `absent` if no key
evmodel(){ python3 -c '
import sys, json
ev = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
m = [e for e in ev if e.get("event") == sys.argv[2] and e.get("gate") == sys.argv[3]]
assert m, "no %s for %s" % (sys.argv[2], sys.argv[3])
e = m[-1]
print("absent" if "model" not in e else ("null" if e["model"] is None else e["model"]))' "$1" "$2" "$3"; }

p="$(mktemp -d)"; trap 'rm -rf "$p"' EXIT

# ── 1+2. CLI recording — python ──────────────────────────────────────────────
py="$p/py"; mkproj "$py"
HB_ACTOR=doer hb start T1 --dir "$py" >/dev/null 2>&1; HB_ACTOR=doer hb done T1 --dir "$py" >/dev/null 2>&1
HB_ACTOR=doer hb gate G0 --dir "$py" >/dev/null 2>&1
HB_ACTOR=rev hb review G0 fail "G0 P0: found a hole in the claim, forty-plus chars of findings" --model m-flag --dir "$py" >/dev/null 2>&1 \
  || fail "python review fail --model failed (does the flag exist?)"
[ "$(evmodel "$py/.hb/events.jsonl" review_failed G0)" = "m-flag" ] || fail "python: review_failed did not record the flagged model"
HB_ACTOR=doer hb gate G0 --dir "$py" >/dev/null 2>&1
HB_ACTOR=rev hb review G0 pass --artifact "$py/art.md" --model m-flag --dir "$py" >/dev/null 2>&1 \
  || fail "python review pass --model failed"
[ "$(evmodel "$py/.hb/events.jsonl" review_passed G0)" = "m-flag" ] || fail "python: review_passed did not record the flagged model"
HB_ACTOR=doer hb start T2 --dir "$py" >/dev/null 2>&1; HB_ACTOR=doer hb done T2 --dir "$py" >/dev/null 2>&1
HB_ACTOR=doer hb gate G1 --dir "$py" >/dev/null 2>&1
printf 'This refutation examined P1 and gate G1 and could not refute completion at all.\nHOLES: none\n' > "$py/art2.md"
HB_ACTOR=rev hb review G1 pass --artifact "$py/art2.md" --dir "$py" >/dev/null 2>&1 || fail "python review pass (no --model) failed"
[ "$(evmodel "$py/.hb/events.jsonl" review_passed G1)" = "null" ] || fail "python: omitted --model must record null (never fabricated, never absent)"

# ── 1. CLI recording — node twin ─────────────────────────────────────────────
nd="$p/nd"; mkproj "$nd"
( cd "$nd" && HB_ACTOR=doer node .hb/hb.js start T1 >/dev/null 2>&1 && HB_ACTOR=doer node .hb/hb.js done T1 >/dev/null 2>&1 && HB_ACTOR=doer bash .hb/gate.sh G0 >/dev/null 2>&1 )
( cd "$nd" && HB_ACTOR=rev node .hb/hb.js review G0 fail "G0 P0: found a hole in the claim, forty-plus chars of findings" --model m-flag >/dev/null 2>&1 ) \
  || fail "node review fail --model failed"
[ "$(evmodel "$nd/.hb/events.jsonl" review_failed G0)" = "m-flag" ] || fail "node: review_failed did not record the flagged model"
( cd "$nd" && HB_ACTOR=doer bash .hb/gate.sh G0 >/dev/null 2>&1 )
( cd "$nd" && HB_ACTOR=rev node .hb/hb.js review G0 pass --artifact art.md --model m-flag >/dev/null 2>&1 ) || fail "node review pass --model failed"
[ "$(evmodel "$nd/.hb/events.jsonl" review_passed G0)" = "m-flag" ] || fail "node: review_passed did not record the flagged model"

# ── 1c. a flag-shaped token in an UNQUOTED note must be refused LOUDLY — never a
#        fabricated model, never a silently truncated note (GATE_RE2 refuter catch;
#        found on node, and python's argparse quietly did the same on intermixed input) ──
ev_count(){ grep -c '"event": *"review_' "$1" 2>/dev/null || true; }
nb=$(ev_count "$py/.hb/events.jsonl")
HB_ACTOR=rev hb review G1 fail found a hole in --model handling --dir "$py" >/dev/null 2>&1 \
  && fail "python: flag-shaped token inside an unquoted note was ACCEPTED (fabrication risk)"
[ "$(ev_count "$py/.hb/events.jsonl")" = "$nb" ] || fail "python: the refused review still wrote an event"
nb=$(ev_count "$nd/.hb/events.jsonl")
( cd "$nd" && HB_ACTOR=rev node .hb/hb.js review G0 fail found a hole in --model handling >/dev/null 2>&1 ) \
  && fail "node: flag-shaped token inside an unquoted note was ACCEPTED (fabrication risk)"
[ "$(ev_count "$nd/.hb/events.jsonl")" = "$nb" ] || fail "node: the refused review still wrote an event"
# …while a QUOTED note that merely MENTIONS --model stays accepted, un-truncated, model null
HB_ACTOR=rev hb review G1 fail "the --model handling has a hole somewhere" --dir "$py" >/dev/null 2>&1 \
  || fail "python: a quoted note mentioning --model was refused (over-tightened)"
python3 -c '
import sys, json
ev = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
e = [x for x in ev if x.get("event") == "review_failed" and x.get("gate") == "G1"][-1]
assert e.get("model") is None, "model fabricated from a quoted note: %r" % e.get("model")
assert "--model handling" in (e.get("note") or ""), "quoted note was truncated: %r" % e.get("note")
' "$py/.hb/events.jsonl" || fail "python: quoted-note event wrong (fabricated model or truncated note)"

# ── 3. exec AUTO-STAMP from the profile (both executors, stub backend) ───────
mkexec(){ # $1 dir — stub script backend: execute ok, refute CLEAR with substantive findings
  cat > "$1/stub.sh" <<'STUB'
#!/usr/bin/env bash
mode="${@: -1}"
if [ "$mode" = "refute" ]; then printf '%s' '{"refuted":false,"findings":"Examined gate G0 of phase P0 thoroughly; could not refute the completion claim.\nHOLES: none"}'
else printf '%s' '{"ok":true,"summary":"did the task"}'; fi
STUB
  chmod +x "$1/stub.sh"
  printf '%s' "{\"backend\":\"script\",\"cmd\":\"$1/stub.sh\"}" > "$1/.hb/executor.json"
}
pe="$p/pe"; mkproj "$pe"; mkexec "$pe"
python3 - "$pe" <<'PY'
import json, sys
f = sys.argv[1] + "/.hb/dag.json"
d = json.load(open(f))
d["phases"] = [d["phases"][0]]          # single review-gated phase for a bounded exec run
json.dump(d, open(f, "w"))
PY
( cd "$pe" && HB_EXEC_BACKEND=script HB_EXEC_CMD="$pe/stub.sh" hb exec run --dir "$pe" >/dev/null 2>&1 )
[ "$(evmodel "$pe/.hb/events.jsonl" review_passed G0)" = "m-auto" ] || fail "python exec did not AUTO-STAMP the profile's model on the review event"
ne="$p/ne"; mkproj "$ne"; mkexec "$ne"
python3 - "$ne" <<'PY'
import json, sys
f = sys.argv[1] + "/.hb/dag.json"
d = json.load(open(f))
d["phases"] = [d["phases"][0]]
json.dump(d, open(f, "w"))
PY
( cd "$ne" && HB_EXEC_BACKEND=script HB_EXEC_CMD="$ne/stub.sh" node .hb/hb-exec.js run >/dev/null 2>&1 )
[ "$(evmodel "$ne/.hb/events.jsonl" review_passed G0)" = "m-auto" ] || fail "node exec did not AUTO-STAMP the profile's model on the review event"

# ── 4. MCP review carries model (stdio JSON-RPC, stdlib only) ────────────────
pm="$p/pm"; mkproj "$pm"
HB_ACTOR=doer hb start T1 --dir "$pm" >/dev/null 2>&1; HB_ACTOR=doer hb done T1 --dir "$pm" >/dev/null 2>&1
HB_ACTOR=doer hb gate G0 --dir "$pm" >/dev/null 2>&1
printf '%s\n%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"proof","version":"0"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"review\",\"arguments\":{\"gate\":\"G0\",\"verdict\":\"pass\",\"artifact\":\"$pm/art.md\",\"model\":\"m-mcp\"}}}" \
  | HB_ACTOR=rev hb mcp-serve --dir "$pm" >/dev/null 2>&1
[ "$(evmodel "$pm/.hb/events.jsonl" review_passed G0)" = "m-mcp" ] || fail "MCP review did not carry model to the event"

# ── 5. per-model impact on a MIXED null/named fixture, node ≡ python ─────────
IMP='import sys,json;r=json.load(sys.stdin);g=r["refuters"]["gates"] if "refuters" in r else r["gates"];print(json.dumps([[x["gate"],sorted((x.get("models") or {}).items())] for x in g],sort_keys=True))'
pyimp=$(hb report --json --dir "$py" | python3 -c "$IMP") || fail "python impact failed"
ndimp=$( cd "$py" && node .hb/hb-report.js .hb --json | python3 -c "$IMP" ) || fail "node impact failed"
[ "$pyimp" = "$ndimp" ] || fail "per-model impact diverges node vs python on the mixed fixture: $pyimp vs $ndimp"
echo "$pyimp" | grep -q 'm-flag' || fail "impact breakdown missing the named model"
echo "$pyimp" | grep -q '(none)' || fail "impact breakdown missing the null bucket ((none))"

# ── 6. guards unchanged (both runtimes) + doctor Sev-1 intact ────────────────
HB_ACTOR=rev2 hb review G1 pass --model m-x --dir "$py" >/dev/null 2>&1 && fail "python: pass WITHOUT artifact was accepted — guard weakened"
( cd "$nd" && HB_ACTOR=rev2 node .hb/hb.js review G0 pass --model m-x >/dev/null 2>&1 ) && fail "node: pass WITHOUT artifact was accepted — guard weakened"
rm -f "$py/.hb/reviews/G0.md"
hb doctor --dir "$py" >/dev/null 2>&1 && fail "doctor no longer flags a missing review artifact (Sev-1 rot check broken)"

# ── --selftest: the checks bite ──────────────────────────────────────────────
if [ "${1:-}" = "--selftest" ]; then
  python3 - "$py/.hb/events.jsonl" <<'PY'
import json, sys
lines = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for e in lines:
    if e.get("event") == "review_passed":
        e.pop("model", None)
open(sys.argv[1], "w").write("\n".join(json.dumps(e) for e in lines) + "\n")
PY
  [ "$(evmodel "$py/.hb/events.jsonl" review_passed G0 2>/dev/null)" = "m-flag" ] && { echo "SELFTEST-ESCAPED: stripped model still read as recorded"; exit 1; }
  echo "$pyimp" | grep -q 'm-NOPE' && { echo "SELFTEST-ESCAPED: impact grep matches anything"; exit 1; }
  echo "SELFTEST-OK: recording, null-honesty, and impact checks are load-bearing."
  exit 0
fi

echo "REFUTER-PROVENANCE-OK: model recorded (flag + null + auto-stamp + MCP), per-model impact node ≡ python, guards and Sev-1 rot intact."
