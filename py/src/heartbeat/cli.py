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
    p = sub.add_parser("audit"); p.add_argument("dagfile", nargs="?"); p.add_argument("--json", action="store_true"); p.add_argument("--agent", action="store_true"); _add_dir(p)
    p = sub.add_parser("report"); p.add_argument("--json", action="store_true"); _add_dir(p)
    p = sub.add_parser("doctor"); _add_dir(p)
    p = sub.add_parser("diagnose"); p.add_argument("reason", nargs="?"); _add_dir(p)
    p = sub.add_parser("protocol"); p.add_argument("reason", nargs="?"); p.add_argument("--md", action="store_true")
    p = sub.add_parser("state"); _add_dir(p)
    p = sub.add_parser("rebuild"); _add_dir(p)
    for name in ("start", "done", "fail", "heartbeat"):
        p = sub.add_parser(name); p.add_argument("task"); p.add_argument("reason", nargs="*"); _add_dir(p)
    p = sub.add_parser("review"); p.add_argument("gate"); p.add_argument("verdict", choices=["pass", "fail"]); p.add_argument("note", nargs="*"); _add_dir(p)
    p = sub.add_parser("ready"); p.add_argument("n", nargs="?", type=int, default=0); _add_dir(p)
    p = sub.add_parser("next"); _add_dir(p)
    p = sub.add_parser("exec"); p.add_argument("action", nargs="?", default="run"); p.add_argument("--parallel", type=int, default=0); _add_dir(p)

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
        ev = {"event": "review_passed" if args.verdict == "pass" else "review_failed", "gate": args.gate}
        if args.note:
            ev["note"] = " ".join(args.note)
        st.mutate(hb, ev); print(f"review {args.verdict} {args.gate}")
    elif args.cmd == "ready":
        s = st.project(st.read_events(hb), st.read_dag(hb))
        print(json.dumps(rv.ready_tasks(s, st.read_dag(hb), hb, args.n)))
    elif args.cmd == "next":
        s = st.project(st.read_events(hb), st.read_dag(hb))
        print(json.dumps(rv.resolve(s, st.read_dag(hb), hb)))
    elif args.cmd == "exec":
        from . import executor
        if args.parallel:
            os.environ["HB_MAX_CONCURRENCY"] = str(args.parallel)
        return executor.run(hb)
    return 0


if __name__ == "__main__":
    sys.exit(main())
