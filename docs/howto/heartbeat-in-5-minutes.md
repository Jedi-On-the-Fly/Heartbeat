# HeartBeat in 5 minutes

**Outcome:** one complete task → gate cycle — you'll init a project, describe one unit of
work with a *behavioral* gate, let a worker do it, and watch the phase advance only because
the gate passed.

Use the Python runtime (`pip install heartbeat-hb`, or `PYTHONPATH=py/src` from a clone). No
Claude Code required.

## 1. Init

```bash
hb init myproject
cd myproject          # run the rest of the walkthrough from inside the project
```

## 2. Describe one unit of work

Edit `.hb/dag.json` — one phase, one task, one **behavioral** gate (assert the work
*happened*, not that a file exists):

```json
{ "phases": [ { "id": "P0", "gate_exit": "GATE_P0",
                "tasks": [ { "id": "P0T1", "title": "produce out.txt with ok" } ] } ],
  "gates": { "GATE_P0": { "desc": "the work is done",
                          "criteria": [ { "id": "c", "cmd": "grep -q ok \"$PROJECT_DIR/out.txt\"" } ] } } }
```

Then `hb rebuild --dir .` to project the initial state, and `hb audit .hb/dag.json` to confirm
the gate is behavioral (see [writing-behavioral-gates.md](writing-behavioral-gates.md)).

## 3. Drive it

Point Stage B at any worker. The simplest is a script backend — a worker that does the task:

```bash
cat > worker.sh <<'EOF'
#!/usr/bin/env bash
cat >/dev/null                 # (the task payload arrives on stdin)
echo ok > "$(pwd)/out.txt"     # do the work
echo '{"ok":true,"summary":"done"}'
EOF
chmod +x worker.sh
HB_EXEC_CMD="$(pwd)/worker.sh" hb exec run --dir .
```

Or point at a real model instead — the DAG doesn't change:
[Ollama](use-heartbeat-with-ollama.md) (local) or [Claude Code](use-heartbeat-with-claude-code.md).

## 4. What HeartBeat did

The tick found the ready task, handed it to the worker, then ran the **gate** — and only
advanced the phase because `grep -q ok out.txt` passed. The worker's "I'm done" was never
trusted; the behavior was checked.

## 5. Prove it worked

```bash
hb state --dir .     # completed_phases: ["P0"]
```

The whole cycle — init → author → drive → gate → done — is proven end to end (with a control
that a worker which does *nothing* does **not** complete the phase) by
[`gate-examples/quickstart-e2e.sh`](gate-examples/quickstart-e2e.sh) → `QUICKSTART-OK`.

## Next

- Turn your own project into a DAG: [turn-a-plan-into-a-dag.md](turn-a-plan-into-a-dag.md).
- Kill it and continue: [stop-and-resume-a-project.md](stop-and-resume-a-project.md).
- Swap the worker: [swap-workers-without-changing-the-dag.md](swap-workers-without-changing-the-dag.md).
