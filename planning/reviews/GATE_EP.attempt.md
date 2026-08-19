# GATE_EP — gate evidence provenance + hb evidence

**Distinct actor:** reviewer agent. **Verdict: SOUND.**

- Real provenance both runtimes: gate_passed carries criteria:[{id,cmd,exit}] with EXACT cmds
  (quotes/backslashes correctly JSON-escaped — events.jsonl stays valid), real commit sha, runtime.
  `hb evidence <gate>` reads it (node + python).
- Edge cases: non-git → commit null, no crash; failing gate → no gate_passed ("no recorded gate pass");
  unknown gate → clean exit 0; review_passed shown (reviewer + artifact).
- No regression: node 323/0 (T105), python 91, parity OK; report/state/doctor read the enriched event fine.
- Proof teeth: reverting the provenance builder / removing `evidence` turns evidence-provenance.sh RED.
