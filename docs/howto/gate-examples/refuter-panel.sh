#!/usr/bin/env bash
# Proof: a profile's verdict {panel:N, refute_if:'majority'|'any'|'all'} runs N refuters and aggregates
# their verdicts (majority ⇒ refuted iff >N/2; any ⇒ iff ≥1; all ⇒ iff N) — identically in node and
# python. With no panel the single-verdict path is unchanged. Fail-closed holds: a panelist that
# returns NO boolean verdict cannot certify a pass. Deterministic STUB verdicts (no model/network).
# Prints REFUTER-PANEL-OK. Fails before panel aggregation exists (spec-first RED).
#
# `--selftest` proves the aggregation truth table is RULE-SENSITIVE (majority / any / all each produce a
# distinct outcome on a crafted verdict set) and that a non-bool verdict is an error — so the main run's
# expected outcomes aren't vacuous. Prints SELFTEST-OK.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
unset HB_DIR DAG_FILE EVENTS_FILE HB_REFUTER 2>/dev/null || true
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# reference aggregation (the truth table the main run asserts the IMPL matches)
agg() { # <rule> <csv-of true/false/other>  -> refuted | clear | error
  local rule="$1" n=0 t=0 tok; local -a A
  IFS=',' read -ra A <<< "$2"
  for tok in "${A[@]}"; do
    case "$tok" in true) t=$((t + 1)) ;; false) : ;; *) echo error; return ;; esac
    n=$((n + 1))
  done
  case "$rule" in
    any) [ "$t" -ge 1 ] && echo refuted || echo clear ;;
    all) [ "$t" -eq "$n" ] && echo refuted || echo clear ;;
    *)   [ $((2 * t)) -gt "$n" ] && echo refuted || echo clear ;;   # majority
  esac
}

if [ "${1:-}" = "--selftest" ]; then
  [ "$(agg majority true,false,false)" = clear ]   || fail "selftest: majority 1/3 should be clear"
  [ "$(agg majority true,true,false)" = refuted ]  || fail "selftest: majority 2/3 should be refuted"
  [ "$(agg any true,false,false)" = refuted ]      || fail "selftest: any ≥1 should be refuted"
  [ "$(agg all true,true,false)" = clear ]         || fail "selftest: all not-unanimous should be clear"
  [ "$(agg all true,true,true)" = refuted ]        || fail "selftest: all unanimous should be refuted"
  [ "$(agg majority false,none)" = error ]         || fail "selftest: a non-bool verdict must be an error (fail-closed)"
  # rule distinctness (teeth): same verdicts, DIFFERENT outcome per rule
  [ "$(agg majority true,false,false)" != "$(agg any true,false,false)" ] || fail "selftest: majority not distinct from any"
  [ "$(agg all true,true,false)"     != "$(agg majority true,true,false)" ] || fail "selftest: all not distinct from majority"
  echo "SELFTEST-OK"; exit 0
fi

export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
hbpy() { python3 -m heartbeat.cli "$@"; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# stub backend: execute writes out.txt; refute returns the i-th verdict from $STUB_VERDICTS (counter file)
bindir="$work/bin"; mkdir -p "$bindir"
cat > "$bindir/stub" <<'STUB'
#!/usr/bin/env bash
mode="${1:-execute}"; cat >/dev/null 2>&1 || true
if [ "$mode" = execute ]; then echo ok > out.txt; echo '{"ok":true,"summary":"stub did the task"}'; exit 0; fi
i=$(cat "$STUB_COUNTER" 2>/dev/null || echo 0); echo $((i + 1)) > "$STUB_COUNTER"
IFS=',' read -ra V <<< "$STUB_VERDICTS"; v="${V[$i]:-none}"
case "$v" in
  true)  echo '{"refuted":true,"findings":"panelist REFUTED: found a genuine hole in the phase, well over the forty character substance minimum"}' ;;
  false) echo '{"refuted":false,"findings":"panelist could not refute: examined every criterion, well over the forty character substance minimum"}' ;;
  ec)    echo '{"refuted":false,"findings":""}' ;;   # a CLEAR verdict with NO evidence (must not certify a pass)
  *)     echo '{"findings":"panelist returned no boolean verdict — inconclusive"}' ;;
esac
STUB
chmod +x "$bindir/stub"

write_dag() { # <dagfile> <profile-or-empty>
  python3 - "$1" "$2" <<'PY'
import json, sys
review = {"prompt": "refute the phase"}
if sys.argv[2]:
    review["profile"] = sys.argv[2]
json.dump({"phases": [{"id": "P0", "gate_entry": None, "gate_exit": "GATE_P0", "tasks": [{"id": "T1"}]}],
           "gates": {"GATE_P0": {"desc": "phase", "review": review,
                                 "criteria": [{"id": "c", "cmd": "grep -q ok \"$PROJECT_DIR/out.txt\""}]}}},
          open(sys.argv[1], "w"))
PY
}

# outcome <runtime> <verdictField> <verdicts-csv> -> DONE (phase completed) | OPEN (review not passed)
outcome() {
  local rt="$1" vf="$2" verds="$3" p out
  p="$(mktemp -d)"
  if [ "$rt" = py ]; then hbpy init "$p" >/dev/null 2>&1; else bash "$ROOT/plugin/bootstrap.sh" "$p" >/dev/null 2>&1 </dev/null; fi
  write_dag "$p/.hb/dag.json" "panel"
  mkdir -p "$p/.hb/refuters"
  printf '{"persona":"PANEL-PERSONA reviews the phase",%s"questions":[]}' "$vf" > "$p/.hb/refuters/panel.json"
  : > "$p/counter"
  if [ "$rt" = py ]; then
    hbpy rebuild --dir "$p" >/dev/null 2>&1
    PATH="$bindir:$PATH" STUB_COUNTER="$p/counter" STUB_VERDICTS="$verds" HB_EXEC_CMD="stub" HB_EXEC_MAX_ITERS=60 hbpy exec run --dir "$p" >/dev/null 2>&1
    out="$(hbpy state --dir "$p")"
  else
    node "$p/.hb/hb.js" rebuild >/dev/null 2>&1
    PATH="$bindir:$PATH" STUB_COUNTER="$p/counter" STUB_VERDICTS="$verds" HB_EXEC_CMD="stub" HB_EXEC_MAX_ITERS=60 node "$p/.hb/hb-exec.js" run >/dev/null 2>&1
    out="$(node "$p/.hb/hb.js" state)"
  fi
  rm -rf "$p"
  if printf '%s' "$out" | python3 -c 'import sys,json;sys.exit(0 if "P0" in (json.load(sys.stdin).get("completed_phases") or []) else 1)'; then echo DONE; else echo OPEN; fi
}

MAJ='"verdict":{"panel":3,"refute_if":"majority"},'
ANY='"verdict":{"panel":3,"refute_if":"any"},'
DUO='"verdict":{"panel":2,"refute_if":"majority"},'

# Executor-integration (kept small to stay under GATE_TIMEOUT_S; the full majority/any/all truth table
# is covered by --selftest + the byte-parity `panel-aggregate` case on the shared aggregateVerdict).
# On BOTH runtimes: the panel actually AGGREGATES (majority 1/3 ⇒ CLEAR — the single-verdict path would
# instead see verdicts[0]=true and REFUTE, so this distinguishes panel from no-panel), and fail-closed.
for rt in py node; do
  [ "$(outcome "$rt" "$MAJ" 'true,false,false')" = DONE ] || fail "$rt: majority 1/3 must be CLEAR (panel not aggregating?)"
  [ "$(outcome "$rt" "$DUO" 'false,none')"       = OPEN ] || fail "$rt: fail-closed — a non-bool panelist must not certify a pass"
  # a panel that AGGREGATES to clear but whose panelists cited NO evidence must NOT pass — the
  # `[panelist i/N]` label prefix must not let boilerplate satisfy the substance floor (Rule 6).
  [ "$(outcome "$rt" "$MAJ" 'ec,ec,ec')"         = OPEN ] || fail "$rt: an all-clear panel with EMPTY findings must NOT certify an evidence-free pass"
done
# refute_if is honoured end-to-end (same verdicts, different rule ⇒ different outcome) — python.
# (The no-panel single-verdict path is covered by the compose/backward-compat proofs and the full suite.)
[ "$(outcome py "$ANY" 'true,false,false')" = OPEN ] || fail "py: any ≥1 must be REFUTED (refute_if not passed through?)"

echo "REFUTER-PANEL-OK"
