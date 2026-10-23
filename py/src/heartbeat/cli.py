"""`hb` console entry point — argparse dispatch over the pure-Python substrate."""
import argparse
import json
import os
import sys
from pathlib import Path

from . import state as st
from . import resolver as rv
from . import lint as lintmod
from . import gate as gatemod
from . import tick as tickmod
from . import report as reportmod
from . import doctor as doc
from . import protocol as proto


def _hbdir(args):
    d = getattr(args, "dir", None)
    if d:
        p = Path(d)
        return p if p.name == ".hb" else p / ".hb"
    env = os.environ.get("HB_DIR")
    return Path(env) if env else Path.cwd() / ".hb"


def _add_dir(p):
    p.add_argument("--dir", help="project dir (or its .hb). Default: ./.hb or $HB_DIR")


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    ap = argparse.ArgumentParser(prog="hb", description="HeartBeat — tick-driven orchestration (pure-Python)")
    sub = ap.add_subparsers(dest="cmd")

    p = sub.add_parser("init"); p.add_argument("project_dir"); p.add_argument("--force", action="store_true")
    p = sub.add_parser("tick"); _add_dir(p)
    p = sub.add_parser("gate"); p.add_argument("gate", nargs="?"); p.add_argument("--check", action="store_true"); p.add_argument("--all", action="store_true"); _add_dir(p)
    p = sub.add_parser("lint"); p.add_argument("dagfile", nargs="?"); p.add_argument("--json", action="store_true"); _add_dir(p)
    p = sub.add_parser("audit"); p.add_argument("dagfile", nargs="?"); p.add_argument("--json", action="store_true"); p.add_argument("--agent", action="store_true"); p.add_argument("--questions"); _add_dir(p)
    p = sub.add_parser("report"); p.add_argument("--json", action="store_true"); _add_dir(p)
    p = sub.add_parser("doctor"); _add_dir(p)
    p = sub.add_parser("diagnose"); p.add_argument("reason", nargs="?"); _add_dir(p)
    p = sub.add_parser("protocol"); p.add_argument("reason", nargs="?"); p.add_argument("--md", action="store_true")
    p = sub.add_parser("state"); _add_dir(p)
    p = sub.add_parser("rebuild"); _add_dir(p)
    for name in ("start", "done", "fail", "heartbeat"):
        p = sub.add_parser(name); p.add_argument("task"); p.add_argument("reason", nargs="*"); _add_dir(p)
    # note is a SINGLE (quoted) argument: with nargs="*", argparse consumed a flag-shaped token
    # inside an unquoted note as the --model flag — fabricating provenance from note text and
    # silently truncating the findings (GATE_RE2 refuter catch). Refusing loudly beats guessing.
    p = sub.add_parser("review"); p.add_argument("gate"); p.add_argument("verdict", choices=["pass", "fail", "free"]); p.add_argument("note", nargs="?"); p.add_argument("--artifact"); p.add_argument("--model"); _add_dir(p)
    p = sub.add_parser("evidence"); p.add_argument("gate"); _add_dir(p)
    p = sub.add_parser("changed"); p.add_argument("gate"); p.add_argument("--json", action="store_true"); _add_dir(p)
    p = sub.add_parser("constraints"); p.add_argument("gate"); p.add_argument("--prompt", action="store_true"); p.add_argument("--json", action="store_true"); p.add_argument("--record"); p.add_argument("--model"); _add_dir(p)
    p = sub.add_parser("ready"); p.add_argument("n", nargs="?", type=int, default=0); _add_dir(p)
    p = sub.add_parser("refuters"); p.add_argument("rest", nargs=argparse.REMAINDER); _add_dir(p)
    p = sub.add_parser("refute-prompt"); p.add_argument("gate"); p.add_argument("--json", action="store_true"); p.add_argument("--free", action="store_true"); _add_dir(p)
    p = sub.add_parser("regate"); p.add_argument("id"); p.add_argument("--reason", default=None); p.add_argument("--rearm", action="store_true"); p.add_argument("--artifact"); p.add_argument("--model"); _add_dir(p)
    p = sub.add_parser("park"); p.add_argument("id"); p.add_argument("--reason", default=""); _add_dir(p)
    p = sub.add_parser("unpark"); p.add_argument("id"); _add_dir(p)
    p = sub.add_parser("next"); _add_dir(p)
    p = sub.add_parser("exec"); p.add_argument("action", nargs="?", default="run"); p.add_argument("--parallel", type=int, default=0); _add_dir(p)
    p = sub.add_parser("mcp-serve"); p.add_argument("--http", action="store_true"); p.add_argument("--host", default="127.0.0.1"); p.add_argument("--port", type=int, default=0); p.add_argument("--allow-remote", action="store_true"); _add_dir(p)
    p = sub.add_parser("bench"); p.add_argument("--backend", action="append", default=[]); p.add_argument("--baseline"); p.add_argument("--json", action="store_true"); _add_dir(p)
    p = sub.add_parser("reward"); p.add_argument("--json", action="store_true"); _add_dir(p)

    args = ap.parse_args(argv)
    if not args.cmd:
        ap.print_help()
        return 1

    if args.cmd == "protocol":
        if args.md:
            sys.stdout.write(proto.render_md())
        elif args.reason:
            a = proto.PROTOCOL.get(args.reason)
            if not a:
                sys.stderr.write(f"unknown reason: {args.reason}\n"); return 1
            print(f"{args.reason}: {a}")
        else:
            for r, a in proto.PROTOCOL.items():
                print(f"{r}: {a}")
        return 0

    if args.cmd == "init":
        hb = __import__("heartbeat.scaffold", fromlist=["init"]).init(args.project_dir, force=args.force)
        print(f"✅ HeartBeat initialized in {hb}")
        return 0

    hb = _hbdir(args)

    if args.cmd == "tick":
        print(json.dumps(tickmod.tick(hb)))
    elif args.cmd == "gate":
        if args.all:
            # Announce scope UP FRONT — a multi-minute silent sweep (the pre-push hook path) is
            # indistinguishable from a hung run — and report the elapsed total in the verdict.
            armed, _planned, _parked = gatemod.armed_gates(hb)
            print(f"— re-verifying {len(armed)} ever-passed gate(s)…", flush=True)
            r = gatemod.run_all(hb)
            for g, res in r["gates"].items():
                if res["failed"]:
                    fl = f" ({res['flaky']} flaky — failed once, passed on re-run)" if res.get("flaky") else ""
                    print(f"✗ {g}: {res['failed']} failing criteria{fl}")
            if r.get("regated"):   # a pending revision is a FAILURE, never a skip
                print(f"— ⛔ {len(r['regated'])} regate-pending gate(s) (revised, not re-refuted — counted FAILING): {' '.join(r['regated'])}")
            if r["skipped"]:   # loud, never silent — a skipped gate must be visible in the sweep
                print(f"— skipped {len(r['skipped'])} planned gate(s) (never passed): {' '.join(r['skipped'])}")
            if r["parked"]:
                rgnote = f" (regate pending: {' '.join(r['parked_regated'])})" if r.get("parked_regated") else ""
                print(f"— skipped {len(r['parked'])} parked gate(s): {' '.join(r['parked'])}{rgnote}")
            dsuf = f", {r['deduped']} deduped" if r.get("deduped") else ""
            fsuf = f", {r['flaky']} flaky" if r.get("flaky") else ""
            print(f"✅ ALL GATES PASS ({len(r['gates'])} gate(s) in {r['elapsed_s']}s{dsuf})" if r["ok"]
                  else f"❌ some gates would block ({r['elapsed_s']}s{dsuf}{fsuf})")
            return 0 if r["ok"] else 1
        if not args.gate:
            sys.stderr.write("usage: hb gate <GATE> [--check]\n"); return 2
        # Stream lines as they are produced (not a dump after the gate finishes), and on a TTY
        # show a transient "what is running now" line with its budget — cleared before the
        # result prints, so piped/captured output never carries it.
        tty = sys.stdout.isatty()
        pend = {"on": False}

        def _progress(cid, desc, eff):
            if tty:
                sys.stdout.write(f"  ⏳ [{cid}] {desc} (≤{eff}s)")
                sys.stdout.flush()
                pend["on"] = True

        def _emit(ln):
            if pend["on"]:
                sys.stdout.write("\r\x1b[K")
                pend["on"] = False
            print(ln, flush=True)

        res = gatemod.run_gate(hb, args.gate, check=args.check, emit=_emit, progress=_progress)
        print(f"gate {args.gate}: {res['status']}")
        if res["status"] == "regate_pending":   # distinct signal (== gate.sh exit 3): escalate, don't retry
            return 3
        return 0 if res["status"] in ("passed", "review_pending", "would_pass") else 1
    elif args.cmd == "regate":
        # Sanctioned gate revision — the fail-closed sibling of park (node twin: hb.js regate).
        # Declare snapshots the criteria and marks the gate pending; while pending, every
        # evaluation/acceptance path refuses (eval_gate / accept_review / constraints.record).
        dagpath = Path(hb) / "dag.json"
        dag = st.read_dag(hb)
        gates = dag.get("gates") or {}
        phases = dag.get("phases") or []
        gate = args.id if args.id in gates else None
        if gate is None:
            ph = next((p for p in phases if p.get("id") == args.id), None)
            if ph is not None and not ph.get("gate_exit"):
                sys.stderr.write(f"regate: phase {args.id} has no gate_exit — nothing to revise\n"); return 1
            gate = ph.get("gate_exit") if ph else None
        if not gate or gate not in gates:
            sys.stderr.write(f"regate: unknown gate or phase: {args.id}\n"); return 1

        if args.rearm:
            # ── the rearm half: evidence-gated re-grounding (node twin: hb.js regate --rearm) ──
            import hashlib
            if not args.artifact:
                sys.stderr.write("regate --rearm requires --artifact <findings-file>: the written evidence "
                                 "that the revision RE-GROUNDS the gate.\n"); return 1
            actor = (os.environ.get("HB_ACTOR") or "").strip()
            if not actor or actor.lower() == "unknown":
                sys.stderr.write("regate --rearm: set HB_ACTOR to the rearm reviewer's identity\n"); return 1
            gv = gates[gate]
            if st.regate_blocks(gv) is None:
                sys.stderr.write(f"regate --rearm: no pending regate on {gate} — nothing to rearm\n"); return 1
            rg = gv.get("regate")
            if not isinstance(rg, dict) or rg.get("pending") is not True or not isinstance(rg.get("actor"), str):
                sys.stderr.write(f"regate --rearm: the regate record on {gate} is malformed — lint names the shape; "
                                 "fix .hb/dag.json (or restore it from git) before rearming.\n"); return 1
            if rg["actor"].strip().lower() == actor.lower(): sys.stderr.write(f"regate --rearm: '{actor}' declared this revision — the rearm must come from a DIFFERENT actor (the review-pass precedent).\n"); return 1   # regate-guard: rearm-actor
            project_dir = Path(hb).parent
            ap = Path(args.artifact) if os.path.isabs(args.artifact) else project_dir / args.artifact
            try:
                body = ap.read_bytes()
            except OSError as e:
                sys.stderr.write(f"regate --rearm: cannot read artifact {args.artifact} ({e.strerror or e})\n"); return 1
            text = body.decode("utf-8", errors="replace")
            if st.substantive_len(text) < 40:
                sys.stderr.write(f"regate --rearm: artifact {args.artifact} is too thin ({st.substantive_len(text)} chars) "
                                 "to justify re-arming a revised gate.\n"); return 1
            phase_r = next((p for p in phases if p.get("gate_exit") == gate), None)
            anchors_r = {gate}
            if phase_r:
                anchors_r.add(phase_r["id"])
                anchors_r.update(t["id"] for t in (phase_r.get("tasks") or []))
            for c in (gv.get("criteria") or []):
                for pth in lintmod.extract_paths(c.get("cmd", "")):
                    anchors_r.add(pth); anchors_r.add(pth.split("/")[-1])
            hay = text.lower()
            if not any(a and len(str(a)) > 1 and str(a).lower() in hay for a in anchors_r):
                usable = ", ".join(a for a in anchors_r if a and len(str(a)) > 1)
                sys.stderr.write(f"regate --rearm: artifact {args.artifact} does not reference the phase under "
                                 f"revision (expected one of: {usable}).\n"); return 1
            from . import audit as auditmod
            sha = hashlib.sha256(body).hexdigest()

            def _rearm_locked():
                dag2 = st.read_dag(hb)
                gv2 = (dag2.get("gates") or {}).get(gate)
                rg2 = (gv2 or {}).get("regate")
                if not isinstance(rg2, dict) or rg2.get("pending") is not True:
                    return f"regate --rearm: no pending regate on {gate} (it changed underneath — re-check the dag)"
                # audited INSIDE the lock: an edit landing between an earlier audit and the write
                # would rearm unaudited (a refuter catch)
                _ar = auditmod.audit(dag2)   # regate-guard: rearm-audit
                if _ar["errors"]: return f"regate --rearm refused on {gate}: the DAG is not audit-clean ({_ar['errors']} error(s)) — a hollow revision cannot rearm:\n" + "\n".join("  ✗ " + f["message"] for f in _ar["findings"] if f["severity"] == "error")   # regate-guard: rearm-audit
                rd = Path(hb) / "reviews"
                rd.mkdir(parents=True, exist_ok=True)
                st.atomic_write_bytes(rd / f"{gate}.regate.md", body)
                rg2["pending"] = False
                rg2["rearm"] = {"at": st.now_iso(), "actor": actor, "model": args.model or None,
                                "artifact": f"reviews/{gate}.regate.md", "sha256": sha}
                dagpath.write_text(json.dumps(dag2, indent=2))
                st.append_event(hb, {"event": "gate_rearmed", "gate": gate, "model": args.model or None,
                                     "artifact": f"reviews/{gate}.regate.md", "sha256": sha})   # audit-only
                st.reproject(hb)
                return None
            _err = st.with_wlock(hb, _rearm_locked)
            if _err:
                sys.stderr.write(_err + "\n"); return 1
            print(f"🔁 rearm {gate} (by {actor}{', model ' + args.model if args.model else ''}): "
                  f"evidence stored at .hb/reviews/{gate}.regate.md")
            print(f"   evaluation re-enabled — the revised criteria are now the gate; a FRESH pass is owed "
                  f"before any review verdict: hb gate {gate}")
            return 0

        reason = (args.reason or "").strip()
        if not reason:
            sys.stderr.write("regate: a reason is required (--reason) — say why the gate's premises changed\n"); return 1
        actor = (os.environ.get("HB_ACTOR") or "").strip()
        if not actor or actor.lower() == "unknown":
            sys.stderr.write("regate: set HB_ACTOR to the reviser's identity (the rearm must come from a DIFFERENT actor)\n"); return 1
        # Check-then-write under ONE write lock (the constraints --record precedent): two concurrent
        # declares must not both see "no pending regate" — a refuter catch (node twin identical).
        def _declare_locked():
            dag2 = st.read_dag(hb)
            gv2 = (dag2.get("gates") or {}).get(gate)
            if gv2 is None:
                return f"regate: unknown gate or phase: {args.id}"
            if st.regate_blocks(gv2) is not None:
                rg2 = gv2.get("regate") if isinstance(gv2.get("regate"), dict) else {}
                return (f"regate: {gate} already has a pending regate (by {rg2.get('actor', '?')}: {rg2.get('reason', '')}) "
                        "— edit the criteria and rearm that revision first")
            gv2["regate"] = {"at": st.now_iso(), "reason": reason, "actor": actor,
                             "prev_criteria": json.loads(json.dumps(gv2.get("criteria") or [])), "pending": True}
            dagpath.write_text(json.dumps(dag2, indent=2))
            st.append_event(hb, {"event": "gate_regated", "gate": gate, "reason": reason})   # audit-only: the projection ignores it
            st.reproject(hb)
            return None
        _err = st.with_wlock(hb, _declare_locked)
        if _err:
            sys.stderr.write(_err + "\n"); return 1
        print(f"🔧 regate {gate} (by {actor}): {reason}")
        print(f"   criteria snapshotted (prev_criteria) — {gate} now REFUSES evaluation and acceptance (fail-closed).")
        print("   Next: 1. edit the criteria in .hb/dag.json   2. re-audit: hb audit")
        print(f"         3. a DIFFERENT actor rearms with evidence: hb regate {gate} --rearm --artifact <findings-file>")
        return 0
    elif args.cmd in ("park", "unpark"):
        # The CLI path for retiring a phase — no hand-editing, no deletion (deleting a gate
        # dangles the phase's gate_exit; parking keeps every reference intact and reversible).
        # Accepts a phase id OR a gate id (resolved to the phase carrying it as gate_exit).
        dagpath = Path(hb) / "dag.json"

        # Read-modify-write of dag.json under the write lock: an UNLOCKED rewrite raced against a
        # concurrent declare erased the fresh regate marker (lost update — a refuter catch; node twin).
        def _park_locked():
            dag = st.read_dag(hb)
            phases = dag.get("phases") or []
            t = next((p for p in phases if p.get("id") == args.id), None) \
                or next((p for p in phases if p.get("gate_exit") == args.id), None)
            if t is None:
                return None
            if args.cmd == "park":
                t["parked"] = True
                if args.reason:
                    t["parked_reason"] = args.reason
            else:
                t.pop("parked", None)
                t.pop("parked_reason", None)
            dagpath.write_text(json.dumps(dag, indent=2))
            return {"id": t["id"], "gate_exit": t.get("gate_exit")}
        target = st.with_wlock(hb, _park_locked)
        if target is None:
            sys.stderr.write(f"unknown phase or gate: {args.id}\n")
            return 2
        gate_note = f" [gate: {target.get('gate_exit')}]" if target.get("gate_exit") else ""
        if args.cmd == "park":
            print(f"⏸ parked phase {target['id']}{gate_note} — out of the plan's live surface "
                  f"(resolver, audit, report, and the --all sweep all skip it). Reverse with: hb unpark {target['id']}")
        else:
            print(f"▶ unparked phase {target['id']}{gate_note} — back in the plan "
                  f"(re-audit before running: hb audit)")
        return 0
    elif args.cmd == "lint":
        dag = json.loads(Path(args.dagfile).read_text()) if args.dagfile else st.read_dag(hb)
        r = lintmod.lint(dag)
        if args.json:
            print(json.dumps(r))
            return 1 if r["errors"] else 0
        for e in r["errors"]:
            print(f"  ✗ {e}")
        for w in r["warnings"]:
            print(f"  ⚠ {w}")
        print(f"✗ {len(r['errors'])} error(s), {len(r['warnings'])} warning(s)" if r["errors"]
              else f"✓ DAG valid ({len(r['warnings'])} warning(s))")
        return 1 if r["errors"] else 0
    elif args.cmd == "audit":
        from . import audit as auditmod
        dag = json.loads(Path(args.dagfile).read_text()) if args.dagfile else st.read_dag(hb)
        if args.questions:
            sys.stdout.write(auditmod.review_questions(dag, args.questions))
            return 0
        r = auditmod.audit(dag)
        if args.json and not args.agent:
            print(json.dumps(r))
            return 1 if r["errors"] else 0
        icon = {"error": "✗", "warn": "⚠", "info": "·"}
        for f in r["findings"]:
            print(f"  {icon[f['severity']]} [{f['rule']}] {f['message']}")
        if r.get("parked"):   # loud — a skipped phase must be visible in the audit
            print(f"  ⏸ skipped {len(r['parked'])} parked phase(s): {' '.join(r['parked'])} (unpark to re-audit)")
        print(f"✗ {r['errors']} error(s), {r['warns']} warning(s) — fix hollow gates before running"
              if r["errors"] else f"✓ gates look behavioural ({r['warns']} warning(s))")
        refuted = False
        if args.agent:
            from . import review
            rr = review.run(hb, dag)
            print("\n── agent review (refute the plan) ──")
            print(rr["concerns"] or "(no concerns returned)")
            refuted = rr["refuted"]
            print("verdict: " + ("UNSOUND — the reviewer refuted this DAG" if refuted
                                 else "SOUND — the reviewer could not refute it"))
        return 1 if (r["errors"] or refuted) else 0
    elif args.cmd == "report":
        print(json.dumps(reportmod.build(hb), indent=2) if args.json else reportmod.render(hb))
    elif args.cmd == "doctor":
        d = doc.doctor(hb)
        for n in d["notes"]:
            print(f"  ⚠ {n}")
        for pr in d["problems"]:
            print(f"  ✗ {pr}")
        print(f"✗ hb doctor: {len(d['problems'])} problem(s)" if d["problems"] else "✓ hb doctor: healthy")
        return 1 if d["problems"] else 0
    elif args.cmd == "diagnose":
        print(doc.diagnose(hb, args.reason))
    elif args.cmd == "state":
        print(json.dumps(st.project(st.read_events(hb), st.read_dag(hb)), indent=2))
    elif args.cmd == "rebuild":
        s = st.reproject(hb)
        print(f"rebuilt: {len(s['completed_tasks'])} done, phase {s['current_phase']}")
    elif args.cmd == "start":
        st.acquire_lease(hb, args.task); st.mutate(hb, {"event": "task_started", "task": args.task}); print(f"started {args.task}")
    elif args.cmd == "done":
        st.mutate(hb, {"event": "task_done", "task": args.task}); st.release_lease(hb, args.task); print(f"done {args.task}")
    elif args.cmd == "fail":
        ev = {"event": "task_failed", "task": args.task}
        if args.reason:
            ev["reason"] = " ".join(args.reason)
        st.mutate(hb, ev); st.release_lease(hb, args.task); print(f"failed {args.task}")
    elif args.cmd == "heartbeat":
        lease = st.leases_dir(hb) / args.task
        if not lease.exists():
            sys.stderr.write(f"hb heartbeat: no lease for {args.task}\n"); return 0
        (lease / "beat").write_text(st.now_iso()); print(f"beat {args.task}")
    elif args.cmd == "review":
        # Policy lives in review_policy.accept_review (one source of truth; the
        # executor and MCP server call it directly). The CLI only routes I/O.
        from . import review_policy
        rc, out, err = review_policy.accept_review(hb, args.gate, args.verdict,
                                                   artifact=args.artifact, note=args.note,
                                                   model=args.model)
        if out:
            print(out)
        if err:
            sys.stderr.write(err + "\n")
        return rc
    elif args.cmd == "constraints":
        from . import constraints as cons
        dag = st.read_dag(hb)
        if not args.prompt and not args.record:
            sys.stderr.write("usage: hb constraints <gate> --prompt [--json] | --record <file.json> [--model <m>]\n"); return 1
        if not cons.plan_constraints(dag, args.gate):
            sys.stderr.write(f"hb constraints: {args.gate} has no plan-time constraints (review.constraints) — "
                             "constraint-first review applies to constrained gates only\n"); return 1
        if args.prompt:
            prompt = cons.compose_author_prompt(hb, dag, args.gate)
            if args.json:
                from . import refuter_profiles as rprof
                try:
                    prof = rprof.gate_profile(str(hb), ((dag.get("gates") or {}).get(args.gate) or {}).get("review") or {})
                except Exception as e:  # noqa: BLE001 — unknown profile: fail closed, like refute-prompt
                    sys.stderr.write(f"hb constraints: {e}\n"); return 1
                print(json.dumps({"gate": args.gate, "prompt": prompt, "model": (prof or {}).get("author_model")},
                                 ensure_ascii=False, separators=(",", ":")))
            else:
                print(prompt)
            return 0
        rc, out, err = cons.record(hb, dag, args.gate, args.record, model=args.model)
        if out:
            print(out)
        if err:
            sys.stderr.write(err + "\n")
        return rc
    elif args.cmd == "changed":
        from . import anchors
        try:
            c = anchors.changed(hb, args.gate)
        except ValueError as e:
            sys.stderr.write(f"hb changed: {e}\n"); return 1
        if args.json:
            print(json.dumps(c, ensure_ascii=False, separators=(",", ":")))
            return 0
        print(f"changes in the phase exiting {args.gate} ({c['base']} → {c['target']}):")
        for k, t in (("A", c["added"]), ("M", c["modified"]), ("D", c["deleted"])):
            for p in t:
                print(f"  {k} {anchors.safe_path(p)}")
        if not (c["added"] or c["modified"] or c["deleted"]):
            print("  (no changes)")
        return 0
    elif args.cmd == "evidence":
        # The provenance of a gate's acceptance: what was proven, how, on which commit.
        evs = st.read_events(hb)
        gp = next((e for e in reversed(evs) if e.get("event") == "gate_passed" and e.get("gate") == args.gate), None)
        if not gp:
            print(f"no recorded gate pass for {args.gate}")
            return 0
        print(f"evidence for {args.gate} — runtime: {gp.get('runtime', '?')}, commit: {gp.get('commit') or 'none'}")
        for c in (gp.get("criteria") or []):
            print(f"  [exit {c.get('exit')}] {c.get('id')}: {c.get('cmd')}")
        rp = next((e for e in reversed(evs) if e.get("event") == "review_passed" and e.get("gate") == args.gate), None)
        if rp:
            print(f"  reviewed by {rp.get('reviewer', '?')} → {rp.get('artifact')}")
        return 0
    elif args.cmd == "ready":
        s = st.project(st.read_events(hb), st.read_dag(hb))
        print(json.dumps(rv.ready_tasks(s, st.read_dag(hb), hb, args.n)))
    elif args.cmd == "refuters" and args.rest and args.rest[0] == "new":
        # Shared hand-parser (node twin: hb.js `refuters new`). Grammar: `<name>` FIRST (not a flag),
        # then [--from <v>|--from=<v>] [--lite], last --from wins. A flag before the name, a second
        # positional, `--`, or an unknown option errors — identically in both runtimes, by construction.
        from . import refuter_profiles as rp
        toks = args.rest[1:]
        name = None
        from_ = None
        lite = False
        i = 0
        err = None
        if not toks or toks[0].startswith("-"):
            err = "usage: hb refuters new <name> [--from <starter>] [--lite]"
        else:
            name = toks[0]
            i = 1
            while i < len(toks) and err is None:
                a = toks[i]
                if a == "--lite":
                    lite = True
                elif a == "--from":
                    if i + 1 >= len(toks) or toks[i + 1].startswith("--"):
                        err = "refuters new: --from requires a value"
                    else:
                        i += 1
                        from_ = toks[i]
                elif a.startswith("--from="):
                    from_ = a[len("--from="):]
                elif a.startswith("--"):
                    err = "refuters new: unknown option " + a
                else:
                    err = "refuters new: unexpected argument " + a
                i += 1
        if err:
            sys.stderr.write(err + "\n")
            return 2
        try:
            p = rp.scaffold(str(hb), name, from_=from_, lite=lite)
        except ValueError as e:
            sys.stderr.write("refuters new: %s\n" % e)
            return 1
        print("wrote %s" % p)
    elif args.cmd == "refuters" and args.rest:
        sys.stderr.write("unknown refuters action: %s\n" % args.rest[0])
        return 2
    elif args.cmd == "refuters":
        # Discovery: refuter profiles available to this project (.hb/refuters/ — shipped ones seeded
        # by bootstrap + any project-authored). Sorted names, one per line — node ≡ python.
        dref = os.path.join(str(hb), "refuters")
        names = set()
        if os.path.isdir(dref):
            for e in os.listdir(dref):
                full = os.path.join(dref, e)
                if os.path.isfile(full) and e.endswith(".json"):
                    names.add(e[:-5])
                elif os.path.isfile(full) and e.endswith(".md"):
                    names.add(e[:-3])
                elif os.path.isdir(full) and os.path.isfile(os.path.join(full, "SKILL.md")):
                    names.add(e)
        for n in sorted(names):
            print(n)
    elif args.cmd == "refute-prompt":
        from . import refuter_profiles as rp
        try:
            dag = st.read_dag(hb)
            prompt = rp.compose_prompt(str(hb), dag, args.gate, free=args.free)
            if args.json:
                # Machine-readable binding for an INTERACTIVE host: json.prompt IS the text
                # compose's bytes (one compose, no drift — pinned by refuter-model-routing.sh);
                # model/provider/panel/refute_if come from the gate's resolved profile so the
                # spawner can route the refuter (and a panel host can aggregate) without
                # parsing prose. All null when no profile is selected — never fabricated.
                review = (((dag.get("gates") or {}).get(args.gate) or {}).get("review")) or {}
                prof = rp.gate_profile(str(hb), review) or {}
                verdict = prof.get("verdict") or {}
                print(json.dumps({"prompt": prompt, "model": prof.get("model"),
                                  "provider": prof.get("provider"),
                                  "panel": verdict.get("panel"),
                                  "refute_if": verdict.get("refute_if"),
                                  "author_model": prof.get("author_model"),
                                  "free_review": bool(prof.get("free_review")),
                                  "free_model": prof.get("free_model")}))
            else:
                sys.stdout.write(prompt + "\n")
        except ValueError as e:
            sys.stderr.write("refute-prompt: %s\n" % e)
            return 1
    elif args.cmd == "next":
        s = st.project(st.read_events(hb), st.read_dag(hb))
        print(json.dumps(rv.resolve(s, st.read_dag(hb), hb)))
    elif args.cmd == "exec":
        from . import executor
        if args.action == "config":                # mirror the plugin's `hb-exec.js config`
            print(json.dumps(executor.config(hb), indent=2))
            return 0
        if args.action != "run":
            sys.stderr.write("usage: hb exec [run|config] [--parallel N]\n")
            return 2
        if args.parallel:
            os.environ["HB_MAX_CONCURRENCY"] = str(args.parallel)
        return executor.run(hb)
    elif args.cmd == "mcp-serve":
        from . import mcp_server
        if args.http:
            return mcp_server.serve_http(hb, args.host, args.port, args.allow_remote)
        return mcp_server.serve(hb)
    elif args.cmd == "bench":
        from . import bench
        if not args.backend:
            sys.stderr.write("usage: hb bench --backend <name|label=cmd> [--backend ...] [--dir <project>]\n")
            return 2
        cards = bench.run(hb, args.backend)
        regr = bench.regressions(cards, args.baseline) if args.baseline else None
        if args.json:
            if regr is not None:
                print(json.dumps({"scorecards": bench.build(cards), "regressions": regr}, indent=2))
            else:
                print(json.dumps(bench.build(cards), indent=2))   # backward-compatible: a plain list of cards
        else:
            print(bench.render(cards))
            if regr is not None:
                print()
                print("regression vs baseline '%s':" % args.baseline)
                for r in regr:
                    print("  %-16s %s (gates %+d, phases %+d, fails %+d)" % (
                        r["candidate"], "REGRESSED" if r["regressed"] else "ok",
                        r["deltas"]["gate_passed"], r["deltas"]["phases_done"],
                        r["deltas"]["task_failures"]))
    elif args.cmd == "reward":
        from . import bench
        recs = bench.rewards(hb)
        if args.json:
            print(json.dumps(recs, indent=2))
        else:
            for r in recs:
                print(json.dumps(r))
    return 0


if __name__ == "__main__":
    sys.exit(main())
