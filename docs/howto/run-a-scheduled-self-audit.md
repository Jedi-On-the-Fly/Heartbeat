# Run a scheduled self-audit

**Outcome:** keep the doc/code corpus honest on a timer. A deterministic audit catches drift
(broken links, non-existent commands, vanished or dormant proofs) and escalates; an on-demand
adversarial sweep hunts overclaims the deterministic layer can't see. This is HeartBeat's
"refute, don't confirm" turned on the project itself, continuously.

## The deterministic audit (schedulable, no model)

```bash
bash docs/howto/gate-examples/self-audit.sh      # -> SELF-AUDIT-OK:<guides>/<proofs>
```

It asserts three project-wide invariants: **prose-integrity** (every guide passes
[`prose-check.sh`](gate-examples/prose-check.sh) — links resolve, only real commands),
**referenced-proof integrity** (every `gate-examples/*.sh` a guide names in its body exists *and*
is wired into `tests/run-tests.sh`), and **runtime parity** (node ≡ python on the shared surfaces
via `tests/parity.sh` — the #2 contract, since the corpus can be coherent while the two runtimes
silently diverge; the generative oracle [`parity-fuzz.sh`](../../tests/parity-fuzz.sh)
is the deeper on-demand version). The second check closes a real gap: proof references are
code-fence paths, not markdown links, so `prose-check` never sees them — which is precisely how a
proof can quietly vanish or go dormant. Non-zero exit on any finding.

The full deterministic battery re-runs the behaviors *and* the coherence check:

```bash
bash tests/run-tests.sh && bash docs/howto/gate-examples/self-audit.sh
```

## Schedule it

Run the battery on a timer and escalate on failure. Locally, system cron:

```bash
0 6 * * * cd /path/to/heartbeat && { bash tests/run-tests.sh && bash docs/howto/gate-examples/self-audit.sh; } \
  || printf 'heartbeat self-audit FAILED\n' | mail -s 'heartbeat drift' you@example.com
```

Or, in an open session, `/loop 6h bash docs/howto/gate-examples/self-audit.sh`. The escalation is
the point: a green run is silent, a red run pages you. Same cloud-vs-local caveat as
[schedule-heartbeat-unattended.md](schedule-heartbeat-unattended.md) — a Claude Code `/schedule`
routine clones a git repo, so use it only for a repo it can clone; otherwise use local cron.

## The adversarial sweep (on-demand, needs a model)

The deterministic audit proves the corpus is *coherent*; it can't judge whether a guide
*overclaims* versus the code. For that, run a distinct-actor refutation sweep — skeptical
reviewers reading the guides against the source, hunting claims stronger than what the code does
(the method that caught the worktree-isolation overclaim and the relative-`--dir` bug). This
needs a live model and is **non-deterministic**, so it never gates the suite — read it as a
capability probe, like the pinned-Docker and MCP-interop tiers. It's the same discipline the
[gated-docs](../../plugin/skills/gated-docs/SKILL.md) skill applies to a single guide, scaled to
the whole library and run when you want depth rather than on every commit.

## Honest scope

The deterministic tier is what you schedule and gate on — it's fast, has no model, and escalates.
The adversarial tier finds deeper defects but can't be a green/red gate. Neither judges whether a
gate tests the *right* thing; that last mile is still on you
([writing-behavioral-gates.md](writing-behavioral-gates.md)).

## Prove it worked

The audit has teeth — it must be able to go red. Its self-test injects a guide that references a
missing proof and one that references an existing-but-unwired proof, and asserts both are caught:

```bash
bash docs/howto/gate-examples/self-audit.sh --selftest   # -> SELF-AUDIT-SELFTEST-OK
```
