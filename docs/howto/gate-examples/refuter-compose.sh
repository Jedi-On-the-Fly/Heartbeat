#!/usr/bin/env bash
# Proof: ONE compose — `hb refute-prompt <gate>` — serves the refute path, node ≡ python, and:
#   (A) BACKWARD-COMPAT — a gate with NO review.profile and no HB_REFUTER yields EXACTLY today's prompt
#       (review.prompt, or the "Refute that <gate> is truly complete." fallback) — no persona/questions
#       injected, so existing projects are byte-unchanged.
#   (B) NAMED profile — the composed prompt CONTAINS persona + the gate's BASE review_questions + the
#       profile's EXTRA questions + review.prompt; and profile.model reaches the refute DISPATCH
#       (observed via a stub backend that echoes the payload prompt + $HB_EXEC_MODEL).
#   (C) COVERAGE-NARROWING — the profile's questions APPEND to, never REPLACE, the base review_questions.
#   (D) an UNKNOWN profile named on a gate makes the DISPATCH error non-zero (review is NOT skipped —
#       fail-closed at the compose site, not only in the resolver).
#   (E) distinct-actor + fail-closed are unchanged.
# Prints REFUTER-COMPOSE-OK. Fails before `hb refute-prompt` / the wired dispatch exist (spec-first RED).
#
# `--selftest` proves the (A) backward-compat, (C) append-not-replace, and (D) unknown-errors checks are
# each individually load-bearing, via crafted prompt strings + exit codes (no real impl needed). SELFTEST-OK.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
unset HB_DIR DAG_FILE EVENTS_FILE HB_REFUTER 2>/dev/null || true
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# ── property checks over a composed prompt STRING / exit code (load-bearing; reused by --selftest) ──
# (A) backward-compat: output is exactly the gate's prompt, with NO profile material leaked in
chk_bc() { # <output> <expectedPrompt>
  [ "$1" = "$2" ] || return 1
  case "$1" in *SECBOT-PERSONA*|*"Falsification checklist"*|*EXTRA-Q-INJECTION*) return 1 ;; esac
  return 0
}
# (B) composed prompt carries every piece
chk_compose() { # <output>
  case "$1" in *SECBOT-PERSONA*)            : ;; *) return 1 ;; esac
  case "$1" in *"Falsification checklist"*) : ;; *) return 1 ;; esac
  case "$1" in *EXTRA-Q-INJECTION*)         : ;; *) return 1 ;; esac
  case "$1" in *REVIEW-PROMPT-MARKER*)      : ;; *) return 1 ;; esac
  return 0
}
# (C) append-not-replace: the BASE checklist AND the profile's extra question BOTH survive
chk_append() { # <output>
  case "$1" in *"Falsification checklist"*) : ;; *) return 1 ;; esac
  case "$1" in *EXTRA-Q-INJECTION*)         : ;; *) return 1 ;; esac
  return 0
}
# (D) unknown profile: the command/dispatch must FAIL (non-zero), not emit a review-less prompt
chk_unknown() { [ "$1" -ne 0 ]; }

# ── selftest: each check rejects the corresponding defect ──────────────────────────────────────────
if [ "${1:-}" = "--selftest" ]; then
  good_bc="REVIEW-PROMPT-MARKER refute this gate"
  chk_bc "$good_bc" "$good_bc" || { echo "SELFTEST FAIL: chk_bc rejected a clean backward-compat prompt" >&2; exit 1; }
  # bc defect: persona leaked into the no-profile path
  if chk_bc "SECBOT-PERSONA ... $good_bc" "$good_bc"; then echo "SELFTEST FAIL: chk_bc passed a prompt with leaked profile material (not load-bearing)" >&2; exit 1; fi
  # append: both base + extra present passes; replaced (base dropped) fails
  chk_append "Falsification checklist ... EXTRA-Q-INJECTION" || { echo "SELFTEST FAIL: chk_append rejected base+extra" >&2; exit 1; }
  if chk_append "EXTRA-Q-INJECTION only (base replaced)"; then echo "SELFTEST FAIL: chk_append passed when the base checklist was replaced (not load-bearing)" >&2; exit 1; fi
  # unknown: nonzero passes, zero fails
  chk_unknown 1 || { echo "SELFTEST FAIL: chk_unknown rejected a non-zero exit" >&2; exit 1; }
  if chk_unknown 0; then echo "SELFTEST FAIL: chk_unknown passed a zero exit for an unknown profile (not load-bearing)" >&2; exit 1; fi
  echo "SELFTEST-OK"; exit 0
fi

export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
hbpy() { python3 -m heartbeat.cli "$@"; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# a review-gated DAG; $1=dagfile, $2=profile-or-empty (sets gate.review.profile when non-empty)
write_dag() {
  python3 - "$1" "$2" <<'PY'
import json, sys
prof = sys.argv[2]
review = {"prompt": "REVIEW-PROMPT-MARKER refute that the phase is complete"}
if prof:
    review["profile"] = prof
json.dump({"phases": [{"id": "P0", "gate_entry": None, "gate_exit": "GATE_P0",
                       "tasks": [{"id": "T1", "title": "produce out.txt"}]}],
           "gates": {"GATE_P0": {"desc": "the phase", "review": review,
                                 "criteria": [{"id": "c", "cmd": "grep -q ok \"$PROJECT_DIR/out.txt\""}]}}},
          open(sys.argv[1], "w"))
PY
}
add_security() { # <hbdir>  — a named profile with a persona, an extra question, and a model
  mkdir -p "$1/refuters"
  printf '%s' '{"persona":"SECBOT-PERSONA hunts injection and missing authz","questions":["EXTRA-Q-INJECTION does any new path skip authz?"],"model":"SENTINEL-MODEL"}' > "$1/refuters/security.json"
}

rp_py()   { hbpy refute-prompt GATE_P0 --dir "$1"; }
rp_node() { node "$1/.hb/hb.js" refute-prompt GATE_P0; }

# ── Part 1: `hb refute-prompt` content, both runtimes ───────────────────────────────────────────────
# (A) backward-compat: no profile, no env → EXACTLY the gate's review.prompt
pbc="$work/bc"; bash "$ROOT/plugin/bootstrap.sh" "$pbc" >/dev/null 2>&1 </dev/null
write_dag "$pbc/.hb/dag.json" ""
EXPECT="REVIEW-PROMPT-MARKER refute that the phase is complete"
obc_n="$(rp_node "$pbc")" || fail "node refute-prompt failed (command missing?) [A]"
obc_p="$(rp_py "$pbc")"   || fail "python refute-prompt failed (command missing?) [A]"
chk_bc "$obc_n" "$EXPECT" || fail "node backward-compat prompt not byte-identical to review.prompt (leaked profile material?) got=[$obc_n]"
chk_bc "$obc_p" "$EXPECT" || fail "python backward-compat prompt not byte-identical to review.prompt got=[$obc_p]"
[ "$obc_n" = "$obc_p" ]   || fail "backward-compat prompt differs node vs python: n=[$obc_n] p=[$obc_p]"

# fallback form: a gate with NO review.prompt → "Refute that GATE_P0 is truly complete."
pfb="$work/fb"; bash "$ROOT/plugin/bootstrap.sh" "$pfb" >/dev/null 2>&1 </dev/null
python3 -c 'import json;json.dump({"phases":[{"id":"P0","gate_entry":None,"gate_exit":"GATE_P0","tasks":[{"id":"T1"}]}],"gates":{"GATE_P0":{"criteria":[{"id":"c","cmd":"true"}]}}},open("'"$pfb"'/.hb/dag.json","w"))'
ofb_n="$(rp_node "$pfb")" || fail "node refute-prompt fallback failed"
ofb_p="$(rp_py "$pfb")"   || fail "python refute-prompt fallback failed"
[ "$ofb_n" = "Refute that GATE_P0 is truly complete." ] || fail "node fallback prompt wrong: [$ofb_n]"
[ "$ofb_n" = "$ofb_p" ] || fail "fallback prompt differs node vs python"

# (B/C) named profile: composed prompt carries persona + base checklist + extra + review.prompt
pnp="$work/np"; bash "$ROOT/plugin/bootstrap.sh" "$pnp" >/dev/null 2>&1 </dev/null
write_dag "$pnp/.hb/dag.json" "security"; add_security "$pnp/.hb"
onp_n="$(rp_node "$pnp")" || fail "node refute-prompt (profile) failed"
onp_p="$(rp_py "$pnp")"   || fail "python refute-prompt (profile) failed"
chk_compose "$onp_n" || fail "node composed prompt missing a piece (persona/checklist/extra/prompt): [$onp_n]"
chk_compose "$onp_p" || fail "python composed prompt missing a piece: [$onp_p]"
chk_append  "$onp_n" || fail "node composed prompt REPLACED the base checklist (coverage narrowing)"
[ "$onp_n" = "$onp_p" ] || fail "composed prompt differs node vs python (parity)"

# (D) unknown profile named on the gate → the command errors non-zero (both runtimes)
pgh="$work/gh"; bash "$ROOT/plugin/bootstrap.sh" "$pgh" >/dev/null 2>&1 </dev/null
write_dag "$pgh/.hb/dag.json" "ghost-profile"
rp_node "$pgh" >/dev/null 2>&1; chk_unknown "$?" || fail "node refute-prompt did NOT error on an unknown profile"
rp_py   "$pgh" >/dev/null 2>&1; chk_unknown "$?" || fail "python refute-prompt did NOT error on an unknown profile"

# ── Part 2: the DISPATCH uses the compose — persona + profile.model reach the refuter (both runtimes) ─
bindir="$work/bin"; mkdir -p "$bindir"
cat > "$bindir/stub" <<'STUB'
#!/usr/bin/env bash
mode="${1:-execute}"; payload="$(cat)"
if [ "$mode" = execute ]; then echo ok > out.txt; echo '{"ok":true,"summary":"stub did the task"}'
else
  { echo "MODEL=${HB_EXEC_MODEL:-none}"; printf '%s\n' "$payload"; } >> "$STUB_CAPTURE"
  echo '{"refuted":false,"findings":"stub refuter examined the phase criteria and could not refute it — substantive artifact well over the forty character minimum"}'
fi
STUB
chmod +x "$bindir/stub"

phase_done() { # <runtime-cmd...> checks P0 completed
  "$@" 2>/dev/null | python3 -c "import sys,json;sys.exit(0 if 'P0' in (json.load(sys.stdin).get('completed_phases') or []) else 1)"
}

# python dispatch
pp="$work/disp-py"; hbpy init "$pp" >/dev/null 2>&1
write_dag "$pp/.hb/dag.json" "security"; add_security "$pp/.hb"; hbpy rebuild --dir "$pp" >/dev/null 2>&1
cap_py="$work/cap-py.txt"; : > "$cap_py"
PATH="$bindir:$PATH" STUB_CAPTURE="$cap_py" HB_EXEC_CMD="stub" HB_EXEC_MAX_ITERS=40 hbpy exec run --dir "$pp" >/dev/null 2>&1
phase_done hbpy state --dir "$pp" || fail "py: phase did not complete through the stub refuter"
grep -q "SECBOT-PERSONA" "$cap_py" || fail "py: the profile PERSONA did not reach the refute dispatch (compose not wired)"
grep -q "MODEL=SENTINEL-MODEL" "$cap_py" || fail "py: profile.model did not reach the refute dispatch"

# node dispatch
pn="$work/disp-node"; bash "$ROOT/plugin/bootstrap.sh" "$pn" >/dev/null 2>&1 </dev/null
write_dag "$pn/.hb/dag.json" "security"; add_security "$pn/.hb"; node "$pn/.hb/hb.js" rebuild >/dev/null 2>&1
cap_n="$work/cap-node.txt"; : > "$cap_n"
PATH="$bindir:$PATH" STUB_CAPTURE="$cap_n" HB_EXEC_CMD="stub" HB_EXEC_MAX_ITERS=40 node "$pn/.hb/hb-exec.js" run >/dev/null 2>&1
node "$pn/.hb/hb.js" state | node -pe 'JSON.parse(require("fs").readFileSync(0)).completed_phases.includes("P0")' | grep -q true || fail "node: phase did not complete through the stub refuter"
grep -q "SECBOT-PERSONA" "$cap_n" || fail "node: the profile PERSONA did not reach the refute dispatch (compose not wired)"
grep -q "MODEL=SENTINEL-MODEL" "$cap_n" || fail "node: profile.model did not reach the refute dispatch"

# (D/E) fail-closed at dispatch: an unknown profile must NOT pass the review (phase stays incomplete)
pfc="$work/failclosed"; hbpy init "$pfc" >/dev/null 2>&1
write_dag "$pfc/.hb/dag.json" "ghost-profile"; hbpy rebuild --dir "$pfc" >/dev/null 2>&1
PATH="$bindir:$PATH" STUB_CAPTURE="/dev/null" HB_EXEC_CMD="stub" HB_EXEC_MAX_ITERS=40 hbpy exec run --dir "$pfc" >/dev/null 2>&1
if phase_done hbpy state --dir "$pfc"; then fail "py: an UNKNOWN profile still passed the review (fail-open at dispatch)"; fi

# same fail-closed at dispatch on the NODE executor (both runtimes must fail closed, not just python)
pfcn="$work/failclosed-node"; bash "$ROOT/plugin/bootstrap.sh" "$pfcn" >/dev/null 2>&1 </dev/null
write_dag "$pfcn/.hb/dag.json" "ghost-profile"; node "$pfcn/.hb/hb.js" rebuild >/dev/null 2>&1
PATH="$bindir:$PATH" STUB_CAPTURE="/dev/null" HB_EXEC_CMD="stub" HB_EXEC_MAX_ITERS=40 node "$pfcn/.hb/hb-exec.js" run >/dev/null 2>&1
if node "$pfcn/.hb/hb.js" state | node -pe 'JSON.parse(require("fs").readFileSync(0)).completed_phases.includes("P0")' | grep -q true; then fail "node: an UNKNOWN profile still passed the review (fail-open at dispatch)"; fi

echo "REFUTER-COMPOSE-OK"
