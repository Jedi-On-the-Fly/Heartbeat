# GATE_PT — Portability — refuter's attempt

**Actor:** reviewer (HB_ACTOR distinct from the implementer)
**Method:** refute, don't confirm. Mutate each fix to check the proof's teeth. All mutations were run against **temp copies** of the tree; the working tree was left untouched (re-verified at the end).

Phase claims three fixes, each with a proof wired into the node suite:
- **C5** — `tick.sh compute_watch_hash` uses `sha256sum` else `shasum -a 256` (macOS), no silent empty hash. Proof `drift-portable.sh` (T132).
- **C6** — 3 adapter skills use `${CLAUDE_PLUGIN_ROOT}/adapters/...` for runnable node/bash commands. Proof `skill-paths.sh` (T133).
- **C7+R9** — `drive-heartbeat-over-mcp.md` documents the MCP server needs the Python `hb`; the heartbeat skill documents `/heartbeat` is a skill, not a `plugin/commands/` dir. Proof `mcp-json-runtime.sh` (T134).

---

## 1. C5 teeth — DECISIVE, HOLDS

- Baseline: all three proofs green on the real tree (`DRIFT-PORTABLE-OK`, `SKILL-PATHS-OK`, `MCP-JSON-RUNTIME-OK`).
- **Mutation (revert to `sha256sum`-only):** copied the tree, rewrote `compute_watch_hash` to `xargs sha256sum | sha256sum` (no shasum fallback), pointed a copy of the proof at it, ran under the proof's clean PATH. Result:
  ```
  sha256sum: command not found
  FAIL: drift hash EMPTY when sha256sum absent (silent no-op — macOS drift disabled)
  (exit 1)
  ```
  → RED, with the exact silent-no-op failure. Proof has teeth.
- **PATH is genuine:** clean bin has no `sha256sum` (`command -v sha256sum` → absent) and a real `shasum` symlink present. Confirmed manually.
- **Fixed version:** under the sha256sum-free PATH, `h1` is a non-empty 64-hex hash via shasum, and `h1 != h2` when the watched file content changes (`15143e31…` → `a61a8b84…`). Non-empty AND changes.
- **Not dead:** §4 drift (tick.sh line 223) calls `compute_watch_hash` on the live path; the `--freeze` path (line 124) also calls it. T8 (drift+freeze) still green on the normal path.
- Proof also passes in a fully clean non-interactive shell (`env -i … --noprofile --norc`), so it is not relying on any interactive-shell leak.

**C5: sound.**

## 2. C6 teeth — HOLDS

- All runnable adapter commands in the 3 skills are `${CLAUDE_PLUGIN_ROOT}`-based (grep across research-grounding / code-aware-planning / docs-authoring): a `grep -nE '(node|bash) +plugin/adapters/'` over the three returns NONE.
- **Mutation:** reverted one command in `research-grounding/SKILL.md` to bare `node plugin/adapters/research/stamp-evidence.js` on a temp copy → proof:
  ```
  FAIL: research-grounding: runnable command uses bare 'plugin/adapters/...' (…use ${CLAUDE_PLUGIN_ROOT})
  (exit 1)
  ```
  → RED. Proof has teeth.
- No regression to skill-integrity (T92) or whole-docs prose (T93): both green in the full suite (see §4).
- (Prose/markdown-link refs to `docs/` not shipped in the plugin are the known separate limitation, out of scope.)

**C6: sound.**

## 3. C7/R9 — **C7 PROOF IS HOLLOW (self-satisfying) — REFUTED**

### Honesty of the claims (both accurate)
- `.mcp.json` declares `{"command":"hb","args":["mcp-serve"]}`.
- The C7 doc note in `docs/howto/drive-heartbeat-over-mcp.md` is present and **truthful**: node `hb.js` (`plugin/templates/hb.js`) has **no** `mcp-serve` — its usage line is `start|done|fail|heartbeat|ready|review|doctor|diagnose|protocol|rebuild|state|import` and `node hb.js mcp-serve` exits 1. Only Python `hb` implements it (`py/src/heartbeat/cli.py` + `mcp_server.py`). A node-only install genuinely cannot run `hb mcp-serve`.
- The R9 skill note is present and truthful: `plugin/skills/heartbeat/SKILL.md` line 15 states the verbs are "provided by **this skill** … not a `plugin/commands/` directory"; there is no `plugin/commands/` dir; the skill is invoked as `heartbeat:heartbeat`.

### R9 branch — has teeth
- **Mutation:** removed the skill note from a temp copy of `SKILL.md` (no commands/ dir) → proof RED:
  `FAIL: no plugin/commands/ AND the heartbeat skill does not document the skill-not-commands design (R9 undecided)` (exit 1). Good.

### C7 branch — NO TEETH (decisive defect)
The refutation criterion is explicit: *"remove the doc note → RED?"* It does **not** go red.

Root cause: `mcp-json-runtime.sh` greps **recursively over `$ROOT/docs`** for the C7 pattern:
```
grep -rqiE 'mcp.*(requires|needs).*(python|hb|heartbeat-hb|pip)|…|python.*(package|hb).*mcp-serve' "$ROOT/docs" "$ROOT/INSTALL.md"
```
But the proof script itself lives at `$ROOT/docs/howto/gate-examples/mcp-json-runtime.sh`, and **its own comment lines match that pattern**:
- line 3: `# C7: .mcp.json declares the server AND a doc states it needs the Python \`hb\``
- line 13: `# C7: a doc must state the MCP server needs the Python hb / package install`

So the gate asserts the existence of a text pattern that the gate's own source satisfies.

**Decisive mutation:** on a temp copy of the tree, deleted the real C7 doc note (the `> Runtime note.` line in `drive-heartbeat-over-mcp.md`) and the `dev-tests.md` mention. Confirmed the only remaining matches of the C7 grep were the proof script's own comment lines. Ran the proof (ROOT = temp copy):
```
=== drive doc still has the note? ===  → GONE from drive doc
=== but what still matches C7 grep? ===  → (only gate-examples/proof matches remain)
=== run proof with real note removed but proof script intact ===
MCP-JSON-RUNTIME-OK
(exit 0)
```
→ **GREEN with the real doc note deleted.** The C7 half of the gate can never detect regression of the very thing it claims to guard. Per AGENTS.md Rule 3 this is a hollow gate (asserts existence, and self-satisfies), and the doc claim (Rule 7) is therefore not actually gated. `hb-audit`'s hollow-gate contract would not catch this because the gate *does* run a `grep` (it isn't `true`/`test -f`); the flaw is that its search scope includes itself.

**C7: proof is hollow — the phase's own refutation criterion ("remove the doc note → RED") fails.**

Suggested minimal fix (not applied — review only): scope the C7 grep to the actual doc(s) (e.g. grep `$ROOT/docs/howto/drive-heartbeat-over-mcp.md` and `$ROOT/INSTALL.md`, or `--exclude-dir=gate-examples`), and add a self-test mutation that deletes the note and asserts RED.

## 4. No regression — HOLDS

- `HB_NO_GIT=1 bash tests/run-tests.sh` → **352 passed, 0 failed**; GROUPS include T8 (drift), T92 (skill-integrity + selftest), T93 (whole-docs prose), T132, T133, T134.
- `cd py && PYTHONPATH=src pytest -q` → **96 passed**.
- `bash tests/parity.sh` → **PARITY OK — node ≡ python**.
- The tick.sh change did not break T8 drift on the normal path; the skill edits did not break T92/T93.
- **Note:** the full suite being green does *not* clear the phase — T134 is green precisely because the C7 gate is self-satisfying. A passing hollow gate is the failure mode being refuted.

## Tree hygiene
All mutations ran in `mktemp -d` copies. Re-verified after: the three proofs are green on the real tree, and the real C7 doc note + R9 skill note are intact (grep counts = 1 each). The working-tree modifications shown by `git status` are the pre-existing PT phase work under review, not introduced by this review.

---

**Summary:** C5 (decisive) and C6 are sound with real teeth. C7's honesty is fine, but its **proof is hollow** — `mcp-json-runtime.sh` greps `$ROOT/docs` recursively and matches its own comment lines, so deleting the real doc note leaves the gate GREEN, directly failing the phase's stated refutation criterion. Phase PT is not done.

VERDICT: REFUTED

---

# GATE_PT — re-verification of the C7 fix (second pass)

**Actor:** reviewer (HB_ACTOR distinct from the implementer)
**Method:** refute, don't confirm. All mutations run on **temp copies** of the tree; working tree left untouched (re-verified at the end).

The prior pass REFUTED for one reason: the C7 half of `mcp-json-runtime.sh` grepped `$ROOT/docs` recursively for a broad "mcp + python" co-occurrence, so it self-matched the proof's own comment lines (and other docs) — deleting the real doc note left it GREEN. This pass verifies the claimed fix.

## 1. C7 teeth now real — DECISIVE, HOLDS

The gate now uses:
`grep -rqiE --include='*.md' 'node-only.*(cannot|can.?t|can not) run.*mcp-serve' "$ROOT/docs" "$ROOT/INSTALL.md"`

- Baseline (temp copy): `MCP-JSON-RUNTIME-OK`, exit 0.
- **Delete** the `node-only … cannot run hb mcp-serve` note line from `drive-heartbeat-over-mcp.md` → `FAIL: no doc states a node-only install cannot run the MCP server …`, **exit 1 (RED).**
- **Restore** the note → `MCP-JSON-RUNTIME-OK`, exit 0. Decisive.
- **No self-match:** `--include='*.md'` excludes the `.sh` proof. Confirmed both ways — with `--include='*.md'` zero `.sh` lines match; dropping `--include` the old broad pattern *does* self-match `mcp-json-runtime.sh` (the exact hollowness the fix removes).
- **Not satisfied by unrelated docs:** the specific phrase appears in exactly ONE file — `docs/howto/drive-heartbeat-over-mcp.md`. No other `.md` carries it.
- **Claim still TRUE:** node `plugin/templates/hb.js` contains no `mcp` at all (there is no `plugin/hb.js`; the node CLI is `plugin/templates/hb.js`). Only the Python `hb` implements it: `py/src/heartbeat/cli.py` (`add_parser("mcp-serve")`, dispatch at ~L259) → `py/src/heartbeat/mcp_server.py`. A node-only install genuinely cannot run `hb mcp-serve`.

## 2. R9 half still has teeth — HOLDS

No `plugin/commands/` dir exists, so R9 rests on the heartbeat SKILL.md note. On a temp copy, stripping the skill-not-commands note (lines matching `not a plugin/commands | provided by this skill | is a … skill`) with no `commands/` dir → `FAIL: no plugin/commands/ AND the heartbeat skill does not document the skill-not-commands design (R9 undecided)`, **exit 1 (RED).**

## 3. C5 + C6 unchanged and still sound — HOLDS (spot-check)

- **C5** `drift-portable.sh`: reverting `compute_watch_hash` in `tick.sh` to sha256sum-only (no `shasum -a 256` fallback) → under the sha256sum-less clean PATH, hash empty → `FAIL: drift hash EMPTY when sha256sum absent …`, **exit 1 (RED).**
- **C6** `skill-paths.sh`: reintroducing a bare `node plugin/adapters/…` runnable command into `research-grounding/SKILL.md` → `FAIL: research-grounding: runnable command uses bare 'plugin/adapters/...' …`, **exit 1 (RED).**

## 4. No regression — HOLDS

- Node: `HB_NO_GIT=1 bash tests/run-tests.sh` → **352 passed, 0 failed** (T132, T133, T134 all green; T8/T92/T93 in GROUPS-PASSED).
- Python: `pytest -q` in `py/` → **96 passed**.
- Parity: `bash tests/parity.sh` → **PARITY OK — node ≡ python**.

## Verdict

The C7 proof now has real teeth: it is decisive (delete→RED / restore→green), no longer self-matches the proof's own comments (excluded by `--include='*.md'`), and is satisfied only by the one doc carrying the specific phrase — not by unrelated docs. The underlying claim is TRUE. R9, C5, C6 remain sound; all suites green. The single defect that grounded the prior refutation is fixed and no new defect was found.

VERDICT: COULD NOT REFUTE
