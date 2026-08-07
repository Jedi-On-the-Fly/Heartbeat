# Add refutation to a sensitive gate

A deterministic gate proves the *check* passed. It cannot prove the check wasn't gamed —
the agent that wrote the code can write a test that grades it green. For a sensitive phase,
add **refutation**: a second actor must fail to prove the phase is *not* done, and must cite
evidence to do so. Looking for the one reason to say no catches what looking for reasons to
say yes waves through.

## Add a review block

In `dag.json`, give the gate a `review` prompt:

```json
"GATE_P3": {
  "desc": "...",
  "review": { "prompt": "Refute that P3 is done: hollow tests? criteria not really met? faked output?" },
  "criteria": [ /* the deterministic behavioral checks */ ]
}
```

Now the phase advances only when **both** the deterministic gate passes **and** a reviewer
fails to refute it. On `review_pending`, spawn a skeptical second agent to attempt the
refutation, then record the verdict:

```bash
hb review GATE_P3 pass --artifact <refuter-notes.md>   # could not refute
hb review GATE_P3 fail "<the hole it found>"           # found a hole -> back to work
```

## A pass must cite evidence, not assert one

`hb review … pass` is not a rubber stamp. The guard enforces:

- **An artifact is required** — `--artifact <file>`, the refuter's written attempt. A bare
  `pass` is rejected.
- **It must be substantive** — a few characters ("ok") is rejected.
- **It must cite a real anchor** — the phase/gate/task it examined. Padding with no anchor
  is rejected.
- **It must come from a different actor** — a self-review (the `HB_ACTOR` who did the work)
  is rejected; refutation is only adversarial from an independent actor.

The accepted artifact is stored under `.hb/reviews/` and re-checked later by `doctor` — if
it vanishes, that is flagged as rot. See [AGENTS.md](../../AGENTS.md) rule 6.

## Proof

These four guards are driven end-to-end against the real CLI by
[`gate-examples/refutation-demo.sh`](gate-examples/refutation-demo.sh): it stands up a
throwaway project, brings a review-gated phase to `review_pending`, and shows a pass is
rejected with no artifact, with a thin artifact, and as a self-review — and accepted only
for a substantive, anchored artifact from a distinct actor. Run it:

```bash
bash docs/howto/gate-examples/refutation-demo.sh   # -> REFUTATION-GUARDS-OK
```

The authoritative unit tests are in `py/tests/test_hardening.py`.
