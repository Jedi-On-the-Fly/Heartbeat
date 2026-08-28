# Scope: refuter authoring — skill-format + quick scaffolder

**One line.** Let a refuter be authored the way agents already author skills — a single Markdown file
with flat frontmatter + a `## Checklist` — so newcomers get a prose-native, portable on-ramp, while the
resolver normalizes it to the *same* profile dict the JSON form produces (all compose/panel/calibration
machinery unchanged). Plus a one-command scaffolder for quick use.

## Why

The [refuter-bench](refuter-bench-scope.md) harness is the rigorous "does this refuter add value" path.
But authoring today means writing JSON, and a refuter *is* really a specialized persona-skill. Expressing
it in the agent-**skill** format (frontmatter + prose body) gives: prose-native authoring, portability
across agents (a `security-refuter` SKILL is loadable outside HeartBeat), and free distribution through
the plugin/marketplace HeartBeat already rides (incl. Codex). It's the same additive **seam**: the
resolver learns a second front-door; the normalized `{persona, questions[], model, provider, verdict}`
contract — and everything downstream — is untouched.

## The format (single file `.hb/refuters/<name>.md`)

```
---
name: security-refuter        # optional (informational)
model: claude-opus-4-8         # optional
provider: anthropic            # optional
panel: 3                       # optional → verdict.panel
refute_if: majority            # optional → verdict.refute_if
---
You are a SECURITY refuter…    (everything before ## Checklist = persona)

## Checklist                    (the "- " bullets = questions, the domain lens)
- Does any new endpoint skip the authz check its siblings enforce?
- Is any secret logged, echoed, or committed?
```

Normalizes to exactly the same dict as the equivalent `<name>.json`.

## The parity constraint (the one hard rule)

Full YAML diverges node vs python. So the frontmatter is **strict flat `key: value` scalars only** (no
nesting, no lists) parsed by a **shared minimal line-parser** — NOT a YAML library — and the questions
come from the `## Checklist` bullet list, not YAML. `panel`→int. Node ≡ python parse byte-identically;
this parser is a parity surface, cased like the JSON resolver (T145).

## Decisions

- **Collision:** if both `<name>.json` and `<name>.md` exist in the SAME dir → the resolver **errors**
  (ambiguous; fail-closed, never a silent shadow). Cross-dir precedence is unchanged (project shadows
  shipped).
- **Seeding:** bootstrap seeds shipped `*.md` refuters too (so skill-format starters travel).
- **Quick use:** `hb refuters new <name> [--from <starter>]` scaffolds a resolvable SKILL.md from a
  shipped starter (no-clobber; unknown starter errors).

## Phases

- **AF — skill-format resolver input.** Teach `resolve()` the `.md` front-door (shared parser),
  normalized to the same dict; collision-errors; node ≡ python; seed `*.md`.
- **QS — quick scaffolder + docs.** `hb refuters new`; document the skill format in the existing
  write-a-refuter-profile.md (no new guide — avoid sprawl); gated by prose-check.

## Non-goals

- Not YAML (parity). Not a new JSON schema. Not a change to compose/panel/calibration (a second
  front-door only). Not the calibration harness (that's refuter-bench, built after this).

## Acceptance

`hb-lint` clean · `hb-audit` clean (0 hollow) · plan-refuted SOUND — before any build.
