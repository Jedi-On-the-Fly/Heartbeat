# Review an unsafe gate command

**Outcome:** read a DAG's gate commands with the right suspicion. A gate `cmd` is an arbitrary
shell one-liner that runs with **your** privileges — so a bad or hostile gate is both a
correctness risk (it can fake its own pass) and a safety risk (it can do anything you can).

## What to look for

- **Self-produced evidence (`side_effecting`).** A gate must *observe* reality, not *create*
  it. A criterion that writes the very file it then checks —
  `touch out.txt && test -f out.txt` — always passes and proves nothing. Watch for `>`, `tee`,
  `cp`, `mv`, `mkdir`, `touch`, `sed -i` writing into the project tree.
- **Network or time (`nondeterministic`).** `curl`, `date`, `$RANDOM`, `sleep` make a gate
  flaky and non-reproducible; a gate that sometimes passes isn't a gate. A behavioral check
  should give the same verdict on the same artifact every time.
- **Destructive or privileged commands.** `rm -rf`, writes outside the project, `sudo`,
  piping a download into a shell. A gate runs unattended and with your permissions — treat an
  unfamiliar one like any untrusted script.

## Let the auditor do the first pass

`hb audit` flags exactly these shapes before you ever run the DAG:

```bash
hb audit --dir myproject      # exit 1 on a hollow gate; warns on side_effecting / nondeterministic
```

It catches `side_effecting`, `nondeterministic`, hollow, existence-only, and off-phase gates —
each rule and its rationale is in
[the-auditor-catches-each-weakness.md](the-auditor-catches-each-weakness.md). The auditor is
mechanical, so it can't judge whether a gate tests the *right* behavior — that last mile is
still a human read.

## Running an untrusted DAG

If the DAG came from someone else, the gate commands are code you're about to execute. Review
them first, and run with least privilege — a sandbox or container, a non-privileged user, no
credentials in the environment. HeartBeat's trust model protects you from a lying *worker* (a
behavioral gate and distinct-actor review mean it can't fake a pass), but the *gate command
itself* is yours to vet.

## Prove it worked

A runnable proof shows the auditor flagging an unsafe DAG (a gate that writes its own evidence,
and one that depends on the clock) while clearing a safe read-only gate:

```bash
bash docs/howto/gate-examples/unsafe-gate.sh   # -> UNSAFE-GATE-OK
```
