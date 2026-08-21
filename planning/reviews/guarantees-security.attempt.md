# Adversarial review — "guarantees + SECURITY" docs change

Refuter attempt against three changes: a README "What it verifies — and where it stops"
section, a new root `SECURITY.md`, and the T93 prose-gate extension over root `*.md` (with the
STATUS.md `hb viz` → `hb-viz.js` fix that the extended gate caught).

Method: read the referenced code AND docs, ran the real suites, and tried to make the new gate
go RED. Phase anchor: `tests/run-tests.sh` T93 (lines ~1236–1238), `plugin/templates/gate.sh`,
`py/src/heartbeat/mcp_server.py`, `py/src/heartbeat/scaffold.py`, `docs/howto/gate-examples/prose-check.sh`.

## 1. SECURITY.md accuracy vs code — every claim backed

- **(a) "A `dag.json` / executor is trusted input = running a shell script."** Backed.
  `plugin/templates/gate.sh` runs each criterion via `run_criterion(){ ... bash -c "$1"; }` and
  states in-source: *"dag.json is TRUSTED input (criteria are eval'd)."* A gate criterion is a
  shell command executed by `.hb/gate.sh`. Accurate, not overstated.
- **(b) MCP HTTP: loopback-only, Origin-validated, refuses non-loopback without `--allow-remote`,
  UNAUTHENTICATED.** Backed by `py/src/heartbeat/mcp_server.py`:
  - `serve_http(hbdir, host="127.0.0.1", ...)` — default bind is `127.0.0.1`.
  - `if not _is_loopback_host(host) and not allow_remote:` → writes a refusal to stderr and
    `return 2`. (`_is_loopback_host` rejects `"127.0.0.1.evil.com"` — it must parse as an IP.)
  - `do_POST`: `if not _origin_ok(...): 403 "forbidden origin"` — the DNS-rebinding defence.
  - No auth anywhere; source comment: *"the endpoint is unauthenticated and can run gate
    shell-commands."* CLI wiring confirms the surface: `cli.py:54` `mcp-serve --http --host
    (default 127.0.0.1) --allow-remote`. SECURITY.md's wording ("`hb mcp-serve --http`") matches.
- **(c) "Auto-commits on gate pass, never auto-pushes."** Backed. Every git write in the repo is a
  `commit` (`gate.sh git_snapshot`, `hb.js:476`, `hb-exec.js:239`, `gate.py:113`, `executor.py:216`,
  `scaffold.py:81`), all gated by `HB_GIT_AUTOCOMMIT != "0"` / `HB_NO_GIT`. A grep for any `push`
  invocation finds NONE — the only occurrences of "push" are in hook/message strings and the
  pre-push guard. The pre-push guard claim ("re-verifies gates before a manual push, bypassable
  with `git push --no-verify`") matches `scaffold.py` `_PRE_PUSH_HOOK` exactly (`hb gate --all`,
  exit 1 on failure, `HB_NO_HOOK`/`--no-verify` bypass).

No SECURITY.md statement is unbacked. Substantive: 23 non-blank lines, four sections, passes the
prose-gate's ≥15-line floor.

## 2. README "What it verifies — and where it stops" — honest, arguably conservative

- **Gates prove behavior, not abstract correctness** — matches AGENTS.md rule 3 and the
  auditor/refutation model; gate.sh eval's authored criteria. Correct.
- **Grounding ≠ truth** — `docs/howto/ground-research-claims.md:52` says the adapter's
  `ground-check` "proves the quote is real ... It does not judge [truth]." README's claim and link
  are faithful. The tool is named `ground-check` (adapter `ground-check.js` / `ground_check.py`) —
  README's backticked `ground-check` is accurate.
- **Distinct actor = identity; distinct capability = opt-in** — `cli.py:205-212` enforces
  identity via `HB_ACTOR` (self-review rejected); `docs/howto/cross-model-verification.md:9`
  states the different-model path "is opt-in." Correct on both halves.
- **Doc-gating covers how-tos + `adapters.md`, not yet every reference-doc list** — an honest
  hedge; and after this change T93 gates root docs too, so if anything the bullet slightly
  UNDER-claims (safe direction). `adapters.md` exists and is gated.
- **`dag.json`/executor = trusted input** — matches gate.sh source. Links to SECURITY.md, which
  resolves.

All five README links resolve in-place (`docs/howto/ground-research-claims.md`,
`cross-model-verification.md`, `docs/adapters.md`, `SECURITY.md`). No bullet overclaims.

## 3. T93 extension has TEETH; the exclusion is honest

**Teeth — proven, not asserted.** Copied `SECURITY.md`, appended (i) a broken relative link
`[nope](does-not-exist-xyz.md)` and (ii) a fake `hb frobnicate` command, then ran
`prose-check.sh` on each copy: **both REJECTED** ("broken link in ...", "unknown hb command ...")
→ PROSE-FAIL. So a rotted root doc or a fake `hb <sub>` now goes RED. `prose-check.sh` derives the
real subcommand set from `py/src/heartbeat/cli.py` (`add_parser(...)` + the loop verbs), which is
precisely why it flags `hb viz` — hence the STATUS.md fix below.

**The gate actually gates root files now.** Simulating the exact T93 expression with the real
`/usr/bin/find`: `FILES` contains all six root docs (README, SECURITY, INSTALL, AGENTS, STATUS,
CLAUDE-MD-SNIPPET), `n=83`, and prose-check emits `ALL-PROSE-OK:83`. (Caveat noted for the record:
my sandboxed agent shell wraps `find` as a function that `exec`s inside `$(...)`, dropping any
sequenced command after it — this made an early run look like the root files vanished. That is a
harness artifact of *my* shell only; the real test harness uses `/usr/bin/find` and the live suite
run below confirms the gate sees all root files.)

**Exclusion regex is correct.** `ls "$R"/*.md | grep -v "/CLAUDE\.md$"` anchors on the full path
segment: it drops exactly `CLAUDE.md` and KEEPS `CLAUDE-MD-SNIPPET.md` (which does not end in
`/CLAUDE.md`). Verified against the real file list — CLAUDE-MD-SNIPPET.md remains gated (it passes
prose-check), CLAUDE.md is the only exclusion.

**Excluding CLAUDE.md is justified, not hiding a doc.** CLAUDE.md is 5 lines: a one-line intro and
`@AGENTS.md` import pointer. It cannot meet prose-check's ≥15-line substance floor by design, and
its content is AGENTS.md — which IS gated. Excluding it is honest; the group title documents the
reason.

**STATUS.md `hb viz` → `hb-viz.js` fix is correct.** There is no `viz` subcommand in `hb.js` or
`cli.py` (grep: none). `hb-viz.js` is a standalone node template that supports `--serve
[--port][--host][--allow-remote]` with the same loopback-bind + Origin-validation as the MCP
server, and is referenced identically elsewhere (`dev-plugin.md`, `watch-a-run-live.md`). So the
old `hb viz --serve` named a non-existent command; `hb-viz.js --serve` is the right reference. This
is exactly the class of defect the extended gate is designed to catch.

## 4. Links resolve + suites green

- `SECURITY.md` → `docs/howto/secure-the-mcp-server.md` resolves (file exists).
- All README links resolve (see §2).
- `HB_NO_GIT=1 bash tests/run-tests.sh`: **336 passed, 0 failed**; T93 present in GROUPS-PASSED;
  T93.1 group title updated to name the root claim-docs.
- Python suite: **96 passed**.
- prose-check in-place on README.md + SECURITY.md + STATUS.md → PROSE-OK each; all six gated root
  files → `ALL-PROSE-OK:6`.
- SECURITY.md is substantive (23 non-blank lines, four sections), not thin.

Tree left clean (only the intended `README.md`/`STATUS.md`/`tests/run-tests.sh` edits + untracked
`SECURITY.md`; all scratch files were under `/tmp` and removed).

## Conclusion

Every SECURITY.md and README claim is backed by code or the point-of-use doc it links. The T93
extension genuinely gates root docs (proven RED on a broken link and a fake `hb` command), the
CLAUDE.md exclusion is honest and the regex does not over-exclude CLAUDE-MD-SNIPPET.md, and the
STATUS.md fix corrects a real non-existent-command reference. All suites and prose checks pass. I
could not refute the change.

VERDICT: SOUND
