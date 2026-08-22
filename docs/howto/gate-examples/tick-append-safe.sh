#!/usr/bin/env bash
# Proof (LK): tick.sh appends informational events (wake / lease_expired / review_wake / log_event) to
# events.jsonl via a RAW `echo "{json}" >> "$EVENTS"` OUTSIDE the write-lock (tick.sh:72/181/338/388).
# That is SAFE by design: a POSIX O_APPEND write of a short line (< PIPE_BUF, 4096) is atomic, so
# concurrent appends never tear or lose a line; and state.json is a full re-fold of events.jsonl
# (reproject), so it stays eventually-consistent without the lock. The write-lock only needs to guard the
# state.json read-modify-write (mutate = append_event → reproject → atomic write), which T139 proves.
#
# This proof demonstrates all of that:
#   (a) many concurrent appends via the EXACT tick.sh idiom → every line valid JSON, none lost, none torn;
#   (b) several real `bash tick.sh` run concurrently on one project → events.jsonl stays all-valid-JSON;
#   (c) --selftest: a NON-atomic read-concat-write writer LOSES updates under the same concurrency,
#       proving the test methodology has teeth (it would catch corruption if it existed).
# Prints TICK-APPEND-SAFE-OK (main) / SELFTEST-OK (--selftest).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fail(){ echo "FAIL: $1"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# ── (c) --selftest: prove a NON-atomic writer corrupts, so (a) is not vacuous ──
if [ "${1:-}" = "--selftest" ]; then
  f="$tmp/na"; : > "$f"
  na_write(){ local cur; cur="$(cat "$f")"; printf '%s%s\n' "$cur" "x" > "$f"; }  # read-concat-write (NOT append)
  M=40
  for _ in $(seq 1 "$M"); do na_write & done; wait
  got="$(tr -cd 'x' < "$f" | wc -c | tr -d ' ')"
  [ "$got" -lt "$M" ] || fail "non-atomic writer did NOT lose updates ($got == $M) — selftest cannot show teeth on this box"
  echo "SELFTEST-OK: a non-atomic read-concat-write lost updates under concurrency ($got < $M); atomic >> does not"
  exit 0
fi

# ── (a) concurrent atomic appends via the exact tick.sh idiom ──
ev="$tmp/events.jsonl"; : > "$ev"
TS="t"; N=60
for i in $(seq 1 "$N"); do
  # identical form to tick.sh log_event/lease_expired/wake: echo "{...}" >> "$EVENTS"
  ( echo "{\"ts\":\"$TS\",\"event\":\"probe\",\"id\":\"$i\"}" >> "$ev" ) &
done
wait
python3 - "$ev" "$N" <<'PY' || fail "concurrent >> appends corrupted the log (torn/lost/duplicated line)"
import json, sys
path, n = sys.argv[1], int(sys.argv[2])
lines = [l for l in open(path).read().splitlines() if l.strip()]
assert len(lines) == n, f"line count {len(lines)} != {n} (lost or duplicated an append)"
ids = set()
for l in lines:
    o = json.loads(l)           # a torn/interleaved line fails here
    ids.add(o["id"])
assert ids == {str(i) for i in range(1, n + 1)}, "id set mismatch (an append was lost or overwritten)"
PY

# ── (b) real concurrent ticks don't corrupt events.jsonl ──
proj="$tmp/p"
HB_NO_GIT=1 bash "$ROOT/plugin/bootstrap.sh" "$proj" >/dev/null 2>&1 || fail "bootstrap"
for _ in $(seq 1 8); do ( cd "$proj" && bash .hb/tick.sh >/dev/null 2>&1 ) & done
wait
python3 - "$proj/.hb/events.jsonl" <<'PY' || fail "concurrent real ticks corrupted events.jsonl"
import json, sys
for l in open(sys.argv[1]):
    if l.strip():
        json.loads(l)           # every line still parses → no torn append under the real tick path
PY

echo "TICK-APPEND-SAFE-OK"
