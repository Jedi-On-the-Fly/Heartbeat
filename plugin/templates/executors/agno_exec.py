#!/usr/bin/env python3
"""HeartBeat executor backend: Agno (https://github.com/agno-agi/agno).

Wire protocol (shared by every HeartBeat backend):
    driver -> backend:  argv[1] = "execute" | "refute" ; stdin = payload JSON
    backend -> driver:  ONE JSON object on stdout
        execute -> {"ok": bool,      "summary":  str}
        refute  -> {"refuted": bool, "findings": str}

One HeartBeat task == one Agno agent run. The backend does the work in the current
directory and NEVER touches .hb/ or gate.sh — the driver mediates all state. If the
`agno` package isn't installed, we still emit protocol-valid JSON so the driver can
route it (it will just count as a failed attempt / a non-refutation).
"""
import sys, os, json


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "execute"
    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}

    try:
        from agno.agent import Agent
        from agno.models.anthropic import Claude
    except Exception as e:  # agno not installed → graceful, protocol-valid degrade
        if mode == "refute":
            emit({"refuted": False, "findings": f"agno not installed ({e})"})
        else:
            emit({"ok": False, "summary": f"agno not installed ({e})"})
        return

    model_id = os.environ.get("HB_EXEC_MODEL", "claude-sonnet-4-6")
    ctx = payload.get("context", "")

    if mode == "refute":
        prompt = payload.get("prompt", "Refute that the phase is complete.")
        reviewer = Agent(
            model=Claude(id=model_id),
            instructions="You are a skeptical adversarial reviewer for a phase gate. "
                         "Hunt for hollow tests, criteria not truly met, or faked output. "
                         "End with the token REFUTED (you found a hole) or CLEAR.",
        )
        try:
            r = reviewer.run(f"{prompt}\n\nContext:\n{ctx}")
            text = getattr(r, "content", str(r))
            emit({"refuted": "REFUTED" in text.upper(), "findings": text[:500]})
        except Exception as e:
            emit({"refuted": False, "findings": f"reviewer error: {e}"})
    else:
        worker = Agent(
            model=Claude(id=model_id),
            instructions="You are a HeartBeat Stage-B worker. Do exactly one task, work in "
                         "the current directory, and never edit .hb/ or gate.sh.",
        )
        try:
            worker.run(f"{ctx}\n\nComplete this one task so the phase gate would pass, then stop.")
            emit({"ok": True, "summary": "agno agent completed the task"})
        except Exception as e:
            emit({"ok": False, "summary": f"agno run failed: {e}"})


if __name__ == "__main__":
    main()
