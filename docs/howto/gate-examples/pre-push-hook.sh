#!/usr/bin/env bash
# Proof: `bootstrap.sh` installs a BLOCKING pre-push hook that re-verifies every gate before a push.
# Asserts: the hook is installed + executable; it BLOCKS (exit non-zero) when gate re-verification fails
# and ALLOWS (exit 0) when it passes; it never CLOBBERS an existing pre-push; HB_NO_HOOK=1 bypasses it;
# and it installs on an EXISTING repo (not only a fresh git init). The block/allow outcome is isolated
# with a stub .hb/gate.sh (exit 1 vs 0), so the proof tests the hook's wiring, not a specific seed gate.
# Prints PRE-PUSH-HOOK-OK. Fails before the pre-push install exists (spec-first). Deterministic.
set -u
unset HB_NO_GIT HB_NO_HOOK   # the suite exports HB_NO_GIT=1; this proof tests git-hook install in isolated temp repos
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v git  >/dev/null 2>&1 || { echo "git absent";  exit 1; }
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
BOOT="$ROOT/plugin/bootstrap.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail(){ echo "FAIL: $1"; exit 1; }
run_hook(){ ( cd "$1" && "${@:2}" bash .git/hooks/pre-push origin fake://x </dev/null >/dev/null 2>&1 ); }

# ── fresh project: bootstrap git-inits and installs the hook ──
proj="$tmp/fresh"; mkdir -p "$proj"
bash "$BOOT" "$proj" >/dev/null 2>&1 || fail "bootstrap failed"
HOOK="$proj/.git/hooks/pre-push"
[ -x "$HOOK" ] || fail "pre-push hook not installed / not executable"

stub(){ printf '#!/usr/bin/env bash\nexit %s\n' "$1" > "$proj/.hb/gate.sh"; chmod +x "$proj/.hb/gate.sh"; }
# (b) BLOCK on a failing gate re-verify
stub 1; run_hook "$proj" && fail "hook did NOT block when gate.sh --all failed"
# (c) ALLOW on a passing gate re-verify
stub 0; run_hook "$proj" || fail "hook blocked when gate.sh --all passed"
# (d) NO DEAD-TERMINAL WINDOW: the hook must announce the sweep BEFORE running it. With a stub
# that HANGS, the preamble must already be visible while the sweep is still running — a silent
# multi-minute hook is indistinguishable from a hung push (real pushes were killed over this).
printf '#!/usr/bin/env bash\nsleep 30\nexit 0\n' > "$proj/.hb/gate.sh"; chmod +x "$proj/.hb/gate.sh"
hlog="$tmp/hook.out"; : > "$hlog"
( cd "$proj" && bash .git/hooks/pre-push origin fake://x </dev/null >"$hlog" 2>&1 ) & hpid=$!
sleep 2
grep -q "re-verifying" "$hlog" || { kill -9 "$hpid" 2>/dev/null; fail "hook was SILENT while the sweep ran — the preamble must print BEFORE gate.sh --all starts"; }
kill -9 "$hpid" 2>/dev/null; wait "$hpid" 2>/dev/null
# (d2) success surfaces the sweep's timed verdict (visible completion, not a silent exit 0)
printf '#!/usr/bin/env bash\necho "some criterion output"\necho "✅ ALL GATES PASS (read-only: 3 gate(s) in 7s)"\nexit 0\n' > "$proj/.hb/gate.sh"; chmod +x "$proj/.hb/gate.sh"
vout="$( cd "$proj" && bash .git/hooks/pre-push origin fake://x </dev/null 2>&1 )" || fail "hook blocked on a passing sweep (verdict passthrough)"
printf '%s' "$vout" | grep -q "ALL GATES PASS" || fail "hook success was silent — the timed ✅ verdict must be surfaced"
# (e) HB_NO_HOOK bypass: even with a failing gate, it exits 0
stub 1; run_hook "$proj" env HB_NO_HOOK=1 || fail "HB_NO_HOOK=1 did not bypass the hook"

# ── existing repo WITHOUT a pre-push: the feature still installs ──
ex="$tmp/existing"; mkdir -p "$ex"; git -C "$ex" init -q
bash "$BOOT" "$ex" >/dev/null 2>&1 || fail "bootstrap failed on an existing repo"
[ -x "$ex/.git/hooks/pre-push" ] || fail "hook not installed on an existing repo"

# ── existing repo WITH a pre-push: never clobbered ──
keep="$tmp/keep"; mkdir -p "$keep"; git -C "$keep" init -q
printf '#!/usr/bin/env bash\necho SENTINEL-DO-NOT-CLOBBER\nexit 0\n' > "$keep/.git/hooks/pre-push"
chmod +x "$keep/.git/hooks/pre-push"
bash "$BOOT" "$keep" >/dev/null 2>&1 || fail "bootstrap failed on a repo with an existing hook"
grep -q 'SENTINEL-DO-NOT-CLOBBER' "$keep/.git/hooks/pre-push" || fail "clobbered an existing pre-push hook"

echo "PRE-PUSH-HOOK-OK"
