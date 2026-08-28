# Write a refuter profile

HeartBeat's value is bounded by how well it *refutes* — a generic skeptic misses domain-specific
failure modes (a security bug slips past a correctness lens; a hallucinated citation past a code
lens). A **refuter profile** is a named, reusable bundle — a persona, an optional model, a domain
falsification lens, and an optional verdict policy — that a project or a single gate selects instead
of re-writing free-text refute prompts. This guide shows when to use one, how to author and share
one, and where the honesty boundary is.

Everything here is backed by runnable proofs — the resolver
([gate-examples/refuter-profile-resolve.sh](gate-examples/refuter-profile-resolve.sh), T145), the
shareable library ([gate-examples/refuter-library.sh](gate-examples/refuter-library.sh), T146), the
one compose ([gate-examples/refuter-compose.sh](gate-examples/refuter-compose.sh), T147), and panels
([gate-examples/refuter-panel.sh](gate-examples/refuter-panel.sh), T148).

## When to use a profile

- **A gate has a dominant failure mode.** A phase that adds an endpoint wants a *security* lens; a
  parser wants a *correctness* lens; a research summary wants a *source-grounding* lens.
- **You keep re-typing the same refute angle.** Author it once, select it by name everywhere.
- **You want a distinct model to refute.** A profile can route the refutation to a different model
  than the doer (cross-model verification).
- **A gate is high-stakes.** Use a *panel* of diverse lenses and require a majority to certify.

If none of these apply, do nothing: with **no profile selected**, refutation behaves exactly as it
always has (see below). Profiles are purely additive.

## The default always works (and the feature is opt-in)

A gate that names no profile, in a project with no `HB_REFUTER`, gets a refute prompt **byte-identical
to today's** — just the gate's `review.prompt` (or the `Refute that <gate> is truly complete.`
fallback). Nothing is injected; existing projects are untouched. This backward-compatibility is a
gated regression check (T147).

A built-in `default` profile (a generic skeptic) is *always* resolvable, so refutation can never
fail-open for want of a profile — but it is **opt-in**: you get it only by naming it (`default`) or
setting `HB_REFUTER=default`. An unknown *explicit* profile name is an **error**, never a silent
downgrade to no review (T145).

## Author a profile

A profile is a JSON file under `.hb/refuters/<name>.json`:

```jsonc
// .hb/refuters/security.json
{
  "persona": "You are a SECURITY refuter for a HeartBeat phase gate. Hunt auth bypass, injection, secret leakage, missing authz on a new path. End with REFUTED or CLEAR.",
  "questions": [                          // a domain lens, folded INTO the falsification checklist
    "Does any new endpoint skip the authz check its siblings enforce?",
    "Is any secret or token logged, echoed, or committed?"
  ],
  "model": "claude-opus-4-8",             // optional — route the refute to a distinct model
  "provider": "anthropic",                // optional
  "verdict": { "panel": 3, "refute_if": "majority" }   // optional — a perspective-diverse panel
}
```

The `//` comments above are for this guide only — a real `.hb/refuters/<name>.json` is parsed as
plain JSON (`JSON.parse` / `json.load`), which has no comments, so strip them in your own file.

Every field is optional and normalizes to a safe default, so a persona-only file is valid. List what
a project can see with `hb refuters` (shipped + project, node and python identical). Select a profile
per gate, keeping any gate-specific angle:

```jsonc
"GATE_P3": {
  "review": { "profile": "security", "prompt": "…and check the new upload path specifically." },
  "criteria": [ … ]
}
```

Precedence for *which* name wins: an explicit gate `review.profile` > the `HB_REFUTER` env default >
the built-in `default`. Precedence for *where* a name resolves: your project files shadow shipped
ones, which shadow the built-in.

## Author it as an agent skill (Markdown, not JSON)

A refuter is really a specialized persona-skill, so you can author it in the same format an agent
skill uses — prose, not JSON. Two shapes, both resolving to the exact same profile:

- **Canonical folder** `.hb/refuters/<name>/SKILL.md` — a real, portable agent skill (packageable and
  shareable through the skill ecosystem, and loadable by other agents), which can carry bundled
  `references/` files alongside it.
- **Lite** `.hb/refuters/<name>.md` — a single file for quick use.

Both use flat frontmatter plus a persona body and a `## Checklist` (the bullets become the questions):

```markdown
---
name: security
description: Refute a phase for security failures — auth bypass, injection, secret leakage.
model: claude-opus-4-8
panel: 3
refute_if: majority
---
You are a SECURITY refuter for a HeartBeat phase gate. Hunt auth bypass, injection, and missing authz
on any new path. Cite the file and line. End with REFUTED or CLEAR.

## Checklist
- Does any new endpoint skip the authz check its siblings enforce?
- Is any secret or token logged, echoed, or committed?
```

The frontmatter is parsed by a small shared line-parser (deliberately not full YAML) so it resolves
identically in the node and python runtimes; keep values to simple one-line scalars. The shipped
`research-source` starter is authored this way — read `plugin/templates/refuters/research-source/SKILL.md`
as a worked example. `node .hb/hb.js refuters` lists folder, lite, and JSON refuters together.

### Quick start: scaffold one

Don't hand-write the boilerplate — scaffold a starting point and edit it:

```
node .hb/hb.js refuters new payments --from security
```

That writes a canonical `.hb/refuters/payments/SKILL.md` folder (a real agent skill you can later
package and share through the skill ecosystem) seeded from the `security` starter's lens. Pass `--lite`
for a single `.hb/refuters/payments.md` instead, or drop `--from` for a generic template. It refuses to
overwrite an existing refuter, and produces byte-identical output whether you run it from node or
python. Then open the file and make the persona yours: name the concrete failure classes of *your*
domain and say why each matters — a specific lens catches what a generic "looks fine" never will.

## What the composed prompt is (and the one caution)

Inspect exactly what a gate's refuter will be handed:

```
node .hb/hb.js refute-prompt GATE_P3      # or: hb refute-prompt GATE_P3 (python)
```

With a profile it composes **persona + the gate's base falsification checklist + the profile's extra
questions + the gate's `review.prompt`**. The one command is what the automated executor *and* an
interactive refuter both use, so every surface honors the profile identically (T147).

**Coverage-narrowing caution.** A profile's questions are **appended** to the deterministic base
checklist — they never replace it. A narrow single-lens profile still gets the full base coverage, so
a security lens can't wave through a correctness bug it wasn't looking for. For a genuinely
high-stakes gate, prefer a panel over a single narrow lens.

## Panels — perspective-diverse refutation

Set `verdict: { "panel": N, "refute_if": "majority" }` (or `"any"` / `"all"`). The executor runs N
refuters and aggregates: `majority` refutes iff more than half do, `any` iff at least one does, `all`
iff every panelist does. Fail-closed holds — a panelist that returns no verdict, or a clear verdict
citing no evidence, cannot certify a pass (T148). Diversity catches failure modes redundancy can't.

## Share a profile — like a domain adapter

Refuters are shared the same way domain adapters are — as data, no code change:

- **Author locally:** drop a JSON in `.hb/refuters/`; it resolves immediately.
- **Ship it:** add it to `plugin/templates/refuters/<name>.json`. Bootstrap seeds the shipped library
  into every new project's `.hb/refuters/` (no-clobber, so a project's own file of the same name is
  never overwritten — it shadows the shipped one). Distribute via the marketplace.
- **Validated like an adapter:** every shipped refuter must be valid and resolve — a behavioral
  integrity check, not a file-exists check (T146).

Three domain starter profiles ship today — `security`, `correctness`, and `research-source` —
alongside the built-in `default` (so `hb refuters` lists four in a fresh project). Read them under
`plugin/templates/refuters/` as templates for your own.

## The honesty boundary

A profile is *prompts*. You cannot deterministically prove an LLM "refuted well," so the same rule
from [writing-behavioral-gates.md](writing-behavioral-gates.md) applies: **gate the plumbing, not the
judgment.** What the suite proves is that the profile resolves, that the composed prompt carries the
persona and the criterion questions and the gate angle, that the model reaches the refute dispatch,
and that the distinct-actor and fail-closed invariants still hold. Whether a given persona produces
*better verdicts* is a live-model question — measure it on demand, never in the gate. A profile
changes the lens; it does not guarantee the verdict.

## How this is proven

The behaviors above are enforced by `tests/run-tests.sh` groups T145–T148 (see
[../dev-tests.md](../dev-tests.md)), each a runnable proof under
[gate-examples/](gate-examples/) with `--selftest` teeth, and node ≡ python parity cases in
`tests/parity.sh`. Concept and rationale: [../heartbeat.md](../heartbeat.md).
