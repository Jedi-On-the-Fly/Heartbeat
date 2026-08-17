# GATE_S2 review — Seam 2: code context to Stage B (generic hook, both runtimes)

Adversarial review of the shipped S2 work (refute-don't-confirm), distinct actor from the implementer.

## Round 1 — UNSOUND (a real cross-runtime parity bug)
Most of the phase held up under mutation testing: the provider emits a real subgraph (touched
symbols + direct neighbors, unrelated excluded; T88 catches an echo-all mutant), the parity proof
drives both executors and compares the injected block (fails if a delimiter differs or a hook is
reverted), the hook is domain-neutral (no codegraph in either executor), it degrades on error with a
timeout, and the ollama demo is honestly on-demand/non-gated.

**Defect:** when `context_cmd` writes stdout but exits NONZERO, the runtimes diverged — Python
(`subprocess.run` without `check`) injected the output; Node (`execSync`, which throws on nonzero)
dropped it (`catch → return ''`). Common in practice (a provider that warns-and-exits-nonzero, a
`set -e` wrapper, a trailing sentinel). T89's stub always exited 0, so it missed this, and
parity-notes claimed "byte-identical" unconditionally.

## Fix (code + proof; gate not weakened)
- `hb-exec.js` contextHook now captures `e.stdout` from the `execSync` throw and injects it (mirrors
  Python's inject-what-was-produced contract); degrades to nothing only when there is no output.
- `context-inject-parity.sh` now asserts parity for BOTH an exit-0 and an emit-then-nonzero-exit
  context_cmd (an `assert_parity` helper run twice). Teeth re-verified: reverting the node fix makes
  the proof fail specifically on `FAIL[nonzero-exit]`.
- `parity-notes.md` corrected to state the byte-identical guarantee covers exit-code handling.

## Round 2 — SOUND
Re-review ran the mutation test (nonzero scenario red when node broken), confirmed emit-then-exit-5
injects the identical block on both runtimes, no regression to the exit-0/unset paths, no stderr
leak, symmetric degrade on empty-stdout+nonzero, parity-notes accurate. Node 301 passed / 0 failed,
python 77 passed, tests/parity.sh node ≡ python.

Note: also hardened the boundary criterion (c0e/s2e) from `grep -q "require('."` — where `.` was a
regex wildcard and a binary-detected file voided the check — to `grep -aqF` (force-text + literal dot).

**VERDICT: SOUND**
