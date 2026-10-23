"""detach/reattach (DT1): retract a dependency claim — python-side spec (spec-first RED).

The bash twin (tests/detach.sh) drives both runtimes and the cross-runtime fixtures; this file
is the pure-python mirror: declare/reattach semantics, the per-channel weasel warning (incl. the
refuted steady state and the cross-gate discriminator), the detach-time anchor as the changed()
base (never widening to _start, never lying on re-detach, stamp-mismatch = missing), and the
twin lint rules."""
import json

from conftest import make_hb


def run_cli(argv):
    from heartbeat import cli
    try:
        return cli.main(list(argv)) or 0
    except SystemExit as e:
        return e.code if isinstance(e.code, int) else 1


def detach_dag():
    return {
        "phases": [
            {"id": "P", "title": "predecessor", "gate_entry": None, "gate_exit": "GATE_P",
             "tasks": [{"id": "p1", "title": "p", "requires": []}]},
            {"id": "D", "title": "dependent", "gate_entry": "GATE_P", "gate_exit": "GATE_D",
             "tasks": [{"id": "d1", "title": "d", "requires": []}]},
            {"id": "X", "title": "independent", "gate_entry": None, "gate_exit": "GATE_X",
             "tasks": [{"id": "x1", "title": "x", "requires": []}]},
        ],
        "gates": {
            "GATE_P": {"desc": "p", "review": {"prompt": "Refute P."},
                       "criteria": [{"id": "gp1", "desc": "d", "cmd": "python3 -c 'assert 1'"}]},
            "GATE_D": {"desc": "d", "criteria": [{"id": "gd1", "desc": "d", "cmd": "python3 -c 'assert 1'"}]},
            "GATE_X": {"desc": "x", "criteria": [{"id": "gx1", "desc": "d", "cmd": "python3 -c 'assert 1'"}]},
        },
    }


def events(hb):
    return [json.loads(l) for l in (hb / "events.jsonl").read_text().splitlines() if l.strip()]


def phase(hb, pid):
    return next(p for p in json.loads((hb / "dag.json").read_text())["phases"] if p["id"] == pid)


def detach(hb, pid="D", reason="premises changed", actor="alice", monkeypatch=None):
    monkeypatch.setenv("HB_ACTOR", actor)
    return run_cli(["detach", pid, "--reason", reason, "--dir", str(hb)])


def test_detach_declare_fields_event_anchor(tmp_path, monkeypatch, capsys):
    hb = make_hb(tmp_path, detach_dag())
    monkeypatch.setenv("HB_ACTOR", "doer")
    assert run_cli(["start", "p1", "--dir", str(hb)]) == 0   # the _start anchor
    assert detach(hb, monkeypatch=monkeypatch) == 0
    out = capsys.readouterr().out
    assert out.splitlines()[-4:] and "detached D from GATE_P" in out.splitlines()[0] or "detached D from GATE_P" in out, out
    p = phase(hb, "D")
    assert p.get("gate_entry") is None
    assert p["detached_from"] == "GATE_P" and p["detached_by"] == "alice"
    assert p["detached_reason"] == "premises changed" and p["detached_at"]
    assert sum(1 for e in events(hb) if e.get("event") == "phase_detached") == 1
    a = json.loads((hb / "anchors" / "_detach_D.json").read_text())
    assert a.get("detached_at") == p["detached_at"], "the anchor must be stamped with the declare's detached_at"


def test_detach_refusal_ladder(tmp_path, monkeypatch):
    hb = make_hb(tmp_path, detach_dag())
    monkeypatch.setenv("HB_ACTOR", "alice")
    assert run_cli(["detach", "D", "--reason", "", "--dir", str(hb)]) != 0, "empty reason accepted"
    monkeypatch.delenv("HB_ACTOR")
    assert run_cli(["detach", "D", "--reason", "r", "--dir", str(hb)]) != 0, "unset HB_ACTOR accepted"
    monkeypatch.setenv("HB_ACTOR", "alice")
    assert run_cli(["detach", "NOPE", "--reason", "r", "--dir", str(hb)]) != 0, "unknown id accepted"
    assert run_cli(["detach", "X", "--reason", "r", "--dir", str(hb)]) != 0, "null-entry phase accepted"
    assert run_cli(["detach", "../evil", "--reason", "r", "--dir", str(hb)]) != 0, "unsafe id accepted"
    assert detach(hb, monkeypatch=monkeypatch) == 0
    assert detach(hb, reason="again", actor="bob", monkeypatch=monkeypatch) != 0, "already-detached accepted"
    assert phase(hb, "D")["detached_by"] == "alice", "a refused re-detach overwrote the record"
    # completed phase
    hb2 = make_hb(tmp_path / "c", detach_dag(), events=[
        {"event": "gate_passed", "gate": "GATE_P", "pass": 1, "fail": 0, "runtime": "python",
         "criteria": [{"id": "gp1", "cmd": "x", "exit": 0}]},
        {"event": "review_passed", "gate": "GATE_P", "artifact": "reviews/GATE_P.md"},
        {"event": "gate_passed", "gate": "GATE_D", "pass": 1, "fail": 0, "runtime": "python",
         "criteria": [{"id": "gd1", "cmd": "x", "exit": 0}]},
    ]) if (tmp_path / "c").mkdir() is None else None
    assert run_cli(["detach", "D", "--reason", "r", "--dir", str(hb2)]) != 0, "a COMPLETED phase was detached"


def test_reattach_restores_and_refuses_brick(tmp_path, monkeypatch):
    hb = make_hb(tmp_path, detach_dag())
    assert detach(hb, monkeypatch=monkeypatch) == 0
    assert run_cli(["reattach", "D", "--dir", str(hb)]) == 0
    p = phase(hb, "D")
    assert p.get("gate_entry") == "GATE_P"
    assert all(k not in p for k in ("detached_from", "detached_reason", "detached_by", "detached_at"))
    assert sum(1 for e in events(hb) if e.get("event") == "phase_reattached") == 1
    assert run_cli(["reattach", "D", "--dir", str(hb)]) != 0, "reattach accepted on a non-detached phase"
    # the resolver brick: detached_from defined but no phase's gate_exit
    assert detach(hb, actor="bob", monkeypatch=monkeypatch) == 0
    d = json.loads((hb / "dag.json").read_text())
    nxt = next(x for x in d["phases"] if x["id"] == "P")
    nxt["gate_exit"] = "GATE_P2"
    d["gates"]["GATE_P2"] = d["gates"]["GATE_P"]
    (hb / "dag.json").write_text(json.dumps(d))
    assert run_cli(["reattach", "D", "--dir", str(hb)]) != 0, \
        "reattach restored a gate that is no phase's gate_exit (the resolver brick)"


def test_detach_warning_per_channel(tmp_path, monkeypatch, capsys):
    """The refuted STEADY STATE (review_failed → gate re-run det-passed, review owed) must warn;
    live failures on a DIFFERENT gate must not (the cross-gate discriminator)."""
    (tmp_path / "s").mkdir()
    hb = make_hb(tmp_path / "s", detach_dag(), events=[
        {"event": "gate_passed", "gate": "GATE_P", "pass": 1, "fail": 0, "runtime": "python",
         "criteria": [{"id": "gp1", "cmd": "x", "exit": 0}]},
        {"event": "review_failed", "gate": "GATE_P", "note": "a hole"},
        {"event": "gate_passed", "gate": "GATE_P", "pass": 1, "fail": 0, "runtime": "python",
         "criteria": [{"id": "gp1", "cmd": "x", "exit": 0}]},
    ])
    assert detach(hb, monkeypatch=monkeypatch) == 0
    assert "removed, not satisfied" in capsys.readouterr().out.lower(), \
        "the refuted steady state detached silently (merged-stream predicate)"
    # discriminator: only ANOTHER gate's channels are live → clean
    (tmp_path / "d").mkdir()
    hb2 = make_hb(tmp_path / "d", detach_dag(), events=[
        {"event": "gate_failed", "gate": "GATE_X", "pass": 0, "fail": 1},
        {"event": "review_failed", "gate": "GATE_X", "note": "other gate"},
    ])
    assert detach(hb2, monkeypatch=monkeypatch) == 0
    assert "removed, not satisfied" not in capsys.readouterr().out.lower(), \
        "warned on a clean detach because a DIFFERENT gate's channel is live (unfiltered scan)"
    # healed: gate_failed then gate_passed, review then accepted → clean
    (tmp_path / "h").mkdir()
    hb3 = make_hb(tmp_path / "h", detach_dag(), events=[
        {"event": "gate_failed", "gate": "GATE_P", "pass": 0, "fail": 1},
        {"event": "gate_passed", "gate": "GATE_P", "pass": 1, "fail": 0, "runtime": "python",
         "criteria": [{"id": "gp1", "cmd": "x", "exit": 0}]},
        {"event": "review_passed", "gate": "GATE_P", "artifact": "reviews/GATE_P.md"},
    ])
    assert detach(hb3, monkeypatch=monkeypatch) == 0
    assert "removed, not satisfied" not in capsys.readouterr().out.lower(), "warned on a healed+accepted predecessor"


def test_detach_changed_base_anchor(tmp_path, monkeypatch):
    from heartbeat import anchors
    hb = make_hb(tmp_path, detach_dag())
    monkeypatch.setenv("HB_ACTOR", "doer")
    assert run_cli(["start", "p1", "--dir", str(hb)]) == 0          # _start on the pristine tree
    (tmp_path / "noise.txt").write_text("other-phase noise")        # _start would include this
    assert detach(hb, monkeypatch=monkeypatch) == 0                 # anchor snapshots noise.txt
    (tmp_path / "dwork.txt").write_text("d work")
    c = anchors.changed(str(hb), "GATE_D")
    allp = c["added"] + c["modified"] + c["deleted"]
    assert "dwork.txt" in allp, "d's own work missing"
    assert "noise.txt" not in allp, "widened to _start (pre-detach noise reported)"
    # stamp mismatch → treated as missing → _start fallback
    a = json.loads((hb / "anchors" / "_detach_D.json").read_text())
    a["detached_at"] = "1999-01-01T00:00:00Z"
    (hb / "anchors" / "_detach_D.json").write_text(json.dumps(a))
    c2 = anchors.changed(str(hb), "GATE_D")
    assert "noise.txt" in c2["added"] + c2["modified"], "a stamp-mismatched anchor was trusted"


def test_detach_lint_rules(tmp_path):
    from heartbeat import lint as lintmod
    base = detach_dag()
    def errs(mod):
        d = json.loads(json.dumps(base))
        mod(d)
        return lintmod.lint(d)["errors"]
    def set_fields(p, **over):
        p.update({"detached_from": "GATE_P", "detached_reason": "r", "detached_by": "a",
                  "detached_at": "2026-01-01T00:00:00Z", **over})
    def D(d):
        return next(x for x in d["phases"] if x["id"] == "D")
    assert errs(lambda d: (D(d).__setitem__("gate_entry", None), D(d).__setitem__("detached_from", "GATE_P"))), \
        "partial detach fields lint clean"
    assert errs(lambda d: set_fields(D(d))), "detach fields with a non-null gate_entry lint clean"
    def notexit(d):
        D(d)["gate_entry"] = None
        set_fields(D(d), detached_from="GATE_ORPHAN")
        d["gates"]["GATE_ORPHAN"] = {"desc": "no phase exits here", "criteria": [{"id": "c", "desc": "d", "cmd": "true"}]}
    assert errs(notexit), "a non-gate_exit detached_from lints clean"
    def emptyts(d):
        D(d)["gate_entry"] = None
        set_fields(D(d), detached_at="  ")
    assert errs(emptyts), "an empty detached_at lints clean"
    assert errs(lambda d: d["gates"].__setitem__("_detach_EVIL", {"desc": "x", "criteria": [{"id": "c", "desc": "d", "cmd": "true"}]})), \
        "a reserved gate name lints clean"
    def unsafe(d):
        d["phases"].append({"id": "../evil", "title": "b", "gate_entry": None, "gate_exit": None, "tasks": []})
        set_fields(d["phases"][-1])
    assert errs(unsafe), "detach fields on an unsafe phase id lint clean"
    # a WELL-FORMED record lints clean
    def ok(d):
        D(d)["gate_entry"] = None
        set_fields(D(d))
    assert not [e for e in errs(ok) if "detach" in e.lower()], "a well-formed detach record lints dirty"
