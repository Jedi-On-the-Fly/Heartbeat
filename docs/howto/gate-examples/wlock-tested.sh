#!/usr/bin/env bash
# Proof (R6): the write-lock provides real MUTUAL EXCLUSION over a read-modify-write critical section —
# the thing `mutate` relies on to not lose a state.json update under concurrency. Both runtimes.
#
# Why not just grep events.jsonl? Because appends are race-safe by construction (append-only, O_APPEND) —
# a proof that only checks both events landed would print OK even with the lock GUTTED to `return fn()`.
# The lock's actual job is serializing the read-modify-write of state.json (reproject → atomic replace).
# So this proof runs two concurrent workers through the REAL primitive (`withWlock` / `with_wlock`), each
# doing read → (forced overlap) → increment → write of a shared counter. Serialized ⇒ final == 2.
# Without the lock both read 0 and both write 1 ⇒ final == 1 (a lost update). The forced overlap makes
# that failure DETERMINISTIC, so gutting either lock turns this proof RED. Prints WLOCK-TESTED-OK.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
fail(){ echo "FAIL: $1"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# ── NODE: two concurrent workers through hb.js withWlock, RMW a counter ──
nd="$tmp/n"; mkdir -p "$nd"; printf 0 > "$nd/counter"
cat > "$tmp/nworker.js" <<'JS'
const hb = require(process.env.HBJS);
const fs = require('fs');
const cf = process.env.CF;
hb.withWlock(() => {
  const v = parseInt(fs.readFileSync(cf, 'utf8'), 10);              // read
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 150); // overlap window
  fs.writeFileSync(cf, String(v + 1));                             // write
});
JS
HBJS="$ROOT/plugin/templates/hb.js" HB_DIR="$nd" CF="$nd/counter" node "$tmp/nworker.js" &
HBJS="$ROOT/plugin/templates/hb.js" HB_DIR="$nd" CF="$nd/counter" node "$tmp/nworker.js" &
wait
nfin="$(cat "$nd/counter")"
[ "$nfin" = "2" ] || fail "node: withWlock did not serialize the RMW — counter=$nfin (expected 2; a lost update means the lock is a no-op)"

# ── PY: two concurrent workers through state.with_wlock, RMW a counter ──
pd="$tmp/p"; mkdir -p "$pd"; printf 0 > "$pd/counter"
cat > "$tmp/pworker.py" <<'PY'
import os, time
from heartbeat import state as st
cf = os.environ["CF"]
def rmw():
    v = int(open(cf).read())          # read
    time.sleep(0.15)                  # overlap window
    open(cf, "w").write(str(v + 1))   # write
st.with_wlock(os.environ["HBDIR"], rmw)
PY
HBDIR="$pd" CF="$pd/counter" python3 "$tmp/pworker.py" &
HBDIR="$pd" CF="$pd/counter" python3 "$tmp/pworker.py" &
wait
pfin="$(cat "$pd/counter")"
[ "$pfin" = "2" ] || fail "py: with_wlock did not serialize the RMW — counter=$pfin (expected 2; a lost update means the lock is a no-op)"

echo "WLOCK-TESTED-OK"
