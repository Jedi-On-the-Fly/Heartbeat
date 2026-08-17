#!/usr/bin/env bash
# Proof: `hb viz --serve` is a LIVE, loopback-only DAG dashboard (node runtime).
# Unlike the baked dag-view.html snapshot, the server re-reads dag.json+state.json FRESH on
# every request, so a state change made THROUGH the CLI is reflected without regenerate/restart.
# Five sub-checks (all must pass to print the marker):
#   (1) server starts on an ephemeral port and answers GET /state
#   (2) LIVENESS  — P0T1 shows no t-done; after `hb done P0T1`, a second GET on the SAME
#                   server shows P0T1 with t-done (proves live re-read)
#   (3) SECURITY  — a non-loopback Origin is rejected 403, a loopback [::1] Origin accepted 200
#                   (DNS-rebinding defence; [::1] matches the py oracle / mcp-http proof)
#   (4) REFUSAL   — --serve --host 0.0.0.0 without --allow-remote exits non-zero with a refusal,
#                   before any socket is created (no listener can leak)
#   (5) SNAPSHOT  — snapshot mode (no --serve) still writes a self-contained dag-view.html
#                   with the verbatim T14 conditions: t-done AND P0T1, no external URL
# Prints VIZ-SERVE-OK only when all five pass.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl absent"; exit 1; }

tmp="$(mktemp -d)"
srv=""
cleanup(){ [ -n "$srv" ] && kill "$srv" 2>/dev/null || true; rm -rf "$tmp"; }
trap cleanup EXIT

HB_NO_GIT=1 bash "$ROOT/plugin/bootstrap.sh" "$tmp/proj" >/dev/null 2>&1 </dev/null
HB="$tmp/proj/.hb"

# (1) start the server on an ephemeral port; discover the port from its stdout
node "$HB/hb-viz.js" "$HB" --serve --port 0 >"$tmp/srv.log" 2>&1 &
srv=$!
port=""
for _ in $(seq 1 40); do
  port="$(grep -oE '127\.0\.0\.1:[0-9]+' "$tmp/srv.log" 2>/dev/null | head -1 | cut -d: -f2 || true)"
  [ -n "$port" ] && curl -s --max-time 1 "http://127.0.0.1:$port/state" >/dev/null 2>&1 && break
  kill -0 "$srv" 2>/dev/null || { echo "server exited early"; cat "$tmp/srv.log"; exit 1; }
  sleep 0.1
done
[ -n "$port" ] || { echo "server never bound a port"; cat "$tmp/srv.log"; exit 1; }
base="http://127.0.0.1:$port"

# (2) LIVENESS — before: P0T1 present, not done
before="$(curl -s --max-time 2 "$base/state")"
echo "$before" | grep -q P0T1            || { echo "FAIL: /state missing P0T1";        exit 1; }
echo "$before" | grep -q 't-done'        && { echo "FAIL: t-done present before done"; exit 1; }
node "$HB/hb.js" start P0T1 >/dev/null 2>&1
node "$HB/hb.js" done  P0T1 >/dev/null 2>&1
after="$(curl -s --max-time 2 "$base/state")"
echo "$after" | grep -q 't-done'         || { echo "FAIL: live re-read did not reflect hb done"; exit 1; }

# (3) SECURITY — a non-loopback Origin is rejected 403 (same running server)
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 -H 'Origin: http://evil.example' "$base/state")"
[ "$code" = "403" ]                      || { echo "FAIL: non-loopback Origin not rejected (got $code)"; exit 1; }
# a loopback Origin over IPv6 ([::1]) is ACCEPTED — matches the py oracle / mcp-http proof
okc="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 -H 'Origin: http://[::1]' "$base/state")"
[ "$okc" = "200" ]                       || { echo "FAIL: loopback [::1] Origin not accepted (got $okc)"; exit 1; }

# (4) REFUSAL — non-loopback bind without --allow-remote exits non-zero with a refusal, BEFORE
# any socket is created (the check precedes createServer, so no listener can leak — no port probe).
if node "$HB/hb-viz.js" "$HB" --serve --host 0.0.0.0 --port 0 >"$tmp/ref.log" 2>&1; then
  echo "FAIL: non-loopback bind was NOT refused"; exit 1
fi
grep -qi 'loopback\|refus' "$tmp/ref.log" || { echo "FAIL: no refusal message"; cat "$tmp/ref.log"; exit 1; }

# (5) SNAPSHOT REGRESSION — verbatim T14 conditions (runs after P0T1 is done)
node "$HB/hb-viz.js" "$HB" >/dev/null 2>&1
snap="$HB/dag-view.html"
grep -q 't-done' "$snap"                 || { echo "FAIL: snapshot missing t-done"; exit 1; }
grep -q 'P0T1'   "$snap"                 || { echo "FAIL: snapshot missing P0T1";   exit 1; }
grep -qE 'https?://' "$snap"             && { echo "FAIL: snapshot has an external URL"; exit 1; }

echo "VIZ-SERVE-OK"
