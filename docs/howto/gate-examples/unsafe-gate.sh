#!/usr/bin/env bash
# Proof for "Review an unsafe gate command": the auditor catches the two risky shapes a human
# reviewer must catch — a gate that WRITES its own evidence (side_effecting: it can fabricate a
# pass) and a gate that depends on network/time (nondeterministic: it flakes). A clean gate that
# only OBSERVES trips neither. Deterministic. Prints UNSAFE-GATE-OK only when hb audit reports
# side_effecting AND nondeterministic on the unsafe DAG, and NEITHER on the safe one.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/unsafe.json" <<'JSON'
{ "phases": [
    { "id": "P1", "gate_entry": null, "gate_exit": "G1", "tasks": [{ "id": "T1", "title": "do work producing out.txt", "requires": [] }] },
    { "id": "P2", "gate_entry": "G1", "gate_exit": "G2", "tasks": [{ "id": "T2", "title": "more work", "requires": [] }] } ],
  "gates": {
    "G1": { "desc": "writes its own evidence", "criteria": [{ "id": "c", "desc": "self-produced", "cmd": "touch \"$PROJECT_DIR/out.txt\" && test -f \"$PROJECT_DIR/out.txt\"" }] },
    "G2": { "desc": "depends on time", "criteria": [{ "id": "c", "desc": "clock", "cmd": "test \"$(date +%s)\" -gt 0" }] } } }
JSON

cat > "$tmp/safe.json" <<'JSON'
{ "phases": [
    { "id": "P1", "gate_entry": null, "gate_exit": "G1", "tasks": [{ "id": "T1", "title": "do work producing out.txt", "requires": [] }] } ],
  "gates": {
    "G1": { "desc": "observes only", "criteria": [{ "id": "c", "desc": "reads output", "cmd": "grep -q ok \"$PROJECT_DIR/out.txt\"" }] } } }
JSON

rules(){ node "$ROOT/plugin/templates/hb-audit.js" "$1" --json | python3 -c 'import sys,json;print(" ".join(sorted(set(x["rule"] for x in json.load(sys.stdin)["findings"]))))'; }

bad="$(rules "$tmp/unsafe.json")"
good="$(rules "$tmp/safe.json")"

case "$bad" in *side_effecting*) ;; *) echo "FAIL: auditor did not flag side_effecting on the unsafe DAG (got: $bad)"; exit 1;; esac
case "$bad" in *nondeterministic*) ;; *) echo "FAIL: auditor did not flag nondeterministic on the unsafe DAG (got: $bad)"; exit 1;; esac
case "$good" in *side_effecting*|*nondeterministic*) echo "FAIL: auditor flagged a safe read-only gate (got: $good)"; exit 1;; esac

echo "UNSAFE-GATE-OK: hb audit flags side_effecting + nondeterministic on the unsafe DAG and neither on the safe one."
