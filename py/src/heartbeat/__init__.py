"""HeartBeat — tick-driven agent orchestration (pure-Python port).

Stage A (the tick) is cheap, deterministic code that reads settled reality and decides
whether to wake Stage B (a model/agent). A project is a DAG (dag.json): phases -> tasks
-> dependencies + behavioral gates. State is an event-sourced projection.

This package is the zero-node/zero-bash port: the orchestration substrate is pure
Python (stdlib-only core). Gate `cmd`s remain user-authored shell — the DAG contract.
"""
# Single-sourced from the installed package metadata (pyproject.toml); no second literal.
try:
    from importlib.metadata import version as _version, PackageNotFoundError
    try:
        __version__ = _version("heartbeat-hb")
    except PackageNotFoundError:
        __version__ = "0+unknown"   # running from a source tree without an install
except Exception:
    __version__ = "0+unknown"
