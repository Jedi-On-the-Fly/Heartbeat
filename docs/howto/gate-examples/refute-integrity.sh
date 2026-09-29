#!/usr/bin/env bash
# Proof: a DEGRADED refuter can never become a review pass, and a GENUINE review is not thrown away —
# in both runtimes. The adversarial review is the differentiator; it must survive its own failure modes.
# Asserts:
#   PY   — every framework backend whose lib is absent degrades to a SENTINEL (no boolean `refuted`),
#          not {"refuted": false} (which the executor would accept as "could not refute" → a pass).
#   NODE — claude-exec.sh: (a) with `claude` absent, the refute output is a SENTINEL (no bool refuted),
#          not a fail-open pass; (b) on a genuine CLEAR it carries the reviewer's ACTUAL text as findings
#          (≥40 chars, not the canned "reviewer could not refute" that dead-ends the ≥40 guard); (c) the
#          verdict is decided by the reply's final token, so prose that merely mentions "REFUTED" but
#          ends CLEAR is NOT scored as a refutation.
# Prints REFUTE-INTEGRITY-OK. Fails today (py fail-open; node degrade fail-open + clear dead-end + fragile
# verdict). Deterministic — no network; `claude` is stubbed.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
fail(){ echo "FAIL: $1"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CE="$ROOT/plugin/templates/executors/claude-exec.sh"
nobool(){ python3 -c "import json,sys; r=json.load(sys.stdin); sys.exit(0 if not isinstance(r.get('refuted'),bool) else 1)"; }
refuted_is(){ python3 -c "import json,sys; r=json.load(sys.stdin); sys.exit(0 if r.get('refuted') is ($1) else 1)"; }
findings(){ python3 -c "import json,sys; print(json.load(sys.stdin).get('findings',''))"; }

# ── PY: framework backends degrade to a sentinel (no bool refuted) ──
PYTHONPATH="$ROOT/py/src" python3 - <<'PY' || fail "py: a framework backend fails open on degrade (returns bool refuted:false when its lib is absent)"
import importlib, sys
mods = ["agno", "autogen", "crewai", "pydanticai", "smolagents", "langgraph", "openai_agents"]
bad = []
for m in mods:
    mod = importlib.import_module("heartbeat.backends." + m)
    r = mod.refute({"context": "x", "prompt": "y", "gate": "G"})   # lib absent in this env → degrade path
    blob = (str(r.get("findings", "")) + str(r.get("error", ""))).lower()
    degraded = ("unavailable" in blob) or ("error" in r) or ("not available" in blob)
    if degraded and isinstance(r.get("refuted"), bool):
        bad.append(f"{m}: fail-open (refuted={r['refuted']} on degrade)")
if bad:
    sys.stderr.write("; ".join(bad) + "\n"); sys.exit(1)
PY

# ── NODE: run claude-exec.sh with a claude-free PATH (a clean bin of only the tools it needs) ──
cleanbin="$tmp/cleanbin"; mkdir -p "$cleanbin"
for b in node cat grep tr head tail sed dirname bash env; do p="$(command -v "$b" 2>/dev/null)" && ln -sf "$p" "$cleanbin/$b"; done
command -v claude >/dev/null 2>&1 && [ ! -e "$cleanbin/claude" ] || true   # ensure the clean bin has NO claude
PATH="$cleanbin" bash -c 'command -v claude' >/dev/null 2>&1 && fail "proof setup: claude leaked into the clean PATH"

# (a) claude ABSENT → sentinel (no bool refuted), not a fail-open pass
printf '%s' '{"context":"c","prompt":"Refute G"}' | PATH="$cleanbin" bash "$CE" refute > "$tmp/degrade.json" 2>/dev/null
nobool < "$tmp/degrade.json" || fail "node: claude-exec.sh fails open on degrade (bool refuted:false when claude absent) — must be a sentinel"

# (b) genuine CLEAR with substantive text → refuted=false carrying the reviewer's ACTUAL text
sdir="$tmp/bin"; mkdir -p "$sdir"
cat > "$sdir/claude" <<'STUB'
#!/usr/bin/env bash
printf 'I examined the phase, the gate criteria, and the artifact in detail and found no hollow test or faked output.\n\nCLEAR\n'
STUB
chmod +x "$sdir/claude"
printf '%s' '{"context":"c","prompt":"Refute G"}' | PATH="$sdir:$cleanbin" bash "$CE" refute > "$tmp/clear.json" 2>/dev/null
refuted_is False < "$tmp/clear.json" || fail "node: a genuine CLEAR was not refuted=false"
f="$(findings < "$tmp/clear.json")"
[ "${#f}" -ge 40 ] || fail "node: CLEAR findings too short (${#f}) — the reviewer's real text was discarded (dead-end)"
printf '%s' "$f" | grep -q 'examined the phase' || fail "node: CLEAR findings do not carry the reviewer's actual text"

# (c) verdict robustness: prose mentions REFUTED but ends CLEAR → must be refuted=false
cat > "$sdir/claude" <<'STUB'
#!/usr/bin/env bash
printf 'The instructions say to end with REFUTED or CLEAR. I looked hard for a hole and could not find one.\nCLEAR\n'
STUB
chmod +x "$sdir/claude"
printf '%s' '{"context":"c","prompt":"Refute G"}' | PATH="$sdir:$cleanbin" bash "$CE" refute > "$tmp/verdict.json" 2>/dev/null
refuted_is False < "$tmp/verdict.json" || fail "node: verdict parse fooled by the word REFUTED in prose (scored a CLEAR as a refutation)"

echo "REFUTE-INTEGRITY-OK"
