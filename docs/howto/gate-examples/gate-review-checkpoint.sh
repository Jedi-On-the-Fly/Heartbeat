#!/usr/bin/env bash
# Proof: for a REVIEW-gated gate the commit+tag GATE_x is created ONLY at review acceptance, NOT at
# the deterministic pass; a NON-review gate still tags at the deterministic pass; node ≡ python.
# So `git reset --hard GATE_x` always restores a reviewed-good state. Prints CHECKPOINT-LIFECYCLE-OK.
# Fails on the current code (which tags at the deterministic pass).
set -uo pipefail
# This proof is ABOUT git tag timing, so it needs git enabled even when the test suite runs with
# HB_NO_GIT=1 by default. Enable git for this process + its children.
unset HB_NO_GIT; export HB_GIT_AUTOCOMMIT=1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
command -v git  >/dev/null 2>&1 || { echo "git absent"; exit 1; }

DAG='{ "phases": [
  {"id":"P0","title":"rev","gate_entry":null,"gate_exit":"GATE_REV","tasks":[{"id":"T0","requires":[]}]},
  {"id":"P1","title":"plain","gate_entry":"GATE_REV","gate_exit":"GATE_PLAIN","tasks":[{"id":"T1","requires":[]}]}
], "gates": {
  "GATE_REV":{"desc":"reviewed phase","review":{"prompt":"refute"},"criteria":[{"id":"r1","desc":"ok","cmd":"true"}]},
  "GATE_PLAIN":{"desc":"plain phase","criteria":[{"id":"p1","desc":"ok","cmd":"true"}]}
} }'
ART="Refutation attempt for GATE_REV / phase P0 / task T0: I tried to break the phase and could not — the criterion genuinely holds.
HOLES: none"

has_tag() { git -C "$1" tag -l "$2" | grep -q "^$2$"; }
seed() {  # ensure a valid HEAD so tags can point somewhere
  printf '%s' "$DAG" > "$1/.hb/dag.json"; printf '%s' "$ART" > "$1/refute.md"
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1 || git -C "$1" init -q
  git -C "$1" add -A >/dev/null 2>&1
  git -c user.name=t -c user.email=t@t -C "$1" commit -q --no-verify -m base >/dev/null 2>&1 || true
}

# ---------- node ----------
tn="$(mktemp -d)"; trap 'rm -rf "$tn" "${tp:-}"' EXIT
bash "$ROOT/plugin/bootstrap.sh" "$tn/p" >/dev/null 2>&1 </dev/null
seed "$tn/p"
bash "$tn/p/.hb/gate.sh" GATE_REV >/dev/null 2>&1 || { echo "FAIL(node): gate.sh GATE_REV errored"; exit 1; }
has_tag "$tn/p" GATE_REV && { echo "FAIL(node): GATE_REV tagged at the deterministic pass (must defer to review)"; exit 1; }
HB_ACTOR=reviewer node "$tn/p/.hb/hb.js" review GATE_REV pass --artifact refute.md >/dev/null 2>&1 || { echo "FAIL(node): hb review GATE_REV pass errored"; exit 1; }
has_tag "$tn/p" GATE_REV || { echo "FAIL(node): GATE_REV NOT tagged after review acceptance"; exit 1; }
bash "$tn/p/.hb/gate.sh" GATE_PLAIN >/dev/null 2>&1 || { echo "FAIL(node): gate.sh GATE_PLAIN errored"; exit 1; }
has_tag "$tn/p" GATE_PLAIN || { echo "FAIL(node): non-review GATE_PLAIN not tagged at the deterministic pass (regression)"; exit 1; }

# ---------- python ----------
if command -v python3 >/dev/null 2>&1; then
  tp="$(mktemp -d)"
  PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli init "$tp/p" >/dev/null 2>&1
  seed "$tp/p"
  PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli gate GATE_REV --dir "$tp/p" >/dev/null 2>&1
  has_tag "$tp/p" GATE_REV && { echo "FAIL(py): GATE_REV tagged at the deterministic pass (must defer to review)"; exit 1; }
  HB_ACTOR=reviewer PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli review GATE_REV pass --artifact refute.md --dir "$tp/p" >/dev/null 2>&1 || { echo "FAIL(py): review pass errored"; exit 1; }
  has_tag "$tp/p" GATE_REV || { echo "FAIL(py): GATE_REV NOT tagged after review acceptance"; exit 1; }
fi

echo "CHECKPOINT-LIFECYCLE-OK"
