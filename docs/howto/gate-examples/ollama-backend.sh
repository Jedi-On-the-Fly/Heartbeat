#!/usr/bin/env bash
# Proof for "Use HeartBeat with Ollama": the real ollama backend drives a task to a passing
# gate, offline, with no API key. To stay deterministic the MODEL is mocked — a tiny local
# HTTP server stands in for Ollama's /api/generate and returns a canned FILE-block — but the
# adapter (HTTP request, response parse, file write), the driver, and the gate are all real.
# For a genuinely live run, see use-heartbeat-with-ollama.md. Prints OLLAMA-BACKEND-OK.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/py/src" HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
hb(){ python3 -m heartbeat.cli "$@"; }
fail(){ echo "FAIL: $1"; exit 1; }

work="$(mktemp -d)"; mockpid=""
cleanup(){ [ -n "$mockpid" ] && kill "$mockpid" 2>/dev/null; rm -rf "$work"; }
trap cleanup EXIT

# Mock Ollama: bind an OS-assigned port (no fixed-port flakiness); every /api/generate returns
# a canned FILE-block that writes out.txt with "ok" — i.e. a "model" that does the task.
cat > "$work/mock.py" <<'PY'
import http.server, json, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', 0)))
        body = json.dumps({"response": "===FILE: out.txt===\nok\n===END==="}).encode()
        self.send_response(200); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
srv = http.server.HTTPServer(('127.0.0.1', 0), H)
open(sys.argv[1], 'w').write(str(srv.server_address[1]))
srv.serve_forever()
PY
python3 "$work/mock.py" "$work/port" & mockpid=$!
for _ in $(seq 1 50); do [ -s "$work/port" ] && break; sleep 0.1; done
port="$(cat "$work/port" 2>/dev/null)"; [ -n "$port" ] || fail "mock ollama server did not start"

mkproj(){ local p; p="$(mktemp -d)"; hb init "$p" >/dev/null 2>&1
  python3 -c 'import json,sys;json.dump({"phases":[{"id":"P0","gate_entry":None,"gate_exit":"GATE_P0","tasks":[{"id":"T1","title":"produce out.txt"}]}],"gates":{"GATE_P0":{"desc":"g","criteria":[{"id":"c","cmd":"grep -q ok \"$PROJECT_DIR/out.txt\""}]}}},open(sys.argv[1],"w"))' "$p/.hb/dag.json"
  hb rebuild --dir "$p" >/dev/null 2>&1; echo "$p"; }
done_P0(){ hb state --dir "$1" | python3 -c "import sys,json;sys.exit(0 if 'P0' in json.load(sys.stdin).get('completed_phases',[]) else 1)"; }

# Drive the REAL ollama backend against the mock model -> the phase completes via its gate.
p="$(mkproj)"
OLLAMA_HOST="http://127.0.0.1:$port" HB_EXEC_BACKEND=ollama HB_EXEC_MAX_ITERS=25 hb exec run --dir "$p" >/dev/null 2>&1
done_P0 "$p" || fail "the ollama backend did not drive the task to a passing gate against the mock model"
rm -rf "$p"

# Control: pointed at a dead host the backend degrades and the phase does NOT complete.
p="$(mkproj)"
OLLAMA_HOST="http://127.0.0.1:9" HB_EXEC_BACKEND=ollama HB_EXEC_ATTEMPT_CAP=2 HB_EXEC_MAX_ITERS=25 hb exec run --dir "$p" >/dev/null 2>&1
done_P0 "$p" && fail "control: the phase completed with the ollama server unreachable — degrade is broken"
rm -rf "$p"

echo "OLLAMA-BACKEND-OK: the real ollama backend completes a gated task against a mock model; a dead host degrades."
