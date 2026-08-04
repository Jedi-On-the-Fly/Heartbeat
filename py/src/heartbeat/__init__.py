"""HeartBeat — tick-driven agent orchestration (pure-Python port).

Stage A (the tick) is cheap, deterministic code that reads settled reality and decides
whether to wake Stage B (a model/agent). A project is a DAG (dag.json): phases -> tasks
-> dependencies + behavioral gates. State is an event-sourced projection.

This package is the zero-node/zero-bash port: the orchestration substrate is pure
Python (stdlib-only core). Gate `cmd`s remain user-authored shell — the DAG contract.
"""
__version__ = "0.1.0"
