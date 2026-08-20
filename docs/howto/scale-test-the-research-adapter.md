# Scale-test the research adapter (parity that a toy fixture can't prove)

The research adapter is a **parity surface**: `ground-check`, `research-context`, and `stamp-evidence`
each have a Node and a Python implementation that must agree. A three-claim fixture proves they agree on
three claims. It does **not** prove they agree on 200 claims full of the things that actually break
cross-runtime parity — non-ASCII bytes and sort order over many ids. For that you need scale, and scale
you can't hand-write. You generate it.

## Why a generator, not a committed corpus

A large corpus committed to the repo is bloat you have to maintain and can't vary. A **deterministic
generator** gives you a big, messy corpus that is byte-identical every run — so the proof stays
reproducible — while keeping the repo small. The generator is the *input*; only the three consumers are
under test, so the generator itself needs no Python twin.

Deterministic means: **no time, no randomness** — every value is derived from the claim's index. Two
runs produce identical bytes (the proof checks this), which is what lets a generated corpus gate.

## What the corpus stresses

The generator (`plugin/adapters/research/fixtures/scale/gen.js`) builds 60 sources and 200 claims across
four sections, and deliberately plants the parity hazards:

- **Non-ASCII bytes** — `°C`, `»`, `é`, `—` in sources and excerpts. This is where Node's UTF-8 output
  and Python's `print` can silently diverge if either mishandles encoding.
- **Line-wraps** — every stored excerpt has a newline injected mid-phrase, while the claim keeps a single
  space, so whitespace normalization is exercised on every grounded claim, not one.
- **Sort order at volume** — ids are **zero-padded** (`c_000…c_199`, `s_00…s_59`) so Node's `Array.sort`
  (UTF-16 code units) and Python's `sorted` (code points) produce the *same* order; the proof would catch
  it if they didn't.
- **Multi-claim-per-source** — each source is cited by several claims, like a real corpus.
- **Known counts** — every 5th claim is fabricated, so the corpus has exactly 160 grounded / 40 issues.
  The proof asserts those numbers, which proves the whole corpus was processed (not bailed on early).

## The two guarantees

The proof enforces exactly two things, at scale:

1. **node ≡ python, byte-identical.** `ground-check` and `research-context` outputs are compared
   byte-for-byte across all four sections; `stamp-evidence` maps are compared canonicalized (parsed-equal,
   since `JSON.stringify` and `json.dumps` legitimately serialize differently). Any encoding or ordering
   divergence fails the proof.
2. **A hung runtime fails fast.** The `ground-check` runs are wrapped in `timeout` as an anti-hang
   backstop: a runtime that deadlocks or loops fails the proof instead of blocking the whole suite. It's
   a coarse ceiling, deliberately *not* a fine-grained performance-divergence check — parity, not speed,
   is what this proof asserts.

## Proof

```bash
bash docs/howto/gate-examples/research-scale-parity.sh   # -> SCALE-PARITY-OK sources=60 claims=200 grounded=160 issues=40
```

Wired into the suite as T115. The generation (and its `mktemp` scratch dir) lives in the proof, never in
a gate criterion — a criterion that generated files would trip the audit's non-determinism and
side-effect checks. Fuller design: [research-adapter-scope.md](../../planning/research-adapter-scope.md).
