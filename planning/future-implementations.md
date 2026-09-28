# HeartBeat — future implementations

Distilled from two real runs outside this repo:
- a full 4-phase DAG on a small PHP web app;
- the plan stage of a 7-phase DAG on a PHP + JS library.

It also draws on a blinded experiment: one real review replayed 13 times across five reviewer setups in sealed
sandboxes, and graded blind against a rubric written before any run.

## Principle: no probabilistic judge in the control path

HeartBeat's job is to add determinism to a flow of non-deterministic actors: gates are deterministic, and the
adversarial review is bounded by a written, evidence-backed artifact. An extra probabilistic pre-screen in the
refute step (ranking "where to look") was measured and rejected:
- its scores didn't track whether a bug was present;
- with its focus, reviewers found the target bug in 0 of 2 runs, against 3 of 3 for blind-written constraints with a
  strong refuter;
- its one apparent win didn't replicate.

Luck is not a method. Every addition to the review path must make the outcome *more* reproducible, not less.

## 1. The review pipeline: constraints first (highest value)

Measured on one real review. The target was a privilege escalation the phase itself introduced.

| setup | target found | real findings per run | tokens per review |
|---|---|---|---|
| Sonnet, plain profile prompt | 0/3 | 0 | ~114k |
| Opus, plain | 1/3 | 4.3 | ~101k |
| Sonnet + blind-written constraints | 2/3 | 5.7 | ~111k |
| **Opus + blind-written constraints** | **3/3** | **9.0** | **~91k** |

Build:
- **A constraint author per gate.** Once per review gate, a strong-model agent reads only the plan, the phase diff
  and the code. It writes a falsifiable constraint list: a property, the subjects it covers, and what a violation
  looks like. It is told not to hunt for bugs. In the experiment it still named the target escalation, from reasoning
  about the capability model (~103k tokens, once per gate). The list is stored next to the gate as evidence, so the
  review becomes reproducible: same constraints, same checks.
- **Constrained refuters.** The refute prompt carries the constraint list, and the instruction is to try to produce
  each violation and report every one confirmed. Default model for review gates: the strongest available (Opus beat
  Sonnet with the same prompt).
- **One unconstrained reviewer for breadth.** Constraints narrow attention. In the experiment, the only run that
  found a real secret leak had no constraints. A review gate should run constrained refuters plus one free
  strong-model reviewer.
- **Triage rule in the refuter persona:** an exploitable side finding means REFUTED, whatever the scope. In the live
  run a refuter found a real escalation and filed it "out of scope" on a premise the phase had just made false.
- **The coordinator reads every artifact,** not just the verdict. `hb review … pass` could require the coordinator
  to acknowledge each non-blocking finding in the artifact.

## 2. Anchors and what the review actually sees

- **A HeartBeat-owned snapshot per gate.** Record a tag or a file-hash manifest at plan start and at every gate pass.
  Then:
  - the first phase has a real "before", so a refuter told to diff `ENTRY..HEAD` doesn't get an empty range;
  - "what changed" stops depending on the plan having a previous gate;
  - git becomes optional.
- **Reviews see uncommitted work.** HeartBeat commits a phase on `review pass`, *after* the review. Anything that
  diffs committed history at review time misses the phase's work, including refuters told to run
  `git diff ENTRY..HEAD`. Options: compose the review's "what changed" from the snapshot against the working tree plus
  untracked files, or commit the phase's work before the review and tag on pass.
- **Tag creation fails loudly.** `review pass` swallows commit and tag errors, and skips them under `HB_NO_GIT`. A plan
  whose gates depend on tags then degrades without a sound: in the library run, a mutant gate passed with zero
  mutants because a tag was missing. Report a failed tag, fail the pass when the plan depends on tags, and have
  `doctor` flag passed gates that have no tag.

## 3. Verification techniques to upstream (from the library plan)

- **Probes pinned by hash.** The planner writes acceptance probes up front, and every gate verifies their SHA-256
  first, so the implementer can't weaken a probe to get through. This needs a documented way to correct a probe that
  turns out to be wrong mid-run (currently that means editing the hash in the DAG, which is re-planning).
- **Mutant gates.** Each new mutant must bring back its own issue's bug; one that only breaks the build or crashes
  the engine is rejected. The library plan needed four refutation rounds to harden this. Upstream it as a tested
  helper, so plans don't rebuild it from scratch.

## 4. Plan refutation: budget and convergence

The library plan took 7 plan-refutation rounds: ~531k refuter tokens and ~248k main-session output tokens, before
any code ran. Rounds 3 to 6 hardened the plan's own self-built verification script.
- After round 1, re-refute only the changed part of the plan (a scoped round cost 45k tokens, against 70–102k).
- A round budget, with an explicit decision to go past it.
- A warning when a plan builds verification machinery complex enough to need its own refutation loop: that is the
  cue to upstream it (see 3) rather than harden it per plan.

## 5. Test and gate quality lessons (for the gate-writing how-tos)

- **Positive controls.** A no-change check must first prove it can detect a change. The live run had a test that
  hashed the wrong file for a whole phase, so its "refused requests change nothing" assertion was vacuous.
- **Prove the proof by mutation.** Break the implementation on a copy and require the test to fail with the expected
  message. That is what showed a rate-limit test really tells a sliding window from a fixed window, a non-expiring
  counter, and IP keying.
- **Test against real shapes.** A metric proven only with synthetic events passed its tests and measured nothing in
  a real run, because it read a field the real event doesn't have.
- **A 403 must come from the check under test.** Several refusals in a real test would have happened anyway:
  a feature was off, a parameter was misnamed, an upload was missing. Assert that the reason names the capability.

## 6. Possible later: structural context for the constraint author

On a real PHP app, CodeGraph renders showed that missing-edge holes (an endpoint skipping a guard its siblings call)
become visible only when the context includes the peers:
- for functions in one module, the other symbols in the same file;
- for one endpoint per file, the sibling files in the same directory.

If a run shows the constraint author needs it, add a peer-scoped render to the code adapter as the author's input,
not the refuter's.
