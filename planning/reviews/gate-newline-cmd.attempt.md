# REFUTER attempt — gate.sh newline-cmd transport fix (T153)

Actor: adversarial refuter (did not write the fix). Repo clean-restored after.

## The fix under review
`plugin/templates/gate.sh` `eval_gate` (lines 53–66):
- emit: `process.stdout.write([c.id, c.desc, c.cmd].join('\x1f') + '\x1e')` (was `console.log(...join('\x1f'))`)
- read: `while IFS=$'\x1f' read -r -d $'\x1e' ID DESC CMD` (was `read -r ID DESC CMD`)
Records now RS(`\x1e`)-terminated instead of newline-terminated → immune to newlines inside a cmd/desc.
Proof: `docs/howto/gate-examples/gate-newline-cmd.sh` (+`--selftest`), wired as T153.1/T153.2 in `tests/run-tests.sh`.
Python `py/src/heartbeat/gate.py` reads the parsed dag directly (`for c in criteria`) → never had the bug; it is the parity oracle.

## 1. Catastrophic single-criterion heredoc (scratch /tmp/gx via bootstrap.sh)
- single heredoc `python3 - <<PYX / import sys / sys.exit(1) / PYX` → **node --check: 0 passed/1 failed, exit 1, "would block"; py: would_block, exit 1.** Correctly BLOCKED.
- single heredoc exit0 → node 1/0 exit 0 "would pass"; py would_pass. Correctly PASSES.
Pre-fix, the middle heredoc body split into empty-CMD records that `bash -c ""` passed (see §5). Fixed.

## 2. Correctness + node≡python (all PARITY-OK unless noted)
| case | node p/f exit | py p/f exit | verdict |
|---|---|---|---|
| multi embedded newlines, exit0 | 1/0 e0 | 1/0 e0 | OK |
| two newline crits (pass+fail) | 1/1 e1 | 1/1 e1 | OK |
| heredoc body w/ literal PYX + `\x1f` byte, exit1 | 2/1 e1 | 2/1 e1 | OK |
| normal single-line 3-crit (2 pass 1 fail) | 2/1 e1 | 2/1 e1 | OK — no regression |
| desc containing newline | 1/0 e0 | 1/0 e0 | OK |
| cmd trailing newline | 1/0 e0 | 1/0 e0 | OK |
| empty criteria gate | 0/1 e1 (refused) | 0/1 e1 (refused) | OK — hollow floor holds |
| 6 crits after the newline one (1 fail) | 5/1 e1 | 5/1 e1 | OK — no desync |

`\x1f` byte *inside* a cmd is safe: `read` with 3 vars folds the remainder into the last var (CMD), so the cmd stays intact (node 1/0 == py 1/0).

## 3. Real path (not --check), with git — scratch /tmp/gr
- `gate.sh GATE_PASS` (heredoc exit0): prints "✅ GATE PASSED", exit 0. `events.jsonl` gets `gate_passed` with `criteria:[{id:h,cmd:"...\nimport sys\nsys.exit(0)\nPYX",exit:0}]` (heredoc stored verbatim), commit hash, `runtime:node`; git tag `GATE_PASS` created.
- `gate.sh GATE_FAIL` (heredoc exit1): "❌ GATE BLOCKED", exit 1; `gate_failed` event appended; no tag.

## 4. Edges
- Last criterion: NOT dropped/double-counted. `process.stdout.write(... + '\x1e')` terminates every record incl. the last; `read -d $'\x1e'` returns each. Counts exact in every case above (e.g. 6-after case = 6 records).
- Literal `\x1e` byte *in a cmd*: **node≡python DIVERGENCE** — node `1/2` vs py `1/1` (node splits the record at the RS, emitting a bogus `[b' >/dev/null; true]` entry). Gate outcome coincidentally still blocks here. **This divergence is INTRODUCED by the fix**: verified the old newline-transport counted the same `\x1e`-in-cmd gate correctly (1/1, == py). So the fix trades newline-fragility for `\x1e`-fragility. `\x1e` (RS control char) is essentially never in a real shell command; newlines (heredocs) are common — net large improvement, but not a total elimination of the transport-injection class. Task said assess-not-over-weight; noted as a residual hole, not a blocker.
- Empty `dag.gates`/missing gate: node exits 2 ("Unknown gate"), py exits 1 ("unknown"). Pre-existing parity divergence in the unchanged flag/lookup section, unrelated to this fix.

## 5. Is the proof load-bearing?
Reverted BOTH lines to the buggy transport (`console.log` + `read -r ID DESC CMD`) in a scratch copy of the TEMPLATE, re-ran the shipped proof:
```
FAIL: node/bash miscounted a newline cmd: 4 passed / 2 failed (expected 0/3)
  ✗ [a] first
  ✓ [nl] newline cmd          <- false pass
  ✓ [import sys]              <- bogus heredoc-body record
  ✓ [sys.exit(1)]            <- bogus
  ✓ [PYX]                    <- bogus
  ✗ [c] third
=== GATE_X: 4 passed, 2 failed ===
```
→ proof goes RED and names the exact pathology. Restored template → GREEN (`GATE-NEWLINE-CMD-OK`).
`--selftest` → SELFTEST-OK (pass-count and bogus-body detectors each proven load-bearing).
node≡python assertion in the proof is real: it runs `python3 -m heartbeat.cli gate GATE_X --check --dir "$proj"` on the SAME dag and asserts `np==pp && nf==pf`.

## 6. Suites
- Node `tests/run-tests.sh`: **385 passed, 0 failed** (T153.1/T153.2 present & green).
- Python `pytest`: **96 passed**.
- Parity `tests/parity.sh`: **✅ node ≡ python**.
- Gate-driving proofs run directly, all green: gate-parity, gate-shell-parity, restore-points, gate-reverify.

Tree restored clean (only the intended uncommitted fix batch remains: gate.sh, docs/dev-plugin.md, docs/dev-tests.md, tests/run-tests.sh, + new gate-newline-cmd.sh). All scratch dirs removed.

## Residual holes (non-blocking)
1. A literal `\x1e`/`\x1f` control byte inside a cmd still injects transport records on the node side and can desync node vs python. Newlines were the real-world case and are fully fixed; control-byte injection is theoretical. If ever hardened, base64/JSON-line transport would close it entirely.
2. Missing-gate exit code differs node(2) vs python(1) — pre-existing, out of scope.

VERDICT: SOUND
