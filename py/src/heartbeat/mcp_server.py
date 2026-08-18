"""`hb mcp-serve` — HeartBeat as a minimal MCP server over stdio.

A tiny, stdlib-only JSON-RPC 2.0 server speaking the MCP stdio transport
(newline-delimited JSON — one message per line). It exposes HeartBeat's read
and act operations as MCP tools that call the SAME library functions the CLI
calls, so any MCP-capable agent (Codex, Claude Code, …) can drive
tick / gate / state itself and act on the deterministic answer.

Deliberately no MCP SDK: the core stays stdlib-only. Act tools route every
state change through ``state.mutate`` — the mutate-only-through-the-log
invariant (AGENTS rule 1) holds inside the server exactly as in the CLI.
"""
import json
import sys

from . import state as st
from . import resolver as rv
from . import lint as lintmod
from . import gate as gatemod
from . import tick as tickmod
from . import report as reportmod
from . import doctor as doc
from . import audit as auditmod
from . import __version__

PROTOCOL_VERSION = "2025-06-18"                      # default/fallback handshake version
# Versions negotiated via the `initialize` handshake (all tools-compatible). A client that
# requests any of these gets it echoed; anything else is negotiated down to PROTOCOL_VERSION.
HANDSHAKE_VERSIONS = ("2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25")
# Versions negotiated the 2026 way (via `server/discover` / per-request _meta).
MODERN_VERSIONS = ("2026-07-28",)
# Advertised by server/discover, newest first.
DISCOVER_VERSIONS = ["2026-07-28", "2025-06-18"]
_PROTO_META = "io.modelcontextprotocol/protocolVersion"
_SERVERINFO_META = "io.modelcontextprotocol/serverInfo"
_SERVER_INFO = {"name": "heartbeat", "version": __version__}

_EMPTY = {"type": "object", "properties": {}}


def _req_version(msg):
    """The protocol version the client declared for THIS request (2026 path), or None."""
    meta = (msg.get("params") or {}).get("_meta") or {}
    return meta.get(_PROTO_META)


def _is_modern(msg):
    """True when the request declares a 2026-era protocol version (per-request, stateless)."""
    return _req_version(msg) in MODERN_VERSIONS


def _state(hb):
    return st.project(st.read_events(hb), st.read_dag(hb))


# ── read tools — each returns a JSON-serialisable result from the same
#    library function the CLI calls (identical data to `hb <cmd>`).
def _tick(hb, a):     return tickmod.tick(hb)
def _next(hb, a):     return rv.resolve(_state(hb), st.read_dag(hb), hb)
def _ready(hb, a):    return rv.ready_tasks(_state(hb), st.read_dag(hb), hb, int(a.get("n", 0) or 0))
def _stateview(hb, a): return _state(hb)
def _report(hb, a):   return reportmod.build(hb)
def _diagnose(hb, a): return {"diagnosis": doc.diagnose(hb, a.get("reason"))}
def _doctor(hb, a):   return doc.doctor(hb)
def _lint(hb, a):     return lintmod.lint(st.read_dag(hb))
def _audit(hb, a):    return auditmod.audit(st.read_dag(hb))


# name -> (handler, description, inputSchema). Act tools are appended in
# _register_act() so the read surface stands alone.
TOOLS = {
    "tick":     (_tick,      "Run one Stage-A tick; returns the next action (wakeAgent, reason, action).", _EMPTY),
    "next":     (_next,      "The single next eligible action (resolver.resolve).", _EMPTY),
    "ready":    (_ready,     "The concurrently-runnable task set.", {"type": "object", "properties": {"n": {"type": "integer", "description": "max tasks (0 = all)"}}}),
    "state":    (_stateview, "The projected project state (from the event log).", _EMPTY),
    "report":   (_report,    "A progress report (phases, tasks, gates).", _EMPTY),
    "diagnose": (_diagnose,  "Computed root cause + recovery steps for a blocked state.", {"type": "object", "properties": {"reason": {"type": "string"}}}),
    "doctor":   (_doctor,    "Integrity check (rot, drift, stale leases).", _EMPTY),
    "lint":     (_lint,      "Validate the DAG structure.", _EMPTY),
    "audit":    (_audit,     "Adversarial gate-quality review (hollow gates).", _EMPTY),
}


# ── domain-adapter read tools — code-aware planning + context, node-free (the adapters are a
#    parity surface: these reuse the same functions node uses; see docs/adapters.md). Pure over the
#    args, read-only (no state mutation).
def _deplint(hb, a):
    from heartbeat.adapters.code.deplint import deplint as _dl
    return _dl(a["dag"], a["codemap"])


def _code_context(hb, a):
    from heartbeat.adapters.code.codegraph_context import context_for
    return context_for(a["codemap"], a["task"])


TOOLS.update({
    "deplint": (_deplint,
                "Code-aware dep-lint: validate a dag's `requires` against a codemap "
                "(edges = symA depends on symB; tasks = task -> symbols); returns "
                "{missing, redundant, collision}. Advisory.",
                {"type": "object", "properties": {"dag": {"type": "object"}, "codemap": {"type": "object"}},
                 "required": ["dag", "codemap"]}),
    "code_context": (_code_context,
                     "Render a task's code subgraph as context text (the symbols it touches + their "
                     "direct neighbors), for feeding Stage B.",
                     {"type": "object", "properties": {"codemap": {"type": "object"}, "task": {"type": "string"}},
                      "required": ["codemap", "task"]}),
})


# ── act tools — every state change routes through the same library path the CLI
#    uses (state.mutate / the validated review path). No direct state.json writes.
def _gate(hb, a):
    return gatemod.run_gate(hb, a["gate"], check=bool(a.get("check", False)))


def _start(hb, a):
    t = a["task"]; st.acquire_lease(hb, t); st.mutate(hb, {"event": "task_started", "task": t}); return {"started": t}


def _done(hb, a):
    t = a["task"]; st.mutate(hb, {"event": "task_done", "task": t}); st.release_lease(hb, t); return {"done": t}


def _fail(hb, a):
    t = a["task"]; ev = {"event": "task_failed", "task": t}
    if a.get("reason"):
        ev["reason"] = a["reason"]
    st.mutate(hb, ev); st.release_lease(hb, t); return {"failed": t}


def _review(hb, a):
    """Delegate to the CLI's review path verbatim — the distinct-actor / artifact
    validation is security-sensitive and lives in one place."""
    import io
    import contextlib
    from . import cli
    argv = ["review", a["gate"], a["verdict"]]
    note = a.get("note")
    if note:
        argv += note if isinstance(note, list) else [note]
    if a.get("artifact"):
        argv += ["--artifact", a["artifact"]]
    argv += ["--dir", str(hb)]
    buf, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(err):
        rc = cli.main(argv)
    return {"ok": rc == 0, "stdout": buf.getvalue().strip(), "stderr": err.getvalue().strip()}


TOOLS.update({
    "gate":   (_gate,   "Run a behavioral gate; a pass records gate_passed via the log and advances the phase.",
               {"type": "object", "properties": {"gate": {"type": "string"}, "check": {"type": "boolean"}}, "required": ["gate"]}),
    "start":  (_start,  "Claim a task (lease + task_started event).",
               {"type": "object", "properties": {"task": {"type": "string"}}, "required": ["task"]}),
    "done":   (_done,   "Complete a task (task_done event + release the lease).",
               {"type": "object", "properties": {"task": {"type": "string"}}, "required": ["task"]}),
    "fail":   (_fail,   "Fail a task (task_failed event + release the lease).",
               {"type": "object", "properties": {"task": {"type": "string"}, "reason": {"type": "string"}}, "required": ["task"]}),
    "review": (_review, "Record an adversarial review verdict (a pass requires --artifact from a distinct actor).",
               {"type": "object", "properties": {"gate": {"type": "string"}, "verdict": {"type": "string", "enum": ["pass", "fail"]},
                                                 "artifact": {"type": "string"}, "note": {"type": "array", "items": {"type": "string"}}},
               "required": ["gate", "verdict"]}),
})


def _result(mid, result):
    return {"jsonrpc": "2.0", "id": mid, "result": result}


def _error(mid, code, message):
    return {"jsonrpc": "2.0", "id": mid, "error": {"code": code, "message": message}}


def _handle(hb, msg):
    """Return a JSON-RPC response dict, or None for a notification."""
    mid = msg.get("id")
    method = msg.get("method")
    params = msg.get("params") or {}
    modern = _is_modern(msg)
    if method == "initialize":
        # Negotiate: echo the requested handshake version iff we support it, else our default —
        # never claim a version we don't implement (no blind echo).
        requested = params.get("protocolVersion")
        negotiated = requested if requested in HANDSHAKE_VERSIONS else PROTOCOL_VERSION
        return _result(mid, {
            "protocolVersion": negotiated,
            "capabilities": {"tools": {}},
            "serverInfo": dict(_SERVER_INFO),
        })
    if method == "server/discover":                 # 2026 negotiation pivot
        return _result(mid, {
            "supportedVersions": list(DISCOVER_VERSIONS),
            "capabilities": {"tools": {}},
            "_meta": {_SERVERINFO_META: dict(_SERVER_INFO)},
        })
    if method in ("notifications/initialized", "initialized"):
        return None
    if method == "tools/list":
        res = {"tools": [
            {"name": n, "description": d, "inputSchema": s} for n, (_h, d, s) in TOOLS.items()
        ]}
        if modern:                                  # 2026 CacheableResult + resultType
            res.update(resultType="complete", ttlMs=0, cacheScope="private")
        return _result(mid, res)
    if method == "tools/call":
        name = params.get("name")
        args = params.get("arguments") or {}
        entry = TOOLS.get(name)
        if not entry:
            return _error(mid, -32602, f"unknown tool: {name}")
        try:
            out = entry[0](hb, args)
            res = {"content": [{"type": "text", "text": json.dumps(out)}]}
        except Exception as e:  # a tool failure is a tool result, not a protocol error
            res = {"content": [{"type": "text", "text": str(e)}], "isError": True}
        if modern:
            res["resultType"] = "complete"
        return _result(mid, res)
    if mid is None:
        return None  # unknown notification — ignore
    return _error(mid, -32601, f"unknown method: {method}")


def serve(hbdir, stdin=None, stdout=None):
    """Run the stdio JSON-RPC loop until stdin closes."""
    stdin = stdin if stdin is not None else sys.stdin
    stdout = stdout if stdout is not None else sys.stdout
    while True:
        raw = stdin.readline()          # readline (not `for line in`) — no read-ahead deadlock
        if not raw:                     # EOF: stdin closed
            break
        line = raw.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            stdout.write(json.dumps(_error(None, -32700, "parse error")) + "\n"); stdout.flush(); continue
        resp = _handle(hbdir, msg)
        if resp is not None:
            stdout.write(json.dumps(resp) + "\n"); stdout.flush()
    return 0


def _is_loopback_host(host):
    import ipaddress
    h = (host or "").strip().lower().strip("[]")
    if h == "localhost":
        return True
    try:                                  # exact IP parse — NOT a prefix match:
        return ipaddress.ip_address(h).is_loopback   # "127.0.0.1.evil.com" is not an IP → rejected
    except ValueError:
        return False


def _origin_ok(origin):
    """A browser sends Origin; a non-browser MCP client does not. Reject any Origin that
    isn't loopback — the DNS-rebinding defence the MCP spec requires of local HTTP servers."""
    if not origin:
        return True
    from urllib.parse import urlsplit
    try:
        return _is_loopback_host(urlsplit(origin).hostname)
    except ValueError:
        return False


def serve_http(hbdir, host="127.0.0.1", port=0, allow_remote=False):
    """Optional streamable-HTTP transport: a stdlib http.server endpoint that
    answers JSON-RPC POSTs through the same _handle dispatch as stdio. Minimal by
    design (single JSON response per POST; no SSE server-push). Binds, then prints
    the actual host:port to stderr as a readiness signal (supports --port 0).

    Security: validates the Origin header (DNS-rebinding) and refuses a non-loopback
    bind unless allow_remote is set — the endpoint is unauthenticated and can run gate
    shell-commands, so remote exposure must be explicit."""
    if not _is_loopback_host(host) and not allow_remote:
        sys.stderr.write(f"refusing to bind the MCP HTTP server to non-loopback host {host!r} "
                         f"without --allow-remote (unauthenticated endpoint can run gate shell-commands)\n")
        sys.stderr.flush()
        return 2
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass  # quiet

        def _send(self, obj, code=200):
            data = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_POST(self):
            if not _origin_ok(self.headers.get("Origin")):    # DNS-rebinding defence
                self._send(_error(None, -32001, "forbidden origin"), 403)
                return
            length = int(self.headers.get("Content-Length", 0) or 0)
            body = self.rfile.read(length).decode() if length else ""
            try:
                msg = json.loads(body)
            except ValueError:
                self._send(_error(None, -32700, "parse error"), 400)
                return
            pv = self.headers.get("mcp-protocol-version")      # modern detection over HTTP
            if pv:
                params = msg.get("params")
                if not isinstance(params, dict):
                    params = {}; msg["params"] = params
                meta = params.get("_meta")
                if not isinstance(meta, dict):
                    meta = {}; params["_meta"] = meta
                meta.setdefault(_PROTO_META, pv)
            resp = _handle(hbdir, msg)
            if resp is None:                       # a notification — no response body
                self.send_response(202)
                self.end_headers()
                return
            self._send(resp)

    httpd = ThreadingHTTPServer((host, port), Handler)
    bound_host, bound_port = httpd.server_address[0], httpd.server_address[1]
    sys.stderr.write(f"HeartBeat MCP server (HTTP) listening on {bound_host}:{bound_port}\n")
    sys.stderr.flush()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0
