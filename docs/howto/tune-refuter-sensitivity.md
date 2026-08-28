# My refuter always / never finds anything

Two symptoms, opposite causes:

- **Never finds anything** — every review comes back CLEAR, even on phases you suspect are wrong. A
  generic skeptic misses domain-specific failure modes, so the gate becomes theatre.
- **Always finds something** — every review comes back REFUTED with thin, generic complaints, so the
  project stalls on noise.

You cannot *deterministically* prove a refuter reaches the "right" verdict — that is an LLM judgment,
measured on demand with a live model. What you CAN do is tune the **levers** below, each a shipped,
proof-backed mechanism, and then read what actually changed. This guide gates on prose integrity
(links resolve, commands are real) and points every remedy at the mechanism that implements it — it
teaches the levers, it does not promise the verdict. Background on that boundary:
[writing-behavioral-gates.md](writing-behavioral-gates.md).

The running example is a **security** phase: `GATE_P3` adds an HTTP endpoint, and a generic refuter
keeps missing that the new route skips the authorization check its siblings enforce.

## Case A — it never finds anything (false CLEAR)

The lens is too generic. Fix it by giving the refuter a domain lens, more perspectives, or a stronger
model — in increasing order of cost.

**1. Select a domain profile.** A shipped `security` profile already names the failure classes to hunt
(auth bypass, injection, secret leakage, missing authz). List what is available and point the gate at
it:

```
node .hb/hb.js refuters                 # security, correctness, research-source, default
```

```jsonc
"GATE_P3": { "review": { "profile": "security" }, "criteria": [ … ] }
```

Inspect exactly what the refuter will now be handed — the persona plus the security questions are
appended to the gate's base falsification checklist:

```
node .hb/hb.js refute-prompt GATE_P3
```

The profile's questions are **added to** the base checklist, never substituted for it, so switching to
a narrow security lens cannot silently drop the general coverage you already had. Authoring or sharing
your own lens: [write-a-refuter-profile.md](write-a-refuter-profile.md).

**2. Add perspectives (a panel).** If one lens still misses it, run several and refute if *any* of them
does — the most sensitive setting. A panel is a field of the **refuter profile** (not the gate); add it
to `.hb/refuters/security.json`:

```json
{
  "persona": "…", "questions": ["…"],
  "verdict": { "panel": 3, "refute_if": "any" }
}
```

That runs 3 refuters and refutes if *any* does. Only a profile's `verdict` is read — a `verdict`
placed on the gate is silently ignored, so keep it in the profile JSON. That placement rule is pinned
by a proof ([gate-examples/refuter-verdict-placement.sh](gate-examples/refuter-verdict-placement.sh),
T149): profile-placed drives N refuters, gate-placed drives one.

**3. Refute with a distinct (stronger) model.** A weak refuter model rubber-stamps; route the refutation
to a different model than the doer: [cross-model-verification.md](cross-model-verification.md).

## Case B — it always finds something (noise / false REFUTED)

Usually a vague persona chasing paraphrases, or a panel set too strict.

- **Name concrete failure classes, not "find problems."** For the security phase, tell it to hunt
  *authz gaps, injection, secret leakage, unsafe deserialization* — specific classes it can confirm or
  clear — instead of an open-ended "look for issues," which always yields something.
- **Loosen the panel rule.** Prefer `refute_if: "majority"` over `"any"` so a single over-eager
  panelist cannot block the phase.
- **Lean on the evidence floor.** A REFUTED verdict must cite a real hole and a pass must cite the
  refuter's actual written attempt from a distinct actor — HeartBeat rejects an evidence-free verdict
  either way (Rule 6). A refuter that "always refutes" with no substantive findings is already caught;
  see [handle-a-successful-refutation.md](handle-a-successful-refutation.md).

If the deeper question is *which* gates deserve refutation at all, that is a scoping decision, not a
sensitivity one: [refute-high-risk-claims.md](refute-high-risk-claims.md) and
[add-refutation-to-a-sensitive-gate.md](add-refutation-to-a-sensitive-gate.md).

## Confirm the change actually took effect

Do not guess — observe:

- `node .hb/hb.js refute-prompt <gate>` shows the composed prompt, so you can confirm the persona and
  the domain questions are really in it.
- After a run, read the stored attempt under `.hb/reviews/<gate>.attempt.md` — the refuter's real
  words, which `hb review` required and which `doctor` re-checks for rot.

## The honest limit

These levers change the *lens*; they do not guarantee a better verdict. Whether a given profile
genuinely catches more real bugs than the default is a live-model question — run it against known-buggy
and known-good phases and compare. The deterministic part is everything above: that the profile
resolves, that its persona and questions reach the refuter, that a distinct model can be routed, and
that evidence-free verdicts are rejected.

## How the mechanisms here are proven

Each lever is backed by a runnable proof wired into `tests/run-tests.sh` (see
[../dev-tests.md](../dev-tests.md)): profiles resolve and default-safely (T145,
[gate-examples/refuter-profile-resolve.sh](gate-examples/refuter-profile-resolve.sh)); the shipped
`security` lens is seeded and discoverable (T146,
[gate-examples/refuter-library.sh](gate-examples/refuter-library.sh)); the persona + appended
questions reach the one compose (T147, [gate-examples/refuter-compose.sh](gate-examples/refuter-compose.sh));
panels aggregate with a fail-closed evidence floor (T148,
[gate-examples/refuter-panel.sh](gate-examples/refuter-panel.sh)); cross-model refutation (T73); and
scoping which gates to refute (T60). Concept: [../heartbeat.md](../heartbeat.md).
