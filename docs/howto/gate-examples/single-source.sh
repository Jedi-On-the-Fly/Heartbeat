#!/usr/bin/env bash
# Proof (R3,R4): must-not-drift logic is single-sourced. R3: the reason→action protocol table in the
# heartbeat SKILL.md lists EXACTLY the reason keys in protocol.py (so the hand-copy can't drift). R4: the
# non-behavioral-criterion check has ONE definition — hb-audit.js exports it and hb-exec.js imports it
# (not a forked second copy). Prints SINGLE-SOURCE-OK. Fails today (hb-exec defines its own nonBehavioral).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
fail(){ echo "FAIL: $1"; exit 1; }
# R3: protocol keys == SKILL.md table reasons
pk="$(grep -oE '"[a-z_]+":' "$ROOT/py/src/heartbeat/protocol.py" | tr -d '":' | sort -u | tr '\n' ' ')"
sk="$(grep -oE '^\| `[a-z_]+`' "$ROOT/plugin/skills/heartbeat/SKILL.md" | tr -d '| `' | sort -u | tr '\n' ' ')"
[ -n "$pk" ] && [ "$pk" = "$sk" ] || fail "SKILL.md reason table drifted from protocol.py keys:\n  protocol=$pk\n  skill=$sk"
# R4: hb-exec.js imports nonBehavioral from hb-audit.js; does NOT define its own
grep -qE "require\('\./hb-audit\.js'\)" "$ROOT/plugin/templates/hb-exec.js" || fail "hb-exec.js does not require hb-audit.js"
grep -qE '^\s*function nonBehavioral' "$ROOT/plugin/templates/hb-exec.js" && fail "hb-exec.js still DEFINES its own nonBehavioral (forked — import hb-audit's instead)"
grep -qE 'function nonBehavioral' "$ROOT/plugin/templates/hb-audit.js" || fail "hb-audit.js does not define the canonical nonBehavioral"
grep -qE 'nonBehavioral' "$ROOT/plugin/templates/hb-audit.js" | head -1
node -e "const a=require('$ROOT/plugin/templates/hb-audit.js'); if(typeof a.nonBehavioral!=='function') process.exit(1)" || fail "hb-audit.js does not EXPORT nonBehavioral"
echo "SINGLE-SOURCE-OK"
