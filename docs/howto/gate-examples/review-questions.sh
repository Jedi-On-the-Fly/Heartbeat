#!/usr/bin/env bash
# Proof: `hb-audit --questions <gate>` derives, from each criterion's CLASS, a targeted "how could this
# FALSELY pass?" question — different for existence / grep-of-source / coverage-grep / behavioral — plus
# one general phase question quoting the gate's claim. node ≡ python. Prints REVIEW-QUESTIONS-OK.
# Fails before the --questions mode exists (spec-first).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
FX="$ROOT/plugin/templates/fixtures/questions.dag.json"

out="$(node "$ROOT/plugin/templates/hb-audit.js" "$FX" --questions GATE_P0)"

# the QUESTION TEXT for a criterion (the line after "  - <id>: "), so checks are LINE-ANCHORED to
# the right criterion and we can compare the texts for distinctness.
qtext() { printf '%s\n' "$out" | sed -nE "s/^  - $1: (.*)/\1/p"; }
qe="$(qtext c_exist)"; qg="$(qtext c_grep)"; qc="$(qtext c_cov)"; qb="$(qtext c_behav)"
[ -n "$qe" ] && [ -n "$qg" ] && [ -n "$qc" ] && [ -n "$qb" ] || { echo "FAIL: a criterion has no question line"; echo "$out"; exit 1; }

# each criterion's OWN question is class-appropriate (anchored to that criterion, not anywhere in output)
printf '%s' "$qe" | grep -qiE 'presence|empty|placeholder' || { echo "FAIL: c_exist not an existence-class question: $qe"; exit 1; }
printf '%s' "$qg" | grep -qiE 'stub|hollow|executed'       || { echo "FAIL: c_grep not a grep-of-source question: $qg"; exit 1; }
printf '%s' "$qc" | grep -qiE 'passed|header|red run'      || { echo "FAIL: c_cov not a coverage-grep question: $qc"; exit 1; }
printf '%s' "$qb" | grep -qiE 'proxy|trivial'             || { echo "FAIL: c_behav not a behavioral question: $qb"; exit 1; }

# the four questions must be DISTINCT — a collapse-to-one-generic-line would fail here (teeth vs a
# synchronized both-runtime mutation, independent of the parity check).
[ "$(printf '%s\n' "$qe" "$qg" "$qc" "$qb" | sort -u | wc -l)" -eq 4 ] || { echo "FAIL: criteria questions are not distinct (collapsed to a generic line?)"; echo "$out"; exit 1; }

# a general phase-level question that quotes the gate claim
printf '%s\n' "$out" | grep -qi 'rename feature works end to end' || { echo "FAIL: no general phase question quoting the gate desc"; echo "$out"; exit 1; }

# node ≡ python (byte-equal; trailing newline normalized by command substitution)
py="$(PYTHONPATH="$ROOT/py/src" python3 -c 'import json,sys; from heartbeat.audit import review_questions as rq; sys.stdout.write(rq(json.load(open(sys.argv[1])), "GATE_P0"))' "$FX")"
[ "$out" = "$py" ] || { echo "FAIL: node vs python differ"; printf 'NODE=%s\n----\nPY=%s\n' "$out" "$py"; exit 1; }

echo "REVIEW-QUESTIONS-OK"
