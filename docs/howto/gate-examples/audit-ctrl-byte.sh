#!/usr/bin/env bash
# Proof: hb-audit FLAGS (error, exit 1) a criterion whose cmd/desc contains a \x1e or \x1f control
# byte — the gate runner's record-transport delimiters. The transport is newline-safe (T153), but a
# raw \x1e/\x1f byte in a cmd would still corrupt record framing and silently miscount; the auditor
# turns that impossible-but-catastrophic case into a LOUD error before the gate ever runs. node ≡
# python. Prints AUDIT-CTRL-BYTE-OK. RED before the `control_char` rule exists.
# `--selftest` proves the detector discriminates (fires iff a byte is present) and that BOTH \x1e and
# \x1f trigger it — each individually load-bearing. SELFTEST-OK.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# write a dag whose single criterion's cmd is clean, or carries a \x1e/\x1f byte ($2 = clean|us|rs)
mkdag() {
  python3 - "$1" "$2" <<'PY'
import json, sys
cmd = {"clean": "grep -q ok f", "us": "grep -q ok f\x1ftrue", "rs": "grep -q ok f\x1etrue"}[sys.argv[2]]
json.dump({"phases": [{"id": "P", "gate_entry": None, "gate_exit": "GATE_X", "tasks": [{"id": "t"}]}],
           "gates": {"GATE_X": {"criteria": [{"id": "c", "desc": "d", "cmd": cmd}]}}}, open(sys.argv[1], "w"))
PY
}
# rule names emitted by each runtime's auditor, sorted
# NB: hb-audit exits 1 when it finds an error — swallow that so pipefail doesn't mask the extractor.
rules_node() { { node "$ROOT/plugin/templates/hb-audit.js" "$1" --json 2>/dev/null || true; } | node -pe 'JSON.parse(require("fs").readFileSync(0)).findings.map(f=>f.rule).sort().join(",")'; }
rules_py()   { PYTHONPATH="$ROOT/py/src" python3 -c 'import json,sys;from heartbeat.audit import audit;print(",".join(sorted(f["rule"] for f in audit(json.load(open(sys.argv[1])))["findings"])))' "$1"; }

if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  mkdag "$d/clean.json" clean; mkdag "$d/us.json" us; mkdag "$d/rs.json" rs
  # discriminates: a clean cmd is NOT flagged; each control byte IS (each load-bearing)
  rules_py "$d/clean.json" | grep -q 'control_char' && fail "selftest: control_char fired on a clean cmd (not discriminating)"
  rules_py "$d/us.json"    | grep -q 'control_char' || fail "selftest: a \\x1f byte was NOT flagged (not load-bearing)"
  rules_py "$d/rs.json"    | grep -q 'control_char' || fail "selftest: a \\x1e byte was NOT flagged (not load-bearing)"
  echo "SELFTEST-OK"; exit 0
fi

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdag "$work/clean.json" clean; mkdag "$work/dirty.json" us

# a control byte is an ERROR: hb-audit exits non-zero and names the rule; a clean dag is fine (exit 0)
if node "$ROOT/plugin/templates/hb-audit.js" "$work/dirty.json" >/dev/null 2>&1; then fail "node hb-audit did NOT fail on a control-byte cmd"; fi
rules_node "$work/dirty.json" | grep -q 'control_char' || fail "node hb-audit did not flag the control_char rule"
node "$ROOT/plugin/templates/hb-audit.js" "$work/clean.json" >/dev/null 2>&1 || fail "node hb-audit wrongly failed a clean dag"
if PYTHONPATH="$ROOT/py/src" python3 -c 'import json,sys;from heartbeat.audit import audit;sys.exit(1 if audit(json.load(open(sys.argv[1])))["errors"] else 0)' "$work/dirty.json"; then fail "python audit did NOT report an error on a control-byte cmd"; fi

# node ≡ python findings (the auditor is a parity surface)
[ "$(rules_node "$work/dirty.json")" = "$(rules_py "$work/dirty.json")" ] || fail "auditor findings differ node vs python on a control-byte cmd"
[ "$(rules_node "$work/clean.json")" = "$(rules_py "$work/clean.json")" ] || fail "auditor findings differ node vs python on a clean cmd"

echo "AUDIT-CTRL-BYTE-OK"
