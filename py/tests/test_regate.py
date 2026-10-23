"""regate (RG1): declare + the fail-closed perimeter — python-side spec (spec-first RED).

A gate whose premises died is revised through `hb regate`, never by hand. While a regate is
pending, every evaluation/acceptance path refuses fail-closed at the CHOKEPOINTS:
gate.eval_gate (so run/check/all AND diagnose can never execute the criteria),
review_policy.accept_review (all three verdicts — the CLI, the MCP review tool and the
executor all route through it), constraints.record, the tick (sleeps regate_pending_waiting),
and the executor (escalates; never appends a review_* event while pending — through refuse()
OR the unconstrained refuted-branch — and never busy-loops).

The bash twin (tests/regate-fail-closed.sh) drives the node runtime and the cross-runtime
fixtures; this file is the python mirror plus the executor seams the bash proof reaches only
via pytest (the gate-path monkeypatched tick; the constrained refuse() guard).
"""
import json
import os

import pytest

from conftest import make_hb


def run_cli(argv):
    from heartbeat import cli
    try:
        return cli.main(list(argv)) or 0
    except SystemExit as e:  # argparse errors and die()-style exits
        return e.code if isinstance(e.code, int) else 1


def regate_dag(tmp_path):
    """A (side-effect gate: eval is observable), B (constrained review), C (no gate_exit)."""
    flag = tmp_path / "executed.flag"
    return {
        "phases": [
            {"id": "A", "title": "side-effect gate", "gate_entry": None, "gate_exit": "GATE_A",
             "tasks": [{"id": "a1", "title": "a", "requires": []}]},
            {"id": "B", "title": "reviewed", "gate_entry": "GATE_A", "gate_exit": "GATE_B",
             "tasks": [{"id": "b1", "title": "b", "requires": []}]},
            {"id": "C", "title": "gateless", "gate_entry": None, "gate_exit": None,
             "tasks": [{"id": "c1", "title": "c", "requires": []}]},
        ],
        "gates": {
            "GATE_A": {"desc": "observable eval", "criteria": [
                {"id": "ga1", "desc": "touch the flag", "cmd": "touch '%s'" % flag}]},
            "GATE_B": {"desc": "reviewed gate",
                       "review": {"prompt": "Refute that B is done.",
                                  "constraints": [{"id": "P1", "claim": "b1 did real work",
                                                   "subjects": ["m.txt"], "violation": "m.txt absent"}]},
                       "criteria": [{"id": "gb1", "desc": "behavioral", "cmd": "python3 -c 'assert True'"}]},
        },
    }


def events(hb):
    return [json.loads(l) for l in (hb / "events.jsonl").read_text().splitlines() if l.strip()]


def ev_names(hb):
    return [e.get("event") for e in events(hb)]


def marker(hb, gate="GATE_A"):
    return (json.loads((hb / "dag.json").read_text())["gates"].get(gate) or {}).get("regate")


def declare(hb, target="GATE_A", reason="premises died: volumes replaced", actor="alice", monkeypatch=None):
    assert monkeypatch is not None
    monkeypatch.setenv("HB_ACTOR", actor)
    return run_cli(["regate", target, "--reason", reason, "--dir", str(hb)])


# ── declare ───────────────────────────────────────────────────────────────────

def test_regate_declare_marker_event_and_projection(tmp_path, monkeypatch):
    hb = make_hb(tmp_path, regate_dag(tmp_path))
    from heartbeat import state as st
    dag = json.loads((hb / "dag.json").read_text())
    before = st.project(events(hb), dag)
    orig = dag["gates"]["GATE_A"]["criteria"]
    assert declare(hb, monkeypatch=monkeypatch) == 0
    m = marker(hb)
    assert m and m["pending"] is True
    assert m["reason"] == "premises died: volumes replaced"
    assert m["actor"] == "alice"
    assert isinstance(m.get("at"), str)
    assert m["prev_criteria"] == orig, "prev_criteria must snapshot the criteria at declare time"
    assert ev_names(hb).count("gate_regated") == 1
    after = st.project(events(hb), json.loads((hb / "dag.json").read_text()))
    for k in ("current_phase", "active_tasks", "completed_tasks", "completed_phases",
              "pending_reviews", "build_stuck_count", "gate"):
        assert before[k] == after[k], "gate_regated must be audit-only (projection changed: %s)" % k


def test_regate_declare_phase_id_resolves_to_gate(tmp_path, monkeypatch):
    hb = make_hb(tmp_path, regate_dag(tmp_path))
    assert declare(hb, target="B", monkeypatch=monkeypatch) == 0
    assert marker(hb, "GATE_B")["pending"] is True


def test_regate_declare_refusals(tmp_path, monkeypatch):
    hb = make_hb(tmp_path, regate_dag(tmp_path))
    monkeypatch.setenv("HB_ACTOR", "alice")
    assert run_cli(["regate", "GATE_A", "--reason", "", "--dir", str(hb)]) != 0, "empty reason accepted"
    monkeypatch.delenv("HB_ACTOR")
    assert run_cli(["regate", "GATE_A", "--reason", "x", "--dir", str(hb)]) != 0, "unset HB_ACTOR accepted"
    monkeypatch.setenv("HB_ACTOR", "unknown")
    assert run_cli(["regate", "GATE_A", "--reason", "x", "--dir", str(hb)]) != 0, "HB_ACTOR=unknown accepted"
    monkeypatch.setenv("HB_ACTOR", "alice")
    assert run_cli(["regate", "NOPE", "--reason", "x", "--dir", str(hb)]) != 0, "unknown id accepted"
    assert run_cli(["regate", "C", "--reason", "x", "--dir", str(hb)]) != 0, "phase with no gate_exit accepted"
    assert marker(hb) is None and "gate_regated" not in ev_names(hb), "a refused declare left traces"
    assert declare(hb, monkeypatch=monkeypatch) == 0
    assert declare(hb, reason="again", actor="bob", monkeypatch=monkeypatch) != 0, "second declare accepted"
    assert marker(hb)["actor"] == "alice", "a refused second declare overwrote the snapshot"


# ── perimeter: eval_gate is the chokepoint ────────────────────────────────────

def test_regate_eval_gate_refuses_fail_closed(tmp_path, monkeypatch):
    hb = make_hb(tmp_path, regate_dag(tmp_path))
    declare(hb, monkeypatch=monkeypatch)
    rc = run_cli(["gate", "GATE_A", "--dir", str(hb)])
    assert rc == 3, "hb gate refusal must exit with the DISTINCT code 3 (got %r)" % rc
    assert run_cli(["gate", "GATE_A", "--check", "--dir", str(hb)]) == 3
    assert not (tmp_path / "executed.flag").exists(), "a pending-regate gate's criteria were EXECUTED"
    assert not any(n in ("gate_passed", "gate_failed") for n in ev_names(hb)), "a refusal appended a gate event"


def test_regate_gate_all_counts_failing_even_never_passed(tmp_path, monkeypatch):
    hb = make_hb(tmp_path, regate_dag(tmp_path))
    declare(hb, monkeypatch=monkeypatch)   # GATE_A never passed: the planned-skip hole
    assert run_cli(["gate", "--all", "--dir", str(hb)]) != 0, "--all said ALL GREEN over a never-passed pending regate"


def test_regate_diagnose_does_not_execute_criteria(tmp_path, monkeypatch):
    hb = make_hb(tmp_path, regate_dag(tmp_path))
    declare(hb, monkeypatch=monkeypatch)
    from heartbeat import doctor
    doctor.diagnose(str(hb))            # inference path
    doctor.diagnose(str(hb), "gate_blocked")
    assert not (tmp_path / "executed.flag").exists(), "diagnose EXECUTED a pending-regate gate's criteria"


# ── perimeter: acceptance chokepoints ─────────────────────────────────────────

def review_owed_fixture(tmp_path, monkeypatch, dag=None, declare_now=True):
    """Everything done, GATE_B det-passed (provenanced), ONLY its review owed — then (optionally)
    a regate declared. The complete history matters: an executor driven on this fixture must land
    in the review_pending branch, not on some earlier task."""
    d = dag or regate_dag(tmp_path)
    hb = make_hb(tmp_path, d, events=[
        {"event": "task_done", "task": "a1", "actor": "doer"},
        {"event": "gate_passed", "gate": "GATE_A", "pass": 1, "fail": 0, "runtime": "python",
         "criteria": [{"id": "ga1", "cmd": "true", "exit": 0}]},
        {"event": "task_done", "task": "b1", "actor": "doer"},
        {"event": "task_done", "task": "c1", "actor": "doer"},
        {"event": "gate_passed", "gate": "GATE_B", "pass": 1, "fail": 0, "runtime": "python",
         "criteria": [{"id": "gb1", "cmd": "python3 -c 'assert True'", "exit": 0}]},
    ])
    (tmp_path / "findings.md").write_text(
        "I tried to refute GATE_B / phase B (task b1): ran the criteria, found nothing broken.\nHOLES: none\n")
    if declare_now:
        declare(hb, target="GATE_B", monkeypatch=monkeypatch)
    return hb


def test_regate_accept_review_refuses_all_verdicts(tmp_path, monkeypatch):
    hb = review_owed_fixture(tmp_path, monkeypatch)
    from heartbeat import review_policy
    monkeypatch.setenv("HB_ACTOR", "reviewer")
    for verdict in ("pass", "fail", "free"):
        rc, out, err = review_policy.accept_review(hb, "GATE_B", verdict, artifact="findings.md")
        assert rc != 0, "accept_review %s succeeded while a regate is pending" % verdict
        assert "regate" in (out + err).lower(), "accept_review %s refusal is silent about the regate" % verdict
    assert not any(n in ("review_passed", "review_failed", "free_review_recorded") for n in ev_names(hb)), \
        "a refused verdict appended a review event"


def test_regate_constraints_record_refused(tmp_path, monkeypatch, capsys):
    hb = review_owed_fixture(tmp_path, monkeypatch)
    (tmp_path / "g.json").write_text(json.dumps(
        [{"id": "G1", "claim": "x behaves", "subjects": ["m.txt"], "violation": "it does not"}]))
    (tmp_path / "m.txt").write_text("x")
    monkeypatch.setenv("HB_ACTOR", "author")
    assert run_cli(["constraints", "GATE_B", "--record", str(tmp_path / "g.json"), "--dir", str(hb)]) != 0, \
        "constraints --record accepted while a regate is pending"
    assert "regate" in capsys.readouterr().err.lower(), \
        "the refusal is not the regate one (a grounding/cycle miss would mask a stripped guard)"
    assert "constraints_recorded" not in ev_names(hb)


def test_regate_malformed_marker_fails_closed(tmp_path, monkeypatch):
    """[]/{}/'yes' as the regate value must REFUSE evaluation and acceptance on this runtime —
    the two runtimes' truthiness rules disagree on empty containers (a refuter catch), so the
    predicate is strict: only a well-formed dict with pending exactly False clears."""
    from heartbeat import review_policy
    for junk in ([], {}, "yes"):
        sub = tmp_path / ("m-%s" % type(junk).__name__)
        sub.mkdir()
        hb = make_hb(sub, regate_dag(sub))
        d = json.loads((hb / "dag.json").read_text())
        d["gates"]["GATE_A"]["regate"] = junk
        (hb / "dag.json").write_text(json.dumps(d))
        assert run_cli(["gate", "GATE_A", "--dir", str(hb)]) == 3, \
            "evaluation ran under a malformed regate marker (%r)" % (junk,)
        assert not (sub / "executed.flag").exists(), "criteria executed under a malformed marker (%r)" % (junk,)
        monkeypatch.setenv("HB_ACTOR", "reviewer")
        rc, out, err = review_policy.accept_review(hb, "GATE_A", "fail", note="x")
        assert rc != 0 and "regate" in (out + err).lower(), \
            "accept_review accepted a verdict under a malformed marker (%r)" % (junk,)


def test_regate_phase_id_does_not_bypass_review_guard(tmp_path, monkeypatch):
    hb = review_owed_fixture(tmp_path, monkeypatch)
    from heartbeat import review_policy
    monkeypatch.setenv("HB_ACTOR", "reviewer")
    rc, out, err = review_policy.accept_review(hb, "B", "fail", note="via the phase id")
    assert rc != 0, "a review verdict recorded via the PHASE id bypassed the regate guard"
    assert "regate" in (out + err).lower()
    assert "review_failed" not in ev_names(hb)


# ── unattended: tick sleeps, executor escalates ───────────────────────────────

def test_regate_tick_sleeps_both_states(tmp_path, monkeypatch):
    from heartbeat import tick as tickmod
    # gate_pending state
    (tmp_path / "g").mkdir()
    hb = make_hb(tmp_path / "g", regate_dag(tmp_path / "g"),
                 events=[{"event": "task_done", "task": "a1", "actor": "doer"}])
    declare(hb, monkeypatch=monkeypatch)
    out = tickmod.tick(str(hb))
    assert out.get("wakeAgent") is False and (out.get("data") or {}).get("reason") == "regate_pending_waiting", \
        "tick must sleep regate_pending_waiting over a pending regate (gate_pending state), got %r" % (out,)
    # review_pending state
    (tmp_path / "r").mkdir()
    hb2 = review_owed_fixture(tmp_path / "r", monkeypatch)
    out = tickmod.tick(str(hb2))
    assert out.get("wakeAgent") is False and (out.get("data") or {}).get("reason") == "regate_pending_waiting", \
        "tick must sleep regate_pending_waiting from the review_pending state too, got %r" % (out,)


def bounded_tick(monkeypatch, limit=6):
    """Wrap the real tick so a mis-implemented executor loop cannot hang pytest."""
    from heartbeat import executor, tick as tickmod
    real, calls = tickmod.tick, {"n": 0}

    def wrapped(hbdir):
        calls["n"] += 1
        if calls["n"] > limit:
            return {"wakeAgent": False, "data": {"reason": "no_pending_tasks"}}
        return real(hbdir)
    monkeypatch.setattr(executor.tickmod, "tick", wrapped)
    return calls


def test_regate_executor_idle_no_dispatch(tmp_path, monkeypatch, capsys):
    hb = review_owed_fixture(tmp_path, monkeypatch)
    from heartbeat import executor
    calls = []
    monkeypatch.setattr(executor, "dispatch",
                        lambda *a, **k: calls.append(a) or {"ok": True, "summary": "x"})
    bounded_tick(monkeypatch)
    executor.run(str(hb))
    assert calls == [], "the executor dispatched a backend over a pre-declared pending regate"
    assert not any(n.startswith("review") or n == "free_review_recorded" for n in ev_names(hb) if n)
    assert "regate_pending_waiting" in capsys.readouterr().out, \
        "the idle exit does not name the regate sleep reason (not loud)"


def test_regate_executor_refuse_guard(tmp_path, monkeypatch, capsys):
    """Mid-review race on a CONSTRAINED gate: the backend declares the regate mid-dispatch; the
    constrained review's refuse() must then escalate, NEVER st.mutate a review_failed."""
    hb = review_owed_fixture(tmp_path, monkeypatch, declare_now=False)
    (tmp_path / "m.txt").write_text("the raced work")   # grounds the fake author's G1 subject
    from heartbeat import executor
    raced = {"done": False}

    def racing_dispatch(cfg, mode, payload, hbdir, task_id, cwd=None, model=None, provider=None):
        if mode == "author":   # a well-formed set, recorded BEFORE the race declares
            return {"ok": True, "constraints": [{"id": "G1", "claim": "m.txt holds the raced work",
                                                 "subjects": ["m.txt"], "violation": "m.txt absent"}]}
        if mode != "refute":
            return {"ok": True, "summary": "x"}
        if not raced["done"]:
            raced["done"] = True
            monkeypatch.setenv("HB_ACTOR", "racer")
            assert run_cli(["regate", "GATE_B", "--reason", "mid-review premise death", "--dir", str(hb)]) == 0
        return {"refuted": True, "findings": "raced findings about GATE_B and b1 — forces refuse()"}
    monkeypatch.setattr(executor, "dispatch", racing_dispatch)
    bounded_tick(monkeypatch)
    executor.run(str(hb))
    assert raced["done"], "the race never ran — the executor never dispatched a refute"
    assert not any(n in ("review_passed", "review_failed", "free_review_recorded") for n in ev_names(hb)), \
        "the executor appended a review event while the gate's regate was pending (refuse() guard missing)"
    assert any("hb-exec" in ln.lower() and "regate" in ln.lower() for ln in capsys.readouterr().out.splitlines()), \
        "the executor did not escalate loudly about the regate (no HB-EXEC line names it)"


def test_regate_executor_unconstrained_refuted_branch_guard(tmp_path, monkeypatch, capsys):
    """Same race on an UNCONSTRAINED review gate: the refuted-branch direct st.mutate must hold."""
    dag = regate_dag(tmp_path)
    del dag["gates"]["GATE_B"]["review"]["constraints"]
    hb = review_owed_fixture(tmp_path, monkeypatch, dag=dag, declare_now=False)
    from heartbeat import executor
    raced = {"done": False}

    def racing_dispatch(cfg, mode, payload, hbdir, task_id, cwd=None, model=None, provider=None):
        if mode != "refute":
            return {"ok": True, "summary": "x"}
        if not raced["done"]:
            raced["done"] = True
            monkeypatch.setenv("HB_ACTOR", "racer")
            assert run_cli(["regate", "GATE_B", "--reason", "mid-review premise death", "--dir", str(hb)]) == 0
        return {"refuted": True, "findings": "raced findings about GATE_B and b1"}
    monkeypatch.setattr(executor, "dispatch", racing_dispatch)
    bounded_tick(monkeypatch)
    executor.run(str(hb))
    assert raced["done"], "the race never ran — the executor never dispatched a refute"
    assert "review_failed" not in ev_names(hb), \
        "the unconstrained refuted-branch st.mutate fired while the regate was pending"
    assert any("hb-exec" in ln.lower() and "regate" in ln.lower() for ln in capsys.readouterr().out.splitlines()), \
        "the executor did not escalate loudly about the regate (no HB-EXEC line names it)"


def test_regate_executor_gate_path_escalates(tmp_path, monkeypatch, capsys):
    """The gate-path signal: a (shimmed) gate_pending wake over a pending regate must reach the
    executor's escalation branch — bounded stop, no gate event, no dispatch of the gate itself."""
    hb = make_hb(tmp_path, regate_dag(tmp_path),
                 events=[{"event": "task_done", "task": "a1", "actor": "doer"}])
    from heartbeat import executor, tick as tickmod
    wake = tickmod.tick(str(hb))                      # genuine pre-declare gate_pending wake
    assert (wake.get("data") or {}).get("reason") == "gate_pending", "fixture is not gate_pending: %r" % (wake,)
    declare(hb, monkeypatch=monkeypatch)
    shim = {"fired": False}

    def one_shot(hbdir):
        if not shim["fired"]:
            shim["fired"] = True
            return wake
        return {"wakeAgent": False, "data": {"reason": "no_pending_tasks"}}
    monkeypatch.setattr(executor.tickmod, "tick", one_shot)
    monkeypatch.setattr(executor, "dispatch", lambda *a, **k: {"ok": True, "summary": "x"})
    executor.run(str(hb))
    assert shim["fired"]
    assert not (tmp_path / "executed.flag").exists(), "the executor's gate run EXECUTED a pending gate's criteria"
    assert not any(n in ("gate_passed", "gate_failed") for n in ev_names(hb)), \
        "the executor's refused gate run appended a gate event"
    assert any("hb-exec" in ln.lower() and "regate" in ln.lower() for ln in capsys.readouterr().out.splitlines()), \
        "the executor swallowed the gate-path refusal (no HB-EXEC escalation line names the regate)"


# ═══ RG2: rearm — evidence-gated re-grounding + stale-pass invalidation ═══════

def rearm_fixture(tmp_path, monkeypatch, declare_gate="GATE_B"):
    """Review-owed GATE_B (provenanced pass), declared, criteria revised, evidence on disk."""
    hb = review_owed_fixture(tmp_path, monkeypatch)   # declares GATE_B as alice
    d = json.loads((hb / "dag.json").read_text())
    d["gates"]["GATE_B"]["criteria"] = [{"id": "rev1", "desc": "revised", "cmd": "python3 -c 'assert 2+2==4'"}]
    (hb / "dag.json").write_text(json.dumps(d))
    (tmp_path / "m.txt").write_text("the real work of b1")
    (tmp_path / "evidence.md").write_text(
        "Rearm evidence for GATE_B (task b1): the volume premise died; the revised criterion was run by hand.")
    return hb


def rearm(hb, actor="bob", artifact="evidence.md", model=None, monkeypatch=None):
    monkeypatch.setenv("HB_ACTOR", actor)
    argv = ["regate", "GATE_B", "--rearm", "--artifact", artifact, "--dir", str(hb)]
    if model:
        argv += ["--model", model]
    return run_cli(argv)


def test_regate_rearm_refusal_matrix(tmp_path, monkeypatch, capsys):
    hb = rearm_fixture(tmp_path, monkeypatch)
    assert rearm(hb, actor="ALICE", monkeypatch=monkeypatch) != 0, "the declarer rearmed their own revision (case-varied)"
    assert "different" in capsys.readouterr().err.lower()
    (tmp_path / "thin.md").write_text("too thin")
    assert rearm(hb, artifact="thin.md", monkeypatch=monkeypatch) != 0, "a thin artifact was accepted"
    (tmp_path / "filler.md").write_text("Fifty characters of generic filler that references nothing real at all.")
    assert rearm(hb, artifact="filler.md", monkeypatch=monkeypatch) != 0, "an artifact citing nothing was accepted"
    assert rearm(hb, artifact="missing.md", monkeypatch=monkeypatch) != 0, "a missing artifact was accepted"
    d = json.loads((hb / "dag.json").read_text())
    d["gates"]["GATE_B"]["criteria"] = [{"id": "h1", "desc": "hollow", "cmd": "true"}]
    (hb / "dag.json").write_text(json.dumps(d))
    capsys.readouterr()
    assert rearm(hb, monkeypatch=monkeypatch) != 0, "a HOLLOW revision was rearmed"
    assert "audit" in capsys.readouterr().err.lower()
    m = marker(hb, "GATE_B")
    assert m["pending"] is True and "rearm" not in m, "a refused rearm touched the record"
    assert "gate_rearmed" not in ev_names(hb)
    # no pending regate at all
    hb2 = review_owed_fixture(tmp_path / "np", monkeypatch, declare_now=False) if (tmp_path / "np").mkdir() is None else None
    (tmp_path / "np" / "evidence.md").write_text("Rearm evidence for GATE_B (task b1): premise died, long enough.")
    monkeypatch.setenv("HB_ACTOR", "bob")
    assert run_cli(["regate", "GATE_B", "--rearm", "--artifact", "evidence.md", "--dir", str(hb2)]) != 0, \
        "rearm with NO pending regate accepted"


def test_regate_rearm_success_provenance(tmp_path, monkeypatch):
    import hashlib
    hb = rearm_fixture(tmp_path, monkeypatch)
    assert rearm(hb, model="sonnet", monkeypatch=monkeypatch) == 0
    m = marker(hb, "GATE_B")
    assert m["pending"] is False
    assert m["rearm"]["actor"] == "bob" and m["rearm"]["model"] == "sonnet"
    assert m["rearm"]["artifact"] == "reviews/GATE_B.regate.md"
    stored = (hb / "reviews" / "GATE_B.regate.md").read_bytes()
    assert stored == (tmp_path / "evidence.md").read_bytes()
    ev = [e for e in events(hb) if e.get("event") == "gate_rearmed"]
    assert len(ev) == 1 and ev[0]["sha256"] == hashlib.sha256(stored).hexdigest() == m["rearm"]["sha256"]
    assert run_cli(["gate", "GATE_B", "--dir", str(hb)]) == 0, "the rearmed gate did not evaluate"


def test_regate_stale_pass_rule_and_synthetic_import(tmp_path, monkeypatch):
    hb = rearm_fixture(tmp_path, monkeypatch)
    assert rearm(hb, monkeypatch=monkeypatch) == 0
    from heartbeat import review_policy
    monkeypatch.setenv("HB_ACTOR", "rev")
    (tmp_path / "findings.md").write_text(
        "I tried to refute GATE_B (task b1): probed the revised criterion.\nHOLES: none\n")
    for v in ("pass", "fail", "free"):
        rc, out, err = review_policy.accept_review(hb, "GATE_B", v, artifact="findings.md")
        assert rc != 0, "review %s accepted over a STALE pre-rearm pass" % v
        assert any(w in (out + err).lower() for w in ("stale", "fresh pass", "re-run")), (out, err)
    # a bare synthetic pass (what hb import writes) must NOT unlock
    with open(hb / "events.jsonl", "a") as f:
        f.write(json.dumps({"event": "gate_passed", "gate": "GATE_B"}) + "\n")
    rc, out, err = review_policy.accept_review(hb, "GATE_B", "fail", note="x")
    assert rc != 0, "a synthetic unprovenanced pass unlocked the verdicts"
    # a PROVENANCED fresh pass unlocks
    assert run_cli(["gate", "GATE_B", "--dir", str(hb)]) == 0
    rc, out, err = review_policy.accept_review(hb, "GATE_B", "fail", note="a finding after the fresh pass")
    assert rc == 0, "a verdict after a fresh provenanced pass was refused: %s" % err
    assert "review_failed" in ev_names(hb)


def test_regate_cycle_start_boundary(tmp_path, monkeypatch):
    from heartbeat import constraints as cons, state as stt
    hb = review_owed_fixture(tmp_path, monkeypatch, declare_now=False)
    (tmp_path / "m.txt").write_text("the real work of b1")
    (tmp_path / "g.json").write_text(json.dumps(
        [{"id": "G1", "claim": "m.txt holds b1 work", "subjects": ["m.txt"], "violation": "absent"}]))
    monkeypatch.setenv("HB_ACTOR", "author")
    assert run_cli(["constraints", "GATE_B", "--record", str(tmp_path / "g.json"), "--dir", str(hb)]) == 0
    declare(hb, target="GATE_B", monkeypatch=monkeypatch)
    d = json.loads((hb / "dag.json").read_text())
    d["gates"]["GATE_B"]["criteria"] = [{"id": "rev1", "desc": "revised", "cmd": "python3 -c 'assert 1'"}]
    (hb / "dag.json").write_text(json.dumps(d))
    (tmp_path / "evidence.md").write_text("Rearm evidence for GATE_B (task b1): premise died; criterion re-run.")
    assert rearm(hb, monkeypatch=monkeypatch) == 0
    assert run_cli(["gate", "GATE_B", "--dir", str(hb)]) == 0   # fresh pass
    dag = stt.read_dag(hb)
    pending, recorded, _ev, start = cons.review_cycle_full(str(hb), dag, "GATE_B")
    assert pending and not recorded, "the pre-declare constraint set survived the rearm"
    _p2, r2, _e2 = cons.review_cycle(str(hb), dag, "GATE_B")
    assert r2 == recorded, "review_cycle and review_cycle_full disagree (two start computations)"
    monkeypatch.setenv("HB_ACTOR", "author2")
    assert run_cli(["constraints", "GATE_B", "--record", str(tmp_path / "g.json"), "--dir", str(hb)]) == 0, \
        "a fresh set was not recordable after the rearm (write-once must apply afresh)"


def test_regate_executor_stale_resume(tmp_path, monkeypatch, capsys):
    hb = rearm_fixture(tmp_path, monkeypatch)
    assert rearm(hb, monkeypatch=monkeypatch) == 0
    from heartbeat import executor
    calls = []
    monkeypatch.setattr(executor, "dispatch", lambda *a, **k: calls.append(a) or {"refuted": False, "findings": "x" * 60})
    bounded_tick(monkeypatch)
    executor.run(str(hb))
    assert calls == [], "the executor dispatched a refuter over a STALE pre-rearm pass"
    assert not any(n in ("review_passed", "review_failed", "free_review_recorded") for n in ev_names(hb))
    out = capsys.readouterr().out
    assert any("hb-exec" in ln.lower() and ("stale" in ln.lower() or "re-run" in ln.lower() or "revised" in ln.lower())
               for ln in out.splitlines()), "no loud stale-window escalation: %r" % out


def test_regate_doctor_rearm_states(tmp_path, monkeypatch):
    from heartbeat import doctor as doc
    hb = rearm_fixture(tmp_path, monkeypatch)
    # pending → NOTE
    r = doc.doctor(str(hb))
    assert any("regate" in n.lower() for n in r["notes"]), "no pending-regate note"
    assert not any("regate" in p.lower() for p in r["problems"]), "a pending regate alone must not be a problem"
    # rearm → artifact rot is a PROBLEM
    assert rearm(hb, monkeypatch=monkeypatch) == 0
    art = hb / "reviews" / "GATE_B.regate.md"
    good = art.read_bytes()
    art.unlink()
    assert any("regate" in p.lower() for p in doc.doctor(str(hb))["problems"]), "missing rearm artifact not flagged"
    art.write_bytes(good + b"x")
    assert any("regate" in p.lower() for p in doc.doctor(str(hb))["problems"]), "byte-changed rearm artifact not flagged"
    art.write_bytes(good)
    assert not any("regate" in p.lower() for p in doc.doctor(str(hb))["problems"])
    # marker cross-check: the log attests a PENDING regate (gate_regated unanswered), the dag lost
    # the marker (e.g. restored from backup) — a problem on a fresh fixture, since a rearm ANSWERS
    # the declare and ends the divergence window
    (tmp_path / "sync").mkdir()
    hb2 = review_owed_fixture(tmp_path / "sync", monkeypatch)   # declares GATE_B (pending)
    d = json.loads((hb2 / "dag.json").read_text())
    d["gates"]["GATE_B"].pop("regate", None)
    (hb2 / "dag.json").write_text(json.dumps(d))
    assert any("regate" in p.lower() for p in doc.doctor(str(hb2))["problems"]), \
        "a log-attested pending regate with no dag marker is not a problem"


def test_regate_hand_cleared_marker_cannot_launder(tmp_path, monkeypatch):
    """The exploit a refuter reproduced: setting regate.pending=false by hand skipped the whole
    rearm bar. The log is truth — an UNANSWERED gate_regated closes the verdict window whatever
    the marker says, and doctor flags the cleared marker."""
    hb = rearm_fixture(tmp_path, monkeypatch)   # declared; criteria revised
    d = json.loads((hb / "dag.json").read_text())
    d["gates"]["GATE_B"]["regate"]["pending"] = False   # the hand edit
    (hb / "dag.json").write_text(json.dumps(d))
    assert run_cli(["gate", "GATE_B", "--dir", str(hb)]) == 0   # eval re-enabled — acceptance must still refuse
    from heartbeat import review_policy, doctor as doc
    monkeypatch.setenv("HB_ACTOR", "rev")
    (tmp_path / "findings.md").write_text(
        "I tried to refute GATE_B (task b1): probed the revised criterion.\nHOLES: none\n")
    for v in ("pass", "fail"):
        rc, out, err = review_policy.accept_review(hb, "GATE_B", v, artifact="findings.md")
        assert rc != 0, "review %s ACCEPTED over a hand-cleared marker (the exploit)" % v
        assert "unanswered" in (out + err).lower()
    assert not any(n in ("review_passed", "review_failed") for n in ev_names(hb))
    assert any("cleared marker" in p.lower() or "fabricated" in p.lower()
               for p in doc.doctor(str(hb))["problems"]), "doctor silent over the hand-cleared marker"


def test_regate_executor_writers_hold_in_stale_window(tmp_path, monkeypatch, capsys):
    """A mid-dispatch declare+rearm pair leaves pending=false but a stale window — the executor's
    direct review_failed writer must still refuse (the log is truth, not the marker)."""
    dag = regate_dag(tmp_path)
    del dag["gates"]["GATE_B"]["review"]["constraints"]
    hb = review_owed_fixture(tmp_path, monkeypatch, dag=dag, declare_now=False)
    (tmp_path / "evidence.md").write_text(
        "Rearm evidence for GATE_B (task b1): the volume premise died; criterion re-run by hand.")
    from heartbeat import executor
    raced = {"done": False}

    def racing_dispatch(cfg, mode, payload, hbdir, task_id, cwd=None, model=None, provider=None):
        if mode != "refute":
            return {"ok": True, "summary": "x"}
        if not raced["done"]:
            raced["done"] = True
            monkeypatch.setenv("HB_ACTOR", "racer")
            assert run_cli(["regate", "GATE_B", "--reason", "mid-dispatch death", "--dir", str(hb)]) == 0
            d2 = json.loads((hb / "dag.json").read_text())
            d2["gates"]["GATE_B"]["criteria"] = [{"id": "rev1", "desc": "revised", "cmd": "python3 -c 'assert 1'"}]
            (hb / "dag.json").write_text(json.dumps(d2))
            monkeypatch.setenv("HB_ACTOR", "racer2")
            assert run_cli(["regate", "GATE_B", "--rearm", "--artifact", "evidence.md", "--dir", str(hb)]) == 0
        return {"refuted": True, "findings": "raced findings about GATE_B and b1 after a mid-dispatch rearm"}
    monkeypatch.setattr(executor, "dispatch", racing_dispatch)
    bounded_tick(monkeypatch)
    executor.run(str(hb))
    assert raced["done"], "the race never ran"
    assert "review_failed" not in ev_names(hb), \
        "the executor landed a verdict in the stale window (pending=false but no fresh pass)"
    assert any("hb-exec" in ln.lower() and ("stale" in ln.lower() or "regate" in ln.lower())
               for ln in capsys.readouterr().out.splitlines())
