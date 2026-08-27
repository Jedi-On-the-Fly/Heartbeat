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
    p = sub.add_parser("review"); p.add_argument("gate"); p.add_argument("verdict", choices=["pass", "fail"]); p.add_argument("note", nargs="*"); p.add_argument("--artifact"); _add_dir(p)
    p = sub.add_parser("evidence"); p.add_argument("gate"); _add_dir(p)
    p = sub.add_parser("ready"); p.add_argument("n", nargs="?", type=int, default=0); _add_dir(p)
    p = sub.add_parser("refuters"); _add_dir(p)
    p = sub.add_parser("refute-prompt"); p.add_argument("gate"); _add_dir(p)
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
            r = gatemod.run_all(hb)
            print("✅ ALL GATES PASS" if r["ok"] else "❌ some gates would block")
            return 0 if r["ok"] else 1
        if not args.gate:
            sys.stderr.write("usage: hb gate <GATE> [--check]\n"); return 2
        res = gatemod.run_gate(hb, args.gate, check=args.check)
        for ln in res.get("lines", []):
            print(ln)
        print(f"gate {args.gate}: {res['status']}")
        return 0 if res["status"] in ("passed", "review_pending", "would_pass") else 1
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
                                                   artifact=args.artifact, note=args.note)
        if out:
            print(out)
        if err:
            sys.stderr.write(err + "\n")
        return rc
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
    elif args.cmd == "refuters":
        # Discovery: refuter profiles available to this project (.hb/refuters/ — shipped ones seeded
        # by bootstrap + any project-authored). Sorted names, one per line — node ≡ python.
        dref = os.path.join(str(hb), "refuters")
        names = sorted(f[:-5] for f in os.listdir(dref) if f.endswith(".json")) if os.path.isdir(dref) else []
        for n in names:
            print(n)
    elif args.cmd == "refute-prompt":
        from . import refuter_profiles as rp
        try:
            sys.stdout.write(rp.compose_prompt(str(hb), st.read_dag(hb), args.gate) + "\n")
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
