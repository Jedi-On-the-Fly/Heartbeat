#!/usr/bin/env bash
# Deterministic corpus self-audit: the drift check we ran by hand, made schedulable.
# Two invariants over the how-to library:
#   (a) prose-integrity — every guide passes prose-check (links resolve, only real hb commands).
#   (b) referenced-proof integrity — every gate-examples/*.sh a guide names in its BODY exists AND
#       is wired (invoked) in tests/run-tests.sh. prose-check misses these: they're code-fence
#       paths, not markdown links — exactly how a proof can vanish or go dormant unnoticed.
# Prints SELF-AUDIT-OK:<guides>/<proofs> with real counts only when both hold; hard-fails on a
# zero count (a bad regex/empty glob must not pass vacuously). --selftest proves it has teeth.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }

# audit_corpus <guides_dir> <gate_examples_dir> <run_tests_file>
# findings → stderr; on success echoes "<guides> <proofs>" to stdout; returns nonzero on any finding.
audit_corpus() {
  local gdir="$1" gex="$2" rt="$3" findings=0 proofs=0 guides base r
  local mds; mds=$(ls "$gdir"/*.md 2>/dev/null)
  guides=$(printf '%s\n' "$mds" | grep -c .)
  [ "$guides" -gt 0 ] || { echo "  FINDING: no guides in $gdir" >&2; return 1; }
  # (a) prose-integrity over the whole set
  bash "$gex/prose-check.sh" $mds >/dev/null 2>&1 || { echo "  FINDING: prose-integrity failed on the library" >&2; findings=$((findings+1)); }
  # (b) referenced-proof integrity
  for r in $(grep -rhoE 'gate-examples/[a-z0-9_-]+\.sh' "$gdir"/*.md 2>/dev/null | sort -u); do
    proofs=$((proofs+1)); base=$(basename "$r")
    [ -f "$gex/$base" ]   || { echo "  FINDING: referenced proof missing: $r" >&2; findings=$((findings+1)); }
    grep -q "$base" "$rt" || { echo "  FINDING: referenced proof not wired in suite: $base" >&2; findings=$((findings+1)); }
  done
  [ "$proofs" -gt 0 ] || { echo "  FINDING: no referenced proofs found (regex/glob?)" >&2; return 1; }
  [ "$findings" -eq 0 ] || return 1
  printf '%s %s\n' "$guides" "$proofs"
}

if [ "${1:-}" = "--selftest" ]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/guides" "$tmp/gex"
  cp "$ROOT/docs/howto/gate-examples/prose-check.sh" "$tmp/gex/prose-check.sh"
  printf '#!/usr/bin/env bash\necho PRESENT-OK\n' > "$tmp/gex/present.sh"
  body() { for i in $(seq 1 20); do echo "Line $i of substantive content about gates and phases."; done; }
  { body; echo 'Prove it: `bash docs/howto/gate-examples/present.sh`.'; } > "$tmp/guides/clean.md"

  # 1) a guide referencing a MISSING proof must be flagged
  { body; echo 'Prove it: `bash docs/howto/gate-examples/does-not-exist.sh`.'; } > "$tmp/guides/missing.md"
  printf 'check "T" %s\n' "'bash gate-examples/present.sh | grep PRESENT-OK'" > "$tmp/rt.sh"
  out=$(audit_corpus "$tmp/guides" "$tmp/gex" "$tmp/rt.sh" 2>&1); rc=$?
  echo "$out" | grep -q "referenced proof missing: gate-examples/does-not-exist.sh" || { echo "SELFTEST FAIL: missing proof not flagged"; exit 1; }
  [ "$rc" -ne 0 ] || { echo "SELFTEST FAIL: missing proof did not fail the audit"; exit 1; }

  # 2) a guide referencing an existing-but-UNWIRED proof must be flagged
  rm "$tmp/guides/missing.md"
  printf 'nothing is wired here\n' > "$tmp/rt.sh"
  out=$(audit_corpus "$tmp/guides" "$tmp/gex" "$tmp/rt.sh" 2>&1); rc=$?
  echo "$out" | grep -q "not wired in suite: present.sh" || { echo "SELFTEST FAIL: unwired proof not flagged"; exit 1; }
  [ "$rc" -ne 0 ] || { echo "SELFTEST FAIL: unwired proof did not fail the audit"; exit 1; }

  echo "SELF-AUDIT-SELFTEST-OK: catches a missing proof and an existing-but-unwired proof."
  exit 0
fi

counts=$(audit_corpus "$ROOT/docs/howto" "$ROOT/docs/howto/gate-examples" "$ROOT/tests/run-tests.sh"); rc=$?
[ "$rc" -eq 0 ] || { echo "SELF-AUDIT-FINDINGS: corpus audit found issues (above)."; exit 1; }

# (c) parity cross-check — the #2 contract: node ≡ python on the shared surfaces. The corpus can
# be coherent while the two runtimes have silently diverged, so the self-audit must verify it too.
# Delegates to tests/parity.sh (fixed fixtures; its own teeth are the HB_PY_SRC self-test / T55).
# The generative oracle tests/parity-fuzz.sh (T75) is the deeper, on-demand version.
parity="skipped(no node)"
if command -v node >/dev/null 2>&1; then
  if bash "$ROOT/tests/parity.sh" >/dev/null 2>&1; then
    parity="ok"
  else
    echo "  FINDING: node<->python parity DIVERGED (tests/parity.sh)" >&2
    echo "SELF-AUDIT-FINDINGS: corpus audit found issues (above)."; exit 1
  fi
fi

set -- $counts
echo "SELF-AUDIT-OK:$1/$2 (parity:$parity) — $1 guides prose-clean; $2 referenced proofs exist and are wired; node ≡ python."
