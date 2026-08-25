#!/usr/bin/env bash
# The SessionStart hook (plugin/hooks/heartbeat-detect.sh) is the ALWAYS-ON channel that reaches any
# agent — Claude Code and, via the shared plugin marketplace, Codex. It must carry a DRIVE-LOOP
# instruction, not just react to one tick: on a `.hb/` project the injected pointer must (A) fire,
# (B) tell the agent to re-run `.hb/tick.sh` (a run verb next to the script, so scattered tokens
# don't count), (C) frame that as a loop, (D) name all_done as the success stop, and (E) name a
# human-needed reason as the other stop. Reactive-only text (the pre-fix hook) fails B+C — that was
# the gap that left interactive Codex/Claude stopping mid-DAG. Silent off-project. Prints
# HOOK-DRIVES-LOOP-OK; `--selftest` proves each of A–E is individually load-bearing (a near-miss
# fixture that fails exactly one check is rejected) and that a real drive-hook passes + stays silent.
#
# SCOPE (honest): this is an anti-DRIFT presence-of-instruction check on TRUSTED first-party hook
# text — it defends against the hook regressing to reactive-only, the real failure mode. It does NOT
# adjudicate semantic contradiction: a first-party hook that says "loop … but actually only once" is
# a code-review concern, not something a deterministic grep can catch. Whether an LLM then obeys the
# instruction is inherently non-deterministic and lives in the on-demand live tier, never the suite.
#   usage: hook-drives-loop.sh [<hook-path>]   (default: repo plugin/hooks/heartbeat-detect.sh)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# assert_drives <hook-path> : 0 iff the hook carries the drive-loop instruction (checks A–E)
assert_drives() {
  local hook="$1" d out norm
  d="$(mktemp -d)"; mkdir -p "$d/.hb"; : > "$d/.hb/hb.js"    # minimal HeartBeat marker
  out="$(CLAUDE_PROJECT_DIR="$d" bash "$hook" 2>/dev/null)"
  rm -rf "$d"
  norm="$(printf '%s' "$out" | tr '\n' ' ' | tr -s ' ')"     # join wrapped lines for proximity
  printf '%s' "$norm" | grep -qi  "HeartBeat"                                              || return 1  # A: fires
  printf '%s' "$norm" | grep -qiE '(run|re-?run|execute|invoke|call).{0,30}tick\.sh'       || return 1  # B: re-run the tick
  printf '%s' "$norm" | grep -qiE '(loop|again|repeat|repeatedly|keep going)'              || return 1  # C: as a loop
  printf '%s' "$norm" | grep -q   'all_done'                                               || return 1  # D: success stop
  printf '%s' "$norm" | grep -qE  'gate_blocked|build_stuck|deadlock|review_stuck'         || return 1  # E: human stop
  return 0
}

# assert_silent_nonhb <hook-path> : 0 iff the hook prints nothing when there is no .hb/
assert_silent_nonhb() {
  local hook="$1" d out
  d="$(mktemp -d)"                                            # no .hb/
  out="$(CLAUDE_PROJECT_DIR="$d" bash "$hook" 2>/dev/null)"
  rm -rf "$d"
  [ -z "$out" ]
}

# emit a hook that prints $1 on a .hb/ project (used to build selftest fixtures)
mkhook() { printf '#!/usr/bin/env bash\nDIR="${CLAUDE_PROJECT_DIR:-$PWD}"\n[ -f "$DIR/.hb/hb.js" ] && printf %%s %s\nexit 0\n' "$(printf '%q' "$1")" > "$2"; }

if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  # Each near-miss fails EXACTLY one of A–E (so removing that check would let it pass → teeth).
  mkhook "Run bash .hb/tick.sh again in a loop until all_done or gate_blocked."            "$d/missA.sh"  # no "HeartBeat"
  mkhook "HeartBeat. Keep looping again and again until all_done or gate_blocked; see PROTOCOL." "$d/missB.sh"  # no tick.sh
  mkhook "HeartBeat. Run bash .hb/tick.sh after each action until all_done or gate_blocked." "$d/missC.sh"  # no loop word
  mkhook "HeartBeat. Run bash .hb/tick.sh again in a loop; stop for gate_blocked/build_stuck." "$d/missD.sh"  # no all_done
  mkhook "HeartBeat. Run bash .hb/tick.sh again in a loop until all_done."                  "$d/missE.sh"  # no human reason
  # the actual pre-fix regression: reactive-only (fails B and C)
  mkhook "HeartBeat. When a tick returns wakeAgent:true, act on data.reason."               "$d/reactive.sh"
  # a real drive-hook (all of A–E) — must PASS
  mkhook "HeartBeat. DRIVE the loop: after each action execute bash .hb/tick.sh again and act on the new reason. Keep looping until all_done or a human-needed reason (gate_blocked / build_stuck / deadlock / review_stuck)." "$d/good.sh"

  for f in missA missB missC missD missE reactive; do
    if assert_drives "$d/$f.sh"; then echo "SELFTEST FAIL: $f wrongly passed (a check is not load-bearing)"; exit 1; fi
  done
  assert_drives "$d/good.sh"       || { echo "SELFTEST FAIL: drive-hook wrongly rejected"; exit 1; }
  assert_silent_nonhb "$d/good.sh" || { echo "SELFTEST FAIL: drive-hook not silent on a non-HeartBeat dir"; exit 1; }
  echo "SELFTEST-OK: each of A–E is individually load-bearing; reactive-only rejected; a real drive-hook passes; silent off-project."
  exit 0
fi

HOOK="${1:-$ROOT/plugin/hooks/heartbeat-detect.sh}"
assert_drives "$HOOK"       || { echo "FAIL: the SessionStart hook does not carry the drive-loop instruction"; exit 1; }
assert_silent_nonhb "$HOOK" || { echo "FAIL: the hook is not silent on a non-HeartBeat dir"; exit 1; }
echo "HOOK-DRIVES-LOOP-OK"
