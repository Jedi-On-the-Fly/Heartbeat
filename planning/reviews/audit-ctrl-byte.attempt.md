# Refuter attempt — `control_char` auditor rule (T154)

Actor: adversarial refuter (did NOT author the rule). Both runtimes exercised with real commands.
Anchor: `plugin/templates/hb-audit.js:98`, `py/src/heartbeat/audit.py:109-112`,
proofs `docs/howto/gate-examples/audit-ctrl-byte.sh`, `docs/howto/gate-examples/audit-rules-check.sh`.

## What the rule claims
hb-audit flags, as ERROR (exit 1), any criterion whose PARSED `cmd` or `desc` value contains a
`\x1e` (RS) or `\x1f` (US) byte — the gate.sh transport delimiters. node ≡ python.

## 1. Does it fire on the parsed byte, in cmd AND desc? — YES
Built DAGs with `"cmd":"......"` / `"......"` (JSON escape → parses to the raw byte),
and separately with the byte only in `desc`. For every case node and python both emit rule
`control_char` at severity error, exit 1, and the FULL finding set is identical:

| case | node cc | node exit | py cc | py exit | parity |
|---|---|---|---|---|---|
| byte(\x1f) in cmd | 1 | 1 | 1 | 1 | YES |
| byte(\x1e) in cmd | 1 | 1 | 1 | 1 | YES |
| byte(\x1f) only in desc | 1 | 1 | 1 | 1 | YES |
| byte(\x1e) only in desc | 1 | 1 | 1 | 1 | YES |
| both bytes in cmd | 1 | 1 | 1 | 1 | YES |
| byte at start of cmd | 1 | 1 | 1 | 1 | YES |
| byte at end of cmd | 1 | 1 | 1 | 1 | YES |
| empty cmd, byte in desc | 1 | 1 | 1 | 1 | YES |
| behavioral cmd + trailing byte | 1 | 1 | 1 | 1 | YES |
| no-cmd-key, byte in desc | 1 | 1 | 1 | 1 | YES |

## 2. False positives on real DAGs — NONE
Ran node + python audit on ALL 76 `dag.json` / `*.dag.json` files in the repo (incl. the two
untracked `planning/refuter-profiles*.dag.json`, plugin/template, adapter fixtures, deadlock
fixtures). Zero `control_char` findings from either runtime; every file parsed and audited (no ERR).
`false_positive_flag=0`.

## 3. Rule-completeness proof honesty — HONEST (with a nuance)
- Remove the control_char FIXTURE from `audit-rules-check.sh` while the rule stays in source:
  fails RED with `FAIL: auditor emits rule 'control_char' but this check has no fixture for it (add one)`.
  So a future rule shipped without a fixture is caught. This is the real completeness guarantee. ✅
- Full removal of the rule from `hb-audit.js` source: `audit-rules-check.sh` still passes at
  count 8 (the rule is DERIVED from source, so a deleted rule is simply no longer required). This
  is correct by design — the guard against deleting the rule itself is `audit-ctrl-byte.sh`, which
  goes RED (`FAIL: node hb-audit did NOT fail on a control-byte cmd`) when the JS rule is reverted.
- Reverting the PYTHON rule (JS intact): `audit-ctrl-byte.sh` goes RED
  (`FAIL: python audit did NOT report an error on a control-byte cmd`) — the proof covers the python
  side too. ✅
All scratch reverts restored; both audit files byte-identical to their pre-test working state.

## 4. Parity on edge inputs — AGREE on all in-spec inputs; one out-of-spec divergence
node `/[\x1e\x1f]/.test(x||'')` vs python `"\x1e" in (x or "") or "\x1f" in (x or "")` agree on:
byte at start/end, both bytes, byte-only-in-desc, empty cmd, missing cmd/desc keys, null cmd/desc.
Divergences found, both on MALFORMED (non-string) schema — not reachable via valid DAG authoring:
- `cmd` is a number (123): BOTH runtimes throw in `classify()` BEFORE the control_char line
  (node "trim is not a function", python "'int' has no attribute 'strip'"). Pre-existing, not
  control_char's doing; both error, neither silently passes.
- `desc` is a number (123): node coerces `123`→`"123"` in `.test()` → exit 0 clean; python
  `"\x1e" in 123` raises TypeError → exit 2. This IS the new control_char line. Minor: it only
  triggers on a non-string `desc`, which no schema check anywhere validates (pre-existing latitude;
  `desc` type is never enforced). Neither behavior is a silent WRONG pass on a REAL control byte.

## 5. Literal (unescaped) 0x1f byte in the file — LOUD, not silent
File with a raw 0x1f byte inside a JSON string:
- node hb-audit: `✗ dag.json unreadable: Bad control character in string literal in JSON`, exit 1.
- python json.load: `JSONDecodeError: Invalid control character at: ...`.
Both parsers reject at load. No new silent path; the already-handled case stays loud.

## 6. Suites — ALL GREEN
- Node: `RESULT: 387 passed, 0 failed`; GROUPS-RAN 154, T42/T43/T153/T154 present & green.
- Python: `96 passed`.
- Parity: `✅ PARITY OK — node ≡ python`.
- `audit-rules-check.sh` → `AUDIT-RULES-PROVEN:9` (was 8 pre-rule; +1 for control_char, sane).
- `audit-ctrl-byte.sh` → AUDIT-CTRL-BYTE-OK; `--selftest` → SELFTEST-OK.

## Holes
- Minor, out-of-spec: a non-string `desc` diverges (node clean / python TypeError). Same class of
  pre-existing type-latitude that already affects a non-string `cmd` (both throw). Not a control-byte
  miss and not authorable through valid JSON-with-string-fields DAGs; document or type-guard if desired.

VERDICT: SOUND
