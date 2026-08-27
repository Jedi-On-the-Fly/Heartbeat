# Scope: refuter profiles (personalizable adversarial review)

**One line.** Make the *refuter* — HeartBeat's adversarial reviewer — a named, reusable **profile**
(persona + optional model + domain falsification lens + verdict policy) that a project or a gate
selects, instead of re-writing free-text prompts and living with one generic "skeptical reviewer."

## Why — the gap

Refutation quality is the **upper bound** on HeartBeat's value. A hollow gate or a generic skeptic
turns the whole verify apparatus into theatre (AGENTS Rule 3/6). Today the refuter is real and
first-class, but its *voice* is generic and hardcoded per backend adapter — e.g.
`backends/agno.py:41` "Skeptical adversarial reviewer. End with REFUTED or CLEAR." A generic skeptic
misses **domain-specific** failure modes: a security bug slips past a correctness lens, a hallucinated
citation past a code lens. This is already flagged on the roadmap — `docs/howto/howto-list.md:85`
*"Write a Good Refuter Prompt / Profile — Not available yet"* (line 217: "higher-value now that the
refuter can be a distinct model"). This doc scopes that item.

## What exists today (reuse, don't rebuild)

The refuter is already a named actor with three personalization hooks — the profile layer composes
*over* them, it doesn't replace them:

1. **Per-gate angle** — `review.prompt` in the DAG; the exec loop reads
   `rv_block.get("prompt", "Refute that {g} is truly complete.")` (`executor.py:326`, node
   `hb-exec.js` twin). Bespoke per gate, free text.
2. **Who refutes (cross-model)** — `HB_REFUTE_BACKEND/CMD/MODEL/PROVIDER` (env) or `executor.json`
   `refute_*` (`executor.py:51-59` ≡ `hb-exec.js:69-89`). The refuter can be a distinct
   model/provider from the doer, and it **fails closed**: no boolean verdict ⇒ never a pass
   (`executor.py:329-331`).
3. **Distinct-actor guarantee** — `HB_ACTOR`, `refuter_actor = worker:refuter` (`executor.py:272`,
   node stamps it too) — no self-review; a pass must cite a different actor's written artifact
   (Rule 6).
4. **Deterministic seed** — the falsification checklist `audit.review_questions(dag, gate)`
   (`audit.py:60`; `hb audit --questions`, node `hb-audit.js:39,61`), derived per gate from each
   criterion's class. The research adapter already extends this with a "source-lens"
   (`research-adapter-scope.md:117,147`) — precedent for a domain lens.

**The missing piece:** a reusable, *named* bundle you author once and select many times — not
copy-pasted prompts and env vars.

## The core idea — a refuter profile

A **profile** is a named bundle:

```jsonc
// .hb/refuters/security.json   (or an executor.json "refuters" map)
{
  "persona": "You are a SECURITY refuter for a HeartBeat phase gate. Hunt: auth bypass, injection, secret leakage, TOCTOU, unsafe deserialization, missing authz on a new path.",
  "questions": [                       // domain lens, folded INTO review_questions (additive)
    "Does any new endpoint/handler skip the authz check its siblings have?",
    "Is any secret/token logged, echoed, or committed?"
  ],
  "model":    "claude-opus-4-8",       // optional — reuse the cross-model refute_* machinery
  "provider": "anthropic",             // optional
  "verdict":  { "panel": 3, "refute_if": "majority" }  // optional — perspective-diverse panel
}
```

Selection is per gate, backward-compatible with `review.prompt`:

```jsonc
"GATE_P3": {
  "desc": "...",
  "review": { "profile": "security", "prompt": "…extra gate-specific angle (optional)" },
  "criteria": [ … ]
}
```

## The default refuter (must always work)

The feature is **purely additive**: a project that selects no profile behaves exactly as today.
Resolution with no name returns a **built-in `default` profile** — the current generic skeptic
persona — so a refuter *always* exists and refutation can never break or fail-open because a profile
was missing. An **unknown *explicit* name errors** (never silently degrades to no-review); only the
*absence* of a selection falls back to `default`. The composed prompt for the no-profile path is
byte-identical to today's, and that backward-compatibility is a gated regression check.

## Sharing — a refuter library, like domain adapters

Refuters are shared the same way domain adapters are (code/docs/research under `plugin/adapters/`):

- **Shipped library:** `plugin/templates/refuters/<name>.json` — versioned with the plugin, distributed via the
  marketplace. Bootstrap seeds them into a project (as it already copies `templates/`, `executors/`).
- **Project overrides:** `.hb/refuters/<name>.json` shadows a shipped one of the same name.
- **Discovery:** `hb refuters` lists what's available (shipped + project), node≡python identical.
- **Authoring/sharing a new refuter** = drop a JSON in `plugin/templates/refuters/` (or `.hb/refuters/`) and,
  to share, PR it to the shipped library — no code change (the [Seam] pattern). A shipped refuter is
  validated like an adapter (resolves + integrity-checked).

**Resolution precedence:** per-gate `review.profile` → project `.hb/refuters/` → shipped
`plugin/templates/refuters/` → built-in `default`.

## Where it plugs — no core surgery (the seam pattern)

Mirrors how backends and domain adapters plug in (the [Seam] pattern, `docs/adapters.md` /
code-adapter precedent): core stays generic; the profile is data + a resolve step.

- **Registry:** the search path above (`.hb/refuters/` + shipped `plugin/templates/refuters/` + built-in
  default), plus an optional `executor.json` `{ "refuters": { … } }` for inline definitions.
- **Composition point:** the `review_pending` dispatch (`executor.py:315-328`, node `hb-exec.js`
  twin). Resolve `review.profile` → compose the refute prompt as **`persona` + `review_questions`
  (with the profile's extra questions) + the gate's `review.prompt`**, and route
  `profile.model/provider` through the existing `refute_model/refute_provider` path. One localized
  change per runtime.
- **Interactive parity:** the plugin/skill `review_pending` handler seeds the spawned Agent the same
  way (persona + `hb audit --questions` + gate prompt), so Claude Code / Codex refuters get the same
  profile. The MCP `review` surface can expose the resolved prompt too.

## The determinism boundary (the key constraint)

A profile is *prompts* — you cannot deterministically prove an LLM "refuted well." So the honesty
rule from the docs work applies exactly: **gate the plumbing, not the judgment.** Suite-provable:
the profile resolves; the composed prompt contains persona + the criterion questions + the gate
angle; `profile.model` reaches the refute dispatch; the distinct-actor and fail-closed invariants
still hold; an unknown profile name errors (never silently falls back to "no review"). The *quality*
of a persona's verdicts is the on-demand live tier (like the framework/backend live proofs), never
the gate.

## Composition — panels and lenses

- **Perspective-diverse panel:** `verdict.panel: N` runs N distinct lenses (correctness / security /
  repro) or N independent skeptics and requires `refute_if: majority`. Diversity catches failure
  modes redundancy can't — the inverse of one generic reviewer.
- **Stacking:** a project default (`HB_REFUTER`) + a per-gate override; the gate's `review.prompt`
  is always appended, so a profile never *loses* the task-specific angle.

## Reused vs new

- **Reused:** the entire cross-model refute path (`refute_*`, fail-closed), `HB_ACTOR` distinct-actor,
  `review_questions` / `--questions`, `review.prompt`, the backend `refute()` wire mode.
- **New:** a profile schema + a resolver (`refuter_profiles.py` / mirror in node), the
  `review.profile` field, prompt composition at the dispatch site, and (optional) the panel verdict
  policy.

## Proof strategy (spec-first, suite-gateable)

1. **Resolver proof** — a profile file resolves; unknown name errors; env default applies; `--selftest`
   teeth (each field load-bearing).
2. **Composition proof** — given a profile + a gate, the composed refute prompt contains persona +
   the gate's criterion questions + the gate `review.prompt`; and `profile.model` lands in the
   refute dispatch config (assert via a stub backend that echoes its received prompt/model, the
   `mcp-server.sh`/backend-stub pattern). RED before wiring.
3. **Invariant proof** — distinct-actor + fail-closed still hold with a profile in play; an unknown
   profile does not silently skip review.
4. **Parity** — the resolve+compose behavior is a **shared surface** (node `hb-exec.js` ≡ python
   `executor.py`): add a `tests/parity.sh` case so both runtimes compose identical prompts.
5. **Refute the design** — distinct-actor review of the plan before building, per the usual loop.

## Sequencing (phases, when built)

- **P1 — schema + resolver** (registry, env default, unknown-name error). Gate: resolver proof.
- **P2 — compose at the dispatch site** (both runtimes) + parity case. Gate: composition + parity.
- **P3 — panel verdict policy** (optional, N-of-M). Gate: majority-refute proof with stub verdicts.
- **P4 — the how-to** (`write-a-refuter-profile.md`, closes `howto-list.md:85`) via gated-docs;
  ship 2-3 starter profiles (security / correctness / research-source).

## Non-goals

- Not a truth oracle or a quality guarantee — a profile changes voice/angle, not the fact that the
  verdict is an LLM's.
- Not a replacement for `review_questions` — profiles are **additive lenses over** the deterministic
  checklist; a narrow persona alone can *reduce* coverage.
- No new trust model — the gate stays behavioral; MCP/backends stay untrusted.

## Risks & open questions

- **Coverage narrowing:** a single-lens profile (security-only) can wave through a correctness bug.
  Mitigation: keep `review_questions` always in the composed prompt; recommend panels for sensitive
  gates.
- **Profile rot:** a persona referencing stale tech drifts. Mitigation: profiles are prose — subject
  to the same "docs are claims" scrutiny; keep them short and lens-focused, not encyclopedic.
- **Config sprawl:** too many profiles = nobody knows which to pick. Mitigation: ship a small
  curated set; document when to use each.
- **Decided (was open):** profiles live BOTH per-project (`.hb/refuters/`) and as a shared,
  marketplace-distributed library (`plugin/templates/refuters/`, bootstrap-seeded) — the domain-adapter model —
  with project shadowing shipped and a built-in `default` beneath both. This makes refuters
  user-creatable and shareable without a code change.

## Reference

- Current refute path: `executor.py:51-59,272,315-338` ≡ `plugin/templates/hb-exec.js:69-89,107`.
- Falsification seed: `audit.py:60` / `plugin/templates/hb-audit.js:39-61` (`hb audit --questions`).
- Roadmap item: `docs/howto/howto-list.md:85,217`. Domain-lens precedent:
  `planning/research-adapter-scope.md:117,147`. Seam pattern: `docs/adapters.md`.
