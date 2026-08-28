#!/usr/bin/env bash
# Proof: a refuter panel is configured by the PROFILE's `verdict` field only — a `verdict` placed on
# the gate (inside the `review` block) is silently inert. Placing `verdict:{panel:3}` on the profile
# drives 3 refute dispatches; the SAME `verdict` on the gate's review drives just 1 (the single path).
# This pins the exact placement the how-to (tune-refuter-sensitivity.md) warns about, in BOTH runtimes.
# Prints REFUTER-VERDICT-PLACEMENT-OK. It goes RED if the executor ever starts honouring a gate-level
# verdict (the confusion the guide guards against). `--selftest` proves the 1-vs-N assertion is
# load-bearing. Prints SELFTEST-OK.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
unset HB_DIR DAG_FILE EVENTS_FILE HB_REFUTER 2>/dev/null || true
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# the assertion: a profile-placed verdict drives MORE THAN ONE dispatch; a gate-placed verdict is
# ignored (exactly one dispatch — the single-verdict path).
check_counts() { # <profileCount> <gateCount>
  [ "$1" -gt 1 ] || return 1
  [ "$2" -eq 1 ] || return 1
}

if [ "${1:-}" = "--selftest" ]; then
  check_counts 3 1 || fail "selftest: a correct (profile drives 3, gate ignored=1) reading was rejected"
  # profile verdict NOT driving the panel (1 dispatch) → must fail
  if check_counts 1 1; then fail "selftest: profile-verdict-inert (1,1) slipped past — the >1 check is not load-bearing"; fi
  # gate verdict WRONGLY honoured (3 dispatches) → must fail
  if check_counts 3 3; then fail "selftest: gate-verdict-honoured (3,3) slipped past — the ==1 check is not load-bearing"; fi
  echo "SELFTEST-OK"; exit 0
fi

export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
hbpy() { python3 -m heartbeat.cli "$@"; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# stub: execute writes out.txt; each refute call appends a line to $STUB_COUNTER, then clears
bindir="$work/bin"; mkdir -p "$bindir"
cat > "$bindir/stub" <<'STUB'
#!/usr/bin/env bash
mode="${1:-execute}"; cat >/dev/null 2>&1 || true
if [ "$mode" = execute ]; then echo ok > out.txt; echo '{"ok":true,"summary":"stub did the task"}'; exit 0; fi
echo x >> "$STUB_COUNTER"
echo '{"refuted":false,"findings":"stub refuter examined the phase and could not refute it, well over the forty character substance minimum"}'
STUB
chmod +x "$bindir/stub"

# verdict {panel:3} on the PROFILE (drives the panel)
DAG_PROFILE='{"phases":[{"id":"P0","gate_entry":null,"gate_exit":"GATE_P0","tasks":[{"id":"T1"}]}],"gates":{"GATE_P0":{"desc":"p","review":{"prompt":"refute the phase","profile":"panelprof"},"criteria":[{"id":"c","cmd":"grep -q ok \"$PROJECT_DIR/out.txt\""}]}}}'
PROF='{"persona":"PANEL persona reviews the phase","verdict":{"panel":3,"refute_if":"any"}}'
# the SAME verdict misplaced on the GATE's review block, with NO profile (must be ignored)
DAG_GATE='{"phases":[{"id":"P0","gate_entry":null,"gate_exit":"GATE_P0","tasks":[{"id":"T1"}]}],"gates":{"GATE_P0":{"desc":"p","review":{"prompt":"refute the phase","verdict":{"panel":3,"refute_if":"any"}},"criteria":[{"id":"c","cmd":"grep -q ok \"$PROJECT_DIR/out.txt\""}]}}}'

# count_dispatches <runtime> <profile|gate> -> number of refute invocations the executor made
count_dispatches() {
  local rt="$1" mode="$2" p
  p="$(mktemp -d)"
  if [ "$rt" = py ]; then hbpy init "$p" >/dev/null 2>&1; else bash "$ROOT/plugin/bootstrap.sh" "$p" >/dev/null 2>&1 </dev/null; fi
  mkdir -p "$p/.hb/refuters"
  if [ "$mode" = profile ]; then
    printf '%s' "$DAG_PROFILE" > "$p/.hb/dag.json"
    printf '%s' "$PROF"        > "$p/.hb/refuters/panelprof.json"
  else
    printf '%s' "$DAG_GATE"    > "$p/.hb/dag.json"
  fi
  : > "$p/counter"
  if [ "$rt" = py ]; then
    hbpy rebuild --dir "$p" >/dev/null 2>&1
    PATH="$bindir:$PATH" STUB_COUNTER="$p/counter" HB_EXEC_CMD="stub" HB_EXEC_MAX_ITERS=40 hbpy exec run --dir "$p" >/dev/null 2>&1
  else
    node "$p/.hb/hb.js" rebuild >/dev/null 2>&1
    PATH="$bindir:$PATH" STUB_COUNTER="$p/counter" HB_EXEC_CMD="stub" HB_EXEC_MAX_ITERS=40 node "$p/.hb/hb-exec.js" run >/dev/null 2>&1
  fi
  local n; n=$(grep -c x "$p/counter" 2>/dev/null || echo 0)
  rm -rf "$p"
  printf '%s' "$n"
}

for rt in py node; do
  cp="$(count_dispatches "$rt" profile)"
  cg="$(count_dispatches "$rt" gate)"
  check_counts "$cp" "$cg" || fail "$rt: profile-placed verdict must drive N dispatches (got $cp, want >1) and a gate-placed verdict must be IGNORED (got $cg, want 1)"
done

echo "REFUTER-VERDICT-PLACEMENT-OK"
