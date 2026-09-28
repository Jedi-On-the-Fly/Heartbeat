# Run a constraint-first review

A plain adversarial review asks a refuter to "refute that this phase is done". What it checks is
left to the refuter, so two runs of the same review can look at different things, and a narrow
reviewer can miss the one thing that mattered. A **constraint-first review** fixes the targets
first: explicit, falsifiable constraints, each with an id, which the refuter must answer one by
one. HeartBeat then refuses a pass that leaves any id unanswered or answers one VIOLATED.

It has four parts:

1. **Plan-time constraints** (`P1…Pn`) written into the DAG with the plan.
2. **Gate-time constraints** (`G1…Gn`) written by an *author* who did not do the work, from the
   plan and from what the phase actually changed — recorded once per review cycle.
3. **The constrained refute**: every id answered on its own line, with evidence.
4. **An optional free review**: one unconstrained reviewer looking in breadth, recorded
   separately, from a different actor than the one who records the pass.

It applies to a gate whose review has plan-time constraints; every other gate reviews exactly as
before.

## 1. Plan time: give the review its targets

In `.hb/dag.json`, add `constraints` to the gate's `review` block:

```json
"GATE_API": {
  "review": {
    "profile": "security",
    "prompt": "Refute that the upload endpoint is safe.",
    "constraints": [
      { "id": "P1",
        "claim": "An upload larger than the limit is rejected with 413",
        "subjects": ["src/upload.py"],
        "violation": "an over-limit upload is stored, or answered with anything but 413" }
    ]
  },
  "criteria": [ … ]
}
```

Each constraint is requirement-level and falsifiable: `claim` is the property the phase promises,
`subjects` the files or areas it covers, `violation` the concrete observation that would break it.
`hb-lint` rejects malformed ones; `hb-audit` warns `unconstrained_review` on a review gate
without any.

## 2. Review time: the author

When the gate's deterministic criteria pass, the review is owed. Compose the author's
instructions — the phase's tasks, the plan-time constraints, and the exact list of what the phase
changed (`hb changed`, uncommitted and untracked work included):

```bash
node .hb/hb.js constraints GATE_API --prompt > author-prompt.txt
node .hb/hb.js constraints GATE_API --prompt --json | node -pe 'JSON.parse(require("fs").readFileSync(0)).model'
```

The second line prints the model the gate's profile names for the author (`author_model`), or
`null` — then use your session's default. Hand `author-prompt.txt` to an agent **that did not do
the phase's work**; it answers with a JSON array of `G1…Gn` constraints. Save it as
`author.json` and record it under that agent's identity:

```bash
HB_ACTOR=author-agent node .hb/hb.js constraints GATE_API --record author.json --model author-model
```

The set is write-once for this review cycle (re-running the gate does not reopen it), the author
must not be a doer of the phase, and HeartBeat stores its hash — `hb doctor` flags a later edit.

## 3. The constrained refute

```bash
node .hb/hb.js refute-prompt GATE_API > refute-prompt.txt
```

The prompt now ends with every id (`P…` then `G…`), the answer format and the triage rule:

```
<ID>: VIOLATED | NOT-REPRODUCED | N/A — <evidence or reason>
```

`NOT-REPRODUCED` means the refuter tried and could not break it, and must cite the probe it ran;
`N/A` needs a reason; `VIOLATED` is a finding. An exploitable problem found *outside* the
constraints still means REFUTED. The refuter writes its attempt to a file (`refute.md`).

## 4. The free review (when the profile asks for it)

A profile with `"free_review": true` also requires one unconstrained reviewer — breadth, not the
constraint list — recorded from an actor other than the one who records the pass:

```bash
node .hb/hb.js refute-prompt GATE_API --free > free-prompt.txt
HB_ACTOR=free-agent node .hb/hb.js review GATE_API free --artifact free.md --model free-model
```

## 5. The verdict

A refuter that found a hole records a failure (`hb review GATE_API fail "<finding>"`). Otherwise:

```bash
HB_ACTOR=refute-agent node .hb/hb.js review GATE_API pass --artifact refute.md --model refute-model
```

The pass is refused, with the id and the fix named, when a gate-time set was not recorded in
this cycle, an id has no answer line (prose that mentions an id is not an answer), an id is
answered twice or is unknown, an answer is VIOLATED, a NOT-REPRODUCED has no evidence or an N/A
no reason, or the profile's free review is missing. The accepted pass records how many answers of
each kind it carried; `hb doctor` re-checks them against the stored artifact.

The same sequence runs unattended under `hb exec`: the driver dispatches the author (backend mode
`author`), the constrained refute, and the free refute, each with its own model, and records a
refused pass as a failed review.

## Choosing models (any harness)

Each role has its own model field on the refuter profile — `author_model`, `model` (the
constrained refuter) and `free_model` — passed through verbatim to whatever your harness or
backend understands; an unset field means "use the session's or backend's default". A sensible
split:

- **The author and security gates** — the strongest model your harness offers. The author's
  constraints are what the rest of the review is held to.
- **The constrained refuter** — answering explicit constraints is narrower work; a cheaper model
  often suffices, and `hb report`'s per-model impact shows whether it still catches.
- **The free reviewer** — a different model from the refuter when you have one: breadth benefits
  from a different point of view.

Expect one author call per review cycle and one extra reviewer when `free_review` is on, on top of
the refute you already run.

## How this is proven

[`gate-examples/constraint-first-review.sh`](gate-examples/constraint-first-review.sh) runs the
fenced `bash` blocks of this page, in order, on a scratch project (with stand-in files for the
agents' outputs) and asserts the gate ends accepted with recorded constraints, a free review and
enforced answers; it also checks that this page and the SKILL's review steps name no vendor model
as a requirement.
