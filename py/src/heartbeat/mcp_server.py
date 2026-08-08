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

PROTOCOL_VERSION = "2025-06-18"

_EMPTY = {"type": "object", "properties": {}}


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
    if method == "initialize":
        return _result(mid, {
            "protocolVersion": params.get("protocolVersion", PROTOCOL_VERSION),
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "heartbeat", "version": __version__},
        })
    if method in ("notifications/initialized", "initialized"):
        return None
    if method == "tools/list":
        return _result(mid, {"tools": [
            {"name": n, "description": d, "inputSchema": s} for n, (_h, d, s) in TOOLS.items()
        ]})
    if method == "tools/call":
        name = params.get("name")
        args = params.get("arguments") or {}
        entry = TOOLS.get(name)
        if not entry:
            return _error(mid, -32602, f"unknown tool: {name}")
        try:
            out = entry[0](hb, args)
        except Exception as e:  # a tool failure is a tool result, not a protocol error
            return _result(mid, {"content": [{"type": "text", "text": str(e)}], "isError": True})
        return _result(mid, {"content": [{"type": "text", "text": json.dumps(out)}]})
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
