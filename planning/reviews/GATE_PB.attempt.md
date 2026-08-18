# GATE_PB review — docs adapter ported to Python (parity surface)

Adversarial review of the shipped PB work, distinct actor from the implementer.

## Round 1 — UNSOUND (port correct; a real byte-parity bug + proof/test gaps)
The core port was faithful (docs-map set-parity holds on an aggressive adversarial corpus;
docs-context byte-parity on ASCII; boundary clean). Three defects:
- **[Real] byte-parity false for BOM/NEL** — Python `.strip()` ≠ JS `.trim()`: JS strips U+FEFF (BOM)
  but not U+0085 (NEL); Python the reverse. A BOM-prefixed .md (a Windows-editor artifact) rendered
  differently → the "byte-identical" claim was refuted.
- **[Proof gap]** docs-context-parity.sh never exercised the cites-nothing / missing-file branches
  (a mutation to those strings passed).
- **[Test gap]** py test omitted those branches.

## Fix (code + proof + test; gate not weakened)
- Added `js_trim()` with `_JS_WS` = exactly the JS `.trim()` char set (WhiteSpace + LineTerminator),
  used on section text (docs_context) and link targets (docs_map, via a relative import). Verified
  empirically: js_trim ≡ node .trim() across BOM/NEL/nbsp/unicode-spaces/ZWSP with 0 mismatches, and
  the re-reviewer computed node's authoritative trim set over U+0000–U+10FFFF — EXACT match.
- docs-context-parity.sh now covers `background` (cites-nothing) and an orphan/ghost missing-file
  case; py test adds cites-nothing, missing-file, and a BOM/NEL test.

## Round 2 — SOUND
Re-review confirmed: BOM section renders byte-identical (BOM stripped, NEL kept by both); the
cites-nothing and missing-file branches now FAIL the proof under mutation; docs-map unaffected;
import is intra-adapter (not core); stdlib-only, no subprocess. Node 311/0, python 85, parity OK.

**VERDICT: SOUND**
