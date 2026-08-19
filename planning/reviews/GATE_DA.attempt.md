# GATE_DA — deplint-accept wrapper (codemap resolution + delegate; parity)

**Distinct actor:** reviewer agent (not the doer). **Verdict: SOUND.**

Refutation attempts, all failed:
- Delegation, not drift: deplint-accept output byte-identical to direct deplint across MISSING+REDUNDANT+COLLISION; formatReport/format_report refactor kept T87 + deplint-parity byte-identical.
- Skip: no codemap + no .codegraph → DEPLINT-ACCEPT-SKIP exit 0 (no crash); resolution order --codemap > dir/codemap.json > db > skip confirmed.
- Strict: advisory exit 0 with findings; --strict → 1 iff missing OR collision; redundant-only + --strict → 0.
- Parity real + gap closed: node ≡ python for report/skip on independent inputs; resolve_task_symbols ported to python and byte-matches node's fuzzy matcher (multi-match, desc-only, no-match, substring, empty-leaf).
- Proof teeth: mutating skip code / --strict / the report each turned deplint-accept.sh (and parity) RED; reverted.
- Suites: node 318/0 (T87+T100 in GROUPS-PASSED), parity OK, python 90.

Reviewer's non-blocking note (a self-audit test under-asserting) fixed: test_accept_delegates_advisory_and_strict now uses _ACM via tmp_path and asserts delegation + strict-block + skip.
