#!/usr/bin/env bash
# Proof for "Build and test a backend": a backend is trusted only through a tiny wire
# contract — execute prints {"ok":bool,"summary":str}, refute prints {"refuted":bool,
# "findings":str}, as valid JSON on the LAST stdout line (the driver reads lines[-1]). This
# harness checks every shipped adapter conforms in degrade mode (list DERIVED from the
# executors directory) and that a non-conformant backend is REJECTED. Prints
# BACKEND-CONFORMANCE-OK:<n> only when every adapter conforms and the bad stubs are caught.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# Force degrade paths deterministically (frameworks absent here; point ollama at a dead host).
export OLLAMA_HOST="http://127.0.0.1:9"
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
fail(){ echo "FAIL: $1"; exit 1; }

# conform CMD -> 0 iff execute/refute both emit a protocol-valid JSON object on the last line.
conform(){
  local ex ref
  ex="$(printf '{}' | bash -c "$1 execute" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -1)"
  printf '%s' "$ex" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if isinstance(d.get('ok'),bool) else 1)" 2>/dev/null || return 1
  ref="$(printf '{}' | bash -c "$1 refute" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -1)"
  printf '%s' "$ref" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if isinstance(d.get('refuted'),bool) else 1)" 2>/dev/null || return 1
  return 0
}

# 1. Every shipped python adapter conforms in degrade mode (derived from the directory).
n=0
for e in "$ROOT"/plugin/templates/executors/*_exec.py; do
  [ -f "$e" ] || continue
  conform "python3 $e" || fail "shipped adapter $(basename "$e") is not protocol-conformant in degrade mode"
  n=$((n + 1))
done
[ "$n" -gt 0 ] || fail "no shipped adapters found to check"

# 2. Non-conformant backends are REJECTED (the harness has teeth).
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
badshape="$work/badshape.sh"; printf '#!/usr/bin/env bash\ncat >/dev/null\necho '\''{"done":true}'\''\n' > "$badshape"; chmod +x "$badshape"
badtail="$work/badtail.sh";   printf '#!/usr/bin/env bash\ncat >/dev/null\necho '\''{"ok":true,"summary":"x"}'\''\necho junk-after-the-json\n' > "$badtail"; chmod +x "$badtail"
conform "bash $badshape" && fail "a wrong-shape backend ({\"done\":true}) was accepted"
conform "bash $badtail"  && fail "a backend with junk after the JSON was accepted"

# Control: a hand-written CONFORMANT stub passes (so the harness isn't rejecting everything).
good="$work/good.sh"; printf '#!/usr/bin/env bash\nm="$1"; cat >/dev/null\n[ "$m" = refute ] && echo '\''{"refuted":false,"findings":"none"}'\'' || echo '\''{"ok":true,"summary":"did it"}'\''\n' > "$good"; chmod +x "$good"
conform "bash $good" || fail "a conformant stub was wrongly rejected — the harness rejects everything"

echo "BACKEND-CONFORMANCE-OK:$n (every shipped adapter conforms in degrade mode; non-conformant backends rejected)."
