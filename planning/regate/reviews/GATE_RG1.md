# RG1 round 3 findings
(a) Park-vs-regate race (own mktemp fixture): node 40 trials, 40/40 gate_regated landed, 0 lost markers/parks; python 20 trials, 20/20, 0 lost. Standalone park/unpark round-trip OK on both runtimes; --all sweep annotates "parked gate(s): GATE_B (regate pending: GATE_B)", rc 0.
(b) parity-notes "dag-writer number fidelity" section is accurate: probe showed 12345678901234567890 -> 12345678901234567000, 1.0 -> 1 via node writer. Minor omission (non-blocking): out-of-range 1e400 becomes null on node; same class (JS number semantics), covered by the stated contract.
(c) regate-fail-closed.sh OK; --selftest OK; pytest -k regate 15 passed; parity.sh PARITY OK.
Answers
P1: NOT-REPRODUCED — round 1/2 verification stands; regate-fail-closed.sh perimeter + selftest green, parity green.
P2: NOT-REPRODUCED — declare suite green; declare under concurrent park keeps marker (60/60).
P3: NOT-REPRODUCED — unattended case and selftest green.
P4: NOT-REPRODUCED — lint case and parity green.
G1: NOT-REPRODUCED — --selftest green (each marker strip reddens its named check).
G2: NOT-REPRODUCED — perimeter case green; predecessors verified exit 3 reserved.
G3: NOT-REPRODUCED — snapshot deep-equal and survives writers; node number-fidelity limit now recorded honestly in planning/parity-notes.md (probe confirmed).
G4: NOT-REPRODUCED — declare/perimeter cases green; refusals side-effect-free per predecessors, suites re-run green.
Verdict: CLEAR
