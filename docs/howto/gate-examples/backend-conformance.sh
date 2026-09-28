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

# 3. MODEL ROUTING: the model a role runs on must reach the CLI (per-role models — the event log and the
#    per-model report record HB_EXEC_MODEL, so an adapter that drops it makes both lie). Fake CLIs log
#    their argv; each shell adapter and each in-process python backend, in every mode, must pass the
#    model with the CLI's flag when HB_EXEC_MODEL is set — and pass NO model flag when it is unset.
fake="$work/fakebin"; mkdir -p "$fake"
for cli in claude codex opencode; do
  printf '#!/usr/bin/env bash\ncat >/dev/null 2>&1 </dev/null; printf "%%s\\x1f" "$(basename "$0")" "$@" >> "$ROUTE_LOG"; printf "\\n" >> "$ROUTE_LOG"\necho "[{\\"id\\":\\"G1\\",\\"claim\\":\\"c\\",\\"subjects\\":[\\"a\\"],\\"violation\\":\\"v\\"}] CLEAR"\n' > "$fake/$cli"
  chmod +x "$fake/$cli"
done
route_ok(){ # <log> <cli> <flag> <model|-> → 0 iff every call of <cli> carries (or, with -, never carries) the flag+model
  python3 - "$@" <<'PY'
import sys
log, cli, flag, model = sys.argv[1:5]
calls = [l.rstrip("\n").split("\x1f")[:-1] for l in open(log) if l.strip()]
calls = [c for c in calls if c and c[0] == cli]
if not calls: sys.exit(1)
for c in calls:
    args = c[1:]
    has = any(args[i] == flag and i + 1 < len(args) and (model == "-" or args[i + 1] == model) for i in range(len(args)))
    if model == "-" and any(a == flag for a in args): sys.exit(1)
    if model != "-" and not has: sys.exit(1)
PY
}
for pair in "claude-exec.sh claude --model" "codex-exec.sh codex -m" "opencode-exec.sh opencode -m"; do
  set -- $pair; ad="$ROOT/plugin/templates/executors/$1"
  for mode in execute refute author; do
    log="$work/route.log"; : > "$log"
    ( cd "$(mktemp -d)" && printf '{"prompt":"p","context":"c"}' | PATH="$fake:$PATH" ROUTE_LOG="$log" HB_EXEC_MODEL="MX-$mode" bash "$ad" "$mode" >/dev/null 2>&1 )
    route_ok "$log" "$2" "$3" "MX-$mode" || fail "$1 $mode does not pass HB_EXEC_MODEL to $2 ($3) — a recorded model would not be the model that ran"
    : > "$log"
    ( cd "$(mktemp -d)" && printf '{"prompt":"p","context":"c"}' | env -u HB_EXEC_MODEL PATH="$fake:$PATH" ROUTE_LOG="$log" bash "$ad" "$mode" >/dev/null 2>&1 )
    route_ok "$log" "$2" "$3" - || fail "$1 $mode passes a model flag although no model was set (a substituted default)"
  done
done
for pair in "claude claude --model" "codex codex -m"; do
  set -- $pair
  for mode in execute refute author; do
    log="$work/route.log"; : > "$log"
    ( cd "$(mktemp -d)" && PATH="$fake:$PATH" ROUTE_LOG="$log" HB_EXEC_MODEL="MX-$mode" PYTHONPATH="$ROOT/py/src" python3 -c '
import sys; from heartbeat import executor
executor.dispatch({"backend": sys.argv[1], "cmd": None, "heartbeat_s": 60}, sys.argv[2], {"prompt": "p", "context": "c"}, ".hb", None)' "$1" "$mode" >/dev/null 2>&1 )
    route_ok "$log" "$2" "$3" "MX-$mode" || fail "in-process backend $1 $mode does not pass HB_EXEC_MODEL to $2 ($3)"
  done
done
n=$((n + 1))

echo "BACKEND-CONFORMANCE-OK:$n (every shipped adapter — python and shell — conforms in degrade mode incl. author + unknown-mode refusal; the role model reaches the CLI; non-conformant backends rejected)."
