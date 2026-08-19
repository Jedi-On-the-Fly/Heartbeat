# GATE_WI — auto-surface deplint at plan acceptance + db-build harness

**Distinct actor:** reviewer agent (not the doer). **Verdict: SOUND.**

Refutation attempts, all failed:
- Auto-surface is real: skill + how-to both instruct running deplint-accept after hb-lint/hb-audit
  (node + python-twin, advisory/--strict, provisional/fuzzy + skips-cleanly caveats); commands run live.
- db-build harness has teeth: real-deplint-accept.sh builds a codemap from a live .codegraph db
  (provisional NOTE + HB-CODE-DEPLINT + a real MISSING Dog->Animal), node ≡ python; mutating the db
  branch or diverging python turns it RED; skips cleanly with codegraph off PATH.
- On-demand consistent: not wired into run-tests.sh (like real-codegraph-map.sh), referenced from the
  adapter header; suite green without CodeGraph.
- Core neutral: base heartbeat SKILL has no deplint/codegraph/codemap dependency; this lives in the
  code adapter + its skill only. No overclaim (auto-built codemap flagged provisional).
- Suites: node 318/0 (T100/T92/T93 in GROUPS-PASSED), parity OK, python 90, self-audit 63/61,
  skill-integrity OK (2 adapters, 7 wired proofs).
