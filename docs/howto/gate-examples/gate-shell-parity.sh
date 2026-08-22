#!/usr/bin/env bash
# Proof: gate criteria run under the SAME shell in both runtimes. gate.sh uses `bash -c`; gate.py used
# `shell=True` (→ /bin/sh, often dash), so a bash-ism criterion ([[ ]], arrays) passed on node and was
# permanently blocked on Python — a silent cross-runtime divergence in the core verification primitive.
# Asserts a `[[ ]]` criterion yields the SAME verdict under node gate.sh and python gate, and that a
# FAILING gate surfaces a diagnostic (output not fully swallowed). Prints GATE-SHELL-PARITY-OK. Fails
# today (dash rejects `[[`). Deterministic.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# node bootstrap gives a .hb/gate.sh (python scaffolds are node-free); both runtimes read the same dag.json
p="$tmp/proj"; mkdir -p "$p"
HB_NO_GIT=1 bash "$ROOT/plugin/bootstrap.sh" "$p" >/dev/null 2>&1 || fail "bootstrap failed"
# a gate whose criterion is a BASH-ism (fails under dash) + a failing gate that echoes a diagnostic
python3 - "$p/.hb/dag.json" <<'PY'
import json, sys
p = sys.argv[1]
json.dump({"phases": [{"id": "P0", "gate_entry": None, "gate_exit": "GATE_SH",
                       "tasks": [{"id": "T1", "title": "t"}]}],
           "gates": {"GATE_SH": {"desc": "bash-ism", "criteria": [{"id": "c", "desc": "bashism", "cmd": "[[ 1 = 1 ]]"}]},
                     "GATE_FAIL": {"desc": "fails loudly", "criteria": [{"id": "d", "desc": "diag", "cmd": "echo GATE-DIAG-XYZ; false"}]}}},
          open(p, "w"))
PY
hb rebuild --dir "$p" >/dev/null 2>&1 || true

# node gate.sh vs python gate on the SAME bash-ism criterion → identical verdict
bash "$p/.hb/gate.sh" --check GATE_SH >/dev/null 2>&1; ns=$?
hb gate --check GATE_SH --dir "$p" >/dev/null 2>&1; ps=$?
[ "$ns" -eq 0 ] || fail "node gate.sh could not pass a [[ ]] criterion (unexpected)"
[ "$ps" -eq 0 ] || fail "python gate blocked a [[ ]] criterion node accepts — cross-runtime shell divergence (dash vs bash)"

# a failing gate surfaces a diagnostic (output not fully swallowed)
out="$(hb gate --check GATE_FAIL --dir "$p" 2>&1 || true)"
printf '%s' "$out" | grep -q 'GATE-DIAG-XYZ' || fail "python gate swallowed the failing criterion's output (no diagnostic)"

echo "GATE-SHELL-PARITY-OK"
