# Schedule HeartBeat unattended

**Outcome:** drive HeartBeat's ticks on a schedule, with no human in the loop — so a project
makes progress on its own and only surfaces when it needs you.

HeartBeat's Stage A is a cheap, deterministic tick. Running it on a timer is all "unattended"
means: each tick reads settled reality and wakes the worker only when there's real work
([spend-the-model-only-on-work.md](spend-the-model-only-on-work.md)), so an idle schedule costs
almost nothing.

## The tick to run

Every option below runs the same thing on a timer:

```bash
hb tick --dir myproject     # one Stage-A tick -> {wakeAgent, data}; act on data.reason if awake
```

Parse the JSON: if `wakeAgent` is false, stop. If true, act on `data.reason` per the tick
protocol (do the task, run the gate, or escalate).

## Three ways to schedule it

- **In-session (Claude Code).** `/loop 20m /heartbeat tick <project-dir>` drives ticks while a
  session is open — simplest for interactive work.
- **Cloud routine (Claude Code `/schedule`).** A cron-triggered routine runs the tick
  unattended. Caveat: `/schedule` routines execute in Anthropic's cloud and clone a **GitHub
  repo** per run — so this only works when your project lives in a repo the routine can clone.
- **System cron (local-only).** For a local project, a machine cron entry drives it with no
  cloud involved, e.g. every 20 minutes:

  ```bash
  */20 * * * * cd /path/to/myproject && hb tick --dir . >> .hb/tick.log 2>&1
  ```

  (Or call a headless agent instead of a raw tick if you want the worker driven automatically.)

## Keep it safe to run unattended

Unattended runs make weak gates dangerous, so lean on HeartBeat's safety rails: the auditor
refuses hollow gates before you start, the driver escalates on a blocked gate instead of
auto-fixing, and the circuit breaker stops a stuck build after repeated no-progress. If you're
gating a pipeline on the result, [run-heartbeat-in-ci.md](run-heartbeat-in-ci.md) covers exit
codes. Review any unfamiliar gate command first
([review-an-unsafe-gate.md](review-an-unsafe-gate.md)) — a scheduled tick runs it with your
privileges.

## What you get

A project that advances on its timer, commits and tags each verified phase as a restore point,
and pings you only on a human-needed wake (a blocked gate, a stuck build, or completion).
