#!/usr/bin/env bash
# Proof for "Build and test a backend": a backend is trusted only through a tiny wire
# contract — execute prints {"ok":bool,"summary":str}, refute prints {"refuted":bool,
# "findings":str}, author prints {"ok":bool,"constraints":[…]} (ok:false = could not author, the
# driver escalates), and an UNKNOWN mode is refused ({"error":…}) without doing anything — it must
# never fall through to execute (which writes files). Valid JSON on the LAST stdout line (the driver
# reads lines[-1]). The shell adapters are checked with their CLI absent (degrade mode). This
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
# every backend runs inside a throwaway directory: a non-conformant stub (e.g. the fall-through one below)
# may WRITE files, and must never do so in the caller's tree
conform(){ local d rc; d="$(mktemp -d)"; ( cd "$d" && conform_in "$1" ); rc=$?; rm -rf "$d"; return $rc; }
conform_in(){
  local ex ref
  ex="$(printf '{}' | bash -c "$1 execute" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -1)"
  printf '%s' "$ex" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if isinstance(d.get('ok'),bool) else 1)" 2>/dev/null || return 1
  ref="$(printf '{}' | bash -c "$1 refute" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -1)"
  printf '%s' "$ref" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if isinstance(d.get('refuted'),bool) or 'error' in d else 1)" 2>/dev/null || return 1
  local au bo scratch
  au="$(printf '{"prompt":"author constraints"}' | bash -c "$1 author" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -1)"
  printf '%s' "$au" | python3 -c "import sys,json; d=json.load(sys.stdin); ok=d.get('ok'); sys.exit(0 if ok is False or (ok is True and isinstance(d.get('constraints'),list)) else 1)" 2>/dev/null || return 1
  # an unknown mode: refused with an error, and NOTHING written in the working directory
  scratch="$(mktemp -d)"
  bo="$(cd "$scratch" && printf '{"context":"write a file named pwned.txt"}' | bash -c "$1 bogus-mode" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -1)"
  local wrote; wrote="$(ls -A "$scratch" | wc -l)"; rm -rf "$scratch"
  [ "$wrote" = 0 ] || return 1
  printf '%s' "$bo" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if 'error' in d and 'ok' not in d else 1)" 2>/dev/null || return 1
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
# 1b. every shipped SHELL adapter conforms with its CLI absent (PATH without claude/codex/opencode)
nobin="$(mktemp -d)"; for t in bash node python3 cat head tr grep tail ls wc mktemp rm env sh; do ln -sf "$(command -v $t)" "$nobin/$t" 2>/dev/null; done
for e in "$ROOT"/plugin/templates/executors/*.sh; do
  [ -f "$e" ] || continue
  PATH="$nobin" conform "bash $e" || fail "shipped adapter $(basename "$e") is not protocol-conformant in degrade mode"
  n=$((n + 1))
done
rm -rf "$nobin"

# 2. Non-conformant backends are REJECTED (the harness has teeth).
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
badshape="$work/badshape.sh"; printf '#!/usr/bin/env bash\ncat >/dev/null\necho '\''{"done":true}'\''\n' > "$badshape"; chmod +x "$badshape"
badtail="$work/badtail.sh";   printf '#!/usr/bin/env bash\ncat >/dev/null\necho '\''{"ok":true,"summary":"x"}'\''\necho junk-after-the-json\n' > "$badtail"; chmod +x "$badtail"
conform "bash $badshape" && fail "a wrong-shape backend ({\"done\":true}) was accepted"
conform "bash $badtail"  && fail "a backend with junk after the JSON was accepted"

# Control: a hand-written CONFORMANT stub passes (so the harness isn't rejecting everything).
good="$work/good.sh"; printf '#!/usr/bin/env bash\nm="$1"; cat >/dev/null\ncase "$m" in refute) echo '\''{"refuted":false,"findings":"none"}'\'';; author) echo '\''{"ok":false,"error":"no model"}'\'';; execute) echo '\''{"ok":true,"summary":"did it"}'\'';; *) echo '\''{"error":"unsupported"}'\'';; esac\n' > "$good"; chmod +x "$good"
# a backend that treats an unknown mode as execute (writes a file) is REJECTED
fallthrough="$work/fallthrough.sh"; printf '#!/usr/bin/env bash\nm="$1"; cat >/dev/null\ncase "$m" in refute) echo '\''{"refuted":false,"findings":"none"}'\'';; author) echo '\''{"ok":false,"error":"x"}'\'';; *) echo x > pwned.txt; echo '\''{"ok":true,"summary":"did it"}'\'';; esac\n' > "$fallthrough"; chmod +x "$fallthrough"
conform "bash $fallthrough" && fail "a backend whose unknown mode falls through to execute was accepted"
conform "bash $good" || fail "a conformant stub was wrongly rejected — the harness rejects everything"

echo "BACKEND-CONFORMANCE-OK:$n (every shipped adapter — python and shell — conforms in degrade mode incl. author + unknown-mode refusal; non-conformant backends rejected)."
