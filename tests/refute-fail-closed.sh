#!/usr/bin/env bash
# refute-fail-closed.sh — a refute verdict is emitted ONLY when the reviewer actually gave one.
# A refutation that could not run (backend unreachable, framework missing, CLI crash) or whose reply
# carries no final REFUTED/CLEAR token must come back as {"error": …}, which the driver escalates
# (fail-closed) — never as {"refuted": false}, which the driver would accept as "could not refute".
# Also: the ollama backend sends an explicit context size (num_ctx) and refuses a verdict when the
# prompt filled it (a truncated prompt means the reviewer never saw the whole request).
# The verdict is the reply's final WHOLE-WORD, upper-case REFUTED/CLEAR: "unclear" or "all clear" is
# not a verdict (else a REFUTED reply that goes on to call something unclear reads as CLEAR). The
# opencode adapter reads the model's TEXT parts of its --format json stream only — a tool output
# (a file the reviewer read, a grep hit) is not the reviewer's verdict.
#   bash tests/refute-fail-closed.sh [case]   cases: degrade cli ollama token e2e (default: all)
# Prints <CASE>-OK per case and REFUTE-FAIL-CLOSED-OK when every case passes.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EX="$ROOT/plugin/templates/executors"
fail(){ echo "FAIL: $1"; exit 1; }
last(){ grep -v '^[[:space:]]*$' | tail -1; }
is_error(){ python3 -c "import sys,json; d=json.loads(sys.stdin.read() or '{}'); sys.exit(0 if 'error' in d and 'refuted' not in d else 1)"; }
is_verdict(){ python3 -c "import sys,json; d=json.loads(sys.stdin.read() or '{}'); sys.exit(0 if d.get('refuted') is $1 else 1)"; }
W=$(mktemp -d); trap 'rm -rf "$W"; [ -n "${MOCK_PID:-}" ] && kill "$MOCK_PID" 2>/dev/null' EXIT

case_degrade(){
  # every python adapter with its framework absent (no site-packages) + ollama at a dead host
  local n=0 f out
  for f in "$EX"/*_exec.py; do
    out=$(cd "$W" && printf '{"prompt":"Refute that the phase is done."}' | OLLAMA_HOST=http://127.0.0.1:9 python3 -S "$f" refute 2>/dev/null | last)
    printf '%s' "$out" | is_error || fail "degrade: $(basename "$f") refute emitted a verdict instead of an error: $out"
    n=$((n+1))
  done
  [ "$n" -ge 5 ] || fail "degrade: only $n python adapters found"
  echo "DEGRADE-OK $n"
}

case_cli(){
  # the shell adapters with a FAKE CLI on PATH: no verdict token → error; CLEAR → false; REFUTED → true
  local bin="$W/bin" a reply out
  mkdir -p "$bin"
  for a in claude codex; do   # opencode speaks a JSON event stream: its cases are in case_token
    for reply in "I looked around and have some thoughts but no conclusion." "Looks complete. CLEAR" "The gate is hollow. REFUTED"; do
      printf '#!/usr/bin/env bash\ncat >/dev/null 2>&1 </dev/null; printf %%s "%s"\n' "$reply" > "$bin/$a"; chmod +x "$bin/$a"
      out=$(cd "$W" && printf '{"prompt":"Refute."}' | PATH="$bin:$PATH" bash "$EX/$a-exec.sh" refute 2>/dev/null | last)
      case "$reply" in
        *REFUTED) printf '%s' "$out" | is_verdict True  || fail "cli: $a REFUTED reply → $out" ;;
        *CLEAR)   printf '%s' "$out" | is_verdict False || fail "cli: $a CLEAR reply → $out" ;;
        *)        printf '%s' "$out" | is_error         || fail "cli: $a reply without a verdict token → $out (must be an error)" ;;
      esac
    done
  done
  echo "CLI-OK"
}

case_token(){
  # the final token is whole-word and upper-case, in every parser (shell adapters, python adapters via
  # the ollama mock, the python package): a REFUTED reply that then says "unclear" stays REFUTED, and
  # a lower-case "all clear" is no verdict (an error)
  local bin="$W/tbin" a out
  mkdir -p "$bin"
  for a in claude codex; do
    printf '#!/usr/bin/env bash\ncat >/dev/null 2>&1 </dev/null; printf %%s "The gate is hollow. REFUTED. Whether the fix is trivial is unclear."\n' > "$bin/$a"; chmod +x "$bin/$a"
    out=$(cd "$W" && printf '{"prompt":"Refute."}' | PATH="$bin:$PATH" bash "$EX/$a-exec.sh" refute 2>/dev/null | last)
    printf '%s' "$out" | is_verdict True || fail "token: $a read 'unclear' as the final CLEAR → $out"
    printf '#!/usr/bin/env bash\ncat >/dev/null 2>&1 </dev/null; printf %%s "I checked it, all clear."\n' > "$bin/$a"; chmod +x "$bin/$a"
    out=$(cd "$W" && printf '{"prompt":"Refute."}' | PATH="$bin:$PATH" bash "$EX/$a-exec.sh" refute 2>/dev/null | last)
    printf '%s' "$out" | is_error || fail "token: $a read a lower-case 'clear' as a verdict → $out (must be an error)"
  done
  # opencode: the verdict comes from the model's text parts, never from a tool's output
  ev(){ python3 -c 'import json,sys
for kind, val in zip(sys.argv[1::2], sys.argv[2::2]):
    part = {"type": "text", "text": val} if kind == "text" else {"type": "tool", "tool": "read", "state": {"status": "completed", "output": val}}
    print(json.dumps({"type": "text" if kind == "text" else "tool_use", "part": part}))' "$@"; }
  for spec in "err|text|Some thoughts, no conclusion.|tool|const CLEAR = 1" \
              "True|text|The gate is hollow. REFUTED|tool|clear() is called" \
              "False|tool|REFUTED in a comment|text|I looked at every criterion. CLEAR"; do
    IFS='|' read -r want k1 v1 k2 v2 <<<"$spec"
    ev "$k1" "$v1" "$k2" "$v2" > "$W/oc.jsonl"
    printf '#!/usr/bin/env bash\ncase "$*" in *--help*) exit 0;; esac\ncat >/dev/null 2>&1 </dev/null; cat "%s"\n' "$W/oc.jsonl" > "$bin/opencode"; chmod +x "$bin/opencode"
    out=$(cd "$W" && printf '{"prompt":"Refute."}' | PATH="$bin:$PATH" bash "$EX/opencode-exec.sh" refute 2>/dev/null | last)
    if [ "$want" = err ]; then printf '%s' "$out" | is_error || fail "token: opencode took a verdict from a TOOL output → $out"
    else printf '%s' "$out" | is_verdict "$want" || fail "token: opencode $spec → $out"; fi
  done
  # python adapters (through ollama_exec.py and a mock server) share the parser
  cat > "$W/tmock.py" <<'EOF'
import json, sys, http.server
reply = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        out = json.dumps({"response": reply, "prompt_eval_count": 900, "done": True}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(out)
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
EOF
  local port r want
  for r in "True|Hollow. REFUTED. The rest is unclear." "err|Looks fine to me, all clear."; do
    want="${r%%|*}"; port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
    python3 "$W/tmock.py" "$port" "${r#*|}" & MOCK_PID=$!
    for i in $(seq 1 50); do python3 -c "import socket; socket.create_connection(('127.0.0.1',$port),0.2)" 2>/dev/null && break; sleep 0.1; done
    out=$(cd "$W" && printf '{"prompt":"Refute."}' | OLLAMA_HOST="http://127.0.0.1:$port" python3 "$EX/ollama_exec.py" refute 2>/dev/null | last)
    kill "$MOCK_PID" 2>/dev/null; wait "$MOCK_PID" 2>/dev/null; MOCK_PID=""
    if [ "$want" = err ]; then printf '%s' "$out" | is_error || fail "token: ollama_exec.py read a lower-case 'clear' as a verdict → $out"
    else printf '%s' "$out" | is_verdict True || fail "token: ollama_exec.py read 'unclear' as the final CLEAR → $out"; fi
  done
  # every python adapter carries the same parser (derived from the directory)
  local f
  for f in "$EX"/*_exec.py; do
    python3 - "$f" <<'EOF' || fail "token: $(basename "$f") parses the verdict differently"
import ast, sys
src = open(sys.argv[1]).read(); ns = {}
fn = next(n for n in ast.parse(src).body if isinstance(n, ast.FunctionDef) and n.name == "_verdict")
exec(compile(ast.Module([fn], []), sys.argv[1], "exec"), ns)
v = ns["_verdict"]
assert v("Hollow. REFUTED. The rest is unclear.") is True
assert v("all clear") is None and v("UNCLEAR") is None and v("") is None
assert v("**CLEAR**") is False and v("REFUTED.") is True
EOF
  done
  echo "TOKEN-OK"
}

case_ollama(){
  # a mock ollama /api/generate: records the request, answers per MOCK_MODE
  cat > "$W/mock.py" <<'EOF'
import json, sys, http.server
mode = sys.argv[2]; log = sys.argv[3]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        open(log, "w").write(json.dumps(body))
        ctx = (body.get("options") or {}).get("num_ctx") or 4096
        reply = {"clear": ("Looks complete. CLEAR", 900), "none": ("Some thoughts, no conclusion.", 900),
                 "full": ("Looks complete. CLEAR", ctx)}[mode]
        out = json.dumps({"response": reply[0], "prompt_eval_count": reply[1], "done": True}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(out)
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
EOF
  local port mode out
  for mode in clear none full; do
    port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
    python3 "$W/mock.py" "$port" "$mode" "$W/req.json" & MOCK_PID=$!
    for i in $(seq 1 50); do python3 -c "import socket; socket.create_connection(('127.0.0.1',$port),0.2)" 2>/dev/null && break; sleep 0.1; done
    out=$(cd "$W" && printf '{"prompt":"Refute."}' | OLLAMA_HOST="http://127.0.0.1:$port" python3 "$EX/ollama_exec.py" refute 2>/dev/null | last)
    kill "$MOCK_PID" 2>/dev/null; wait "$MOCK_PID" 2>/dev/null; MOCK_PID=""
    case "$mode" in
      clear) printf '%s' "$out" | is_verdict False || fail "ollama: a CLEAR reply → $out" ;;
      none)  printf '%s' "$out" | is_error         || fail "ollama: a reply without a verdict token → $out (must be an error)" ;;
      full)  printf '%s' "$out" | is_error         || fail "ollama: a prompt that filled the context → $out (must be an error: truncated)" ;;
    esac
    python3 -c "import json,sys; o=json.load(open('$W/req.json')).get('options') or {}; sys.exit(0 if int(o.get('num_ctx') or 0) >= 16384 else 1)" \
      || fail "ollama: the request carries no num_ctx >= 16384 (the server default 4096 truncates silently): $(cat "$W/req.json" | head -c 200)"
  done
  # an explicit HB_OLLAMA_NUM_CTX is honoured
  port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
  python3 "$W/mock.py" "$port" clear "$W/req.json" & MOCK_PID=$!
  for i in $(seq 1 50); do python3 -c "import socket; socket.create_connection(('127.0.0.1',$port),0.2)" 2>/dev/null && break; sleep 0.1; done
  (cd "$W" && printf '{"prompt":"Refute."}' | HB_OLLAMA_NUM_CTX=24576 OLLAMA_HOST="http://127.0.0.1:$port" python3 "$EX/ollama_exec.py" refute >/dev/null 2>&1)
  kill "$MOCK_PID" 2>/dev/null; wait "$MOCK_PID" 2>/dev/null; MOCK_PID=""
  python3 -c "import json,sys; sys.exit(0 if (json.load(open('$W/req.json')).get('options') or {}).get('num_ctx') == 24576 else 1)" \
    || fail "ollama: HB_OLLAMA_NUM_CTX not honoured"
  echo "OLLAMA-OK"
}

case_e2e(){
  # hb exec, a wrong implementation, the refuter unreachable: the gate must NOT be accepted
  local P="$W/proj"; mkdir -p "$P"; ( cd "$P" && git init -q && bash "$ROOT/plugin/bootstrap.sh" . >/dev/null 2>&1 )
  cat > "$P/.hb/dag.json" <<'EOF'
{"_meta":{"project":"refute fail-closed"},
 "gates":{"GATE_A":{"desc":"add(a,b) returns a+b","review":{"prompt":"Refute that add is correct."},
   "criteria":[{"id":"a1","desc":"add works on one case","cmd":"cd \"$PROJECT_DIR\" && python3 -c 'import m; assert m.add(1,1)==2'"}]}},
 "phases":[{"id":"A","title":"add","gate_entry":null,"gate_exit":"GATE_A","tasks":[{"id":"a","title":"write m.py","requires":[],"description":"Write m.py with add(a,b); the gate runs python3 -c 'import m; …'."}]}]}
EOF
  printf '#!/usr/bin/env bash\nmode="${!#}"; cat >/dev/null\n[ "$mode" = execute ] && { printf "def add(a,b):\\n    return 2\\n" > m.py; echo "{\\"ok\\":true,\\"summary\\":\\"wrote m.py\\"}"; exit 0; }\necho "{\\"error\\":\\"execute only\\"}"\n' > "$P/doer.sh"
  ( cd "$P" && git add -A && git -c user.name=t -c user.email=t@l commit -qm init )
  ( cd "$P" && OLLAMA_HOST=http://127.0.0.1:9 HB_EXEC_BACKEND=script HB_EXEC_CMD="bash $P/doer.sh" HB_REFUTE_BACKEND=ollama \
      timeout 120 node .hb/hb-exec.js run >/dev/null 2>&1 )
  grep -q '"event":"review_passed"' "$P/.hb/events.jsonl" && fail "e2e: an unreachable refuter PASSED the review"
  git -C "$P" tag | grep -qx GATE_A && fail "e2e: the gate was accepted (tagged) with no refutation"
  echo "E2E-OK"
}

sel="${1:-all}"
for c in degrade cli ollama token e2e; do
  if [ "$sel" = all ] || [ "$sel" = "$c" ]; then "case_$c" || exit 1; fi
done
[ "$sel" = all ] && echo "REFUTE-FAIL-CLOSED-OK"
exit 0
