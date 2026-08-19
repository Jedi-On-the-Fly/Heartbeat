# GATE_RQ — falsification questions from gate claims (hb-audit --questions)

**Distinct actor:** reviewer agent. First pass UNSOUND (proof teeth), fixed, re-verified **SOUND**.

- Feature correct: `--questions <gate>` emits a class-appropriate falsification question per criterion
  (existence / grep-of-source / coverage-grep / behavioral / side-effect / nondet) + a general phase
  question quoting the gate desc; node ≡ python byte-identical; normal audit unchanged; missing gate
  degrades cleanly. Exposed as `hb audit --questions` and referenced from review_pending guidance.
- First review refuted the PROOF (not the feature): its per-class greps scanned the whole output, so a
  synchronized both-runtime collapse-to-generic stayed green (teeth rested on parity alone).
- Fix: review-questions.sh now extracts each criterion's question TEXT (sed), asserts each is
  class-appropriate ANCHORED to that criterion, AND asserts the four are DISTINCT (sort -u == 4).
- Re-verified: a both-runtime collapse → RED on distinctness; a wrong-class swap → RED on the class
  assertion; both independent of the parity check. node 322/0 (T104), parity OK, python 91.
