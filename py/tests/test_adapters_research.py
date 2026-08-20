"""The Python research adapter (grounding verifier; a parity surface with plugin/adapters/research/ground-check.js — T111)."""
import hashlib
import os

from heartbeat.adapters.research import ground_check as gc
from heartbeat.adapters.research import research_context as rc
from heartbeat.adapters.research import stamp_evidence as se


def _write(d, name, text):
    p = os.path.join(d, name)
    with open(p, "w") as f:
        f.write(text)
    return p


def test_ground_check_classifies(tmp_path):
    src = tmp_path / "sources"
    src.mkdir()
    body = "Under standard pressure, water boils at 100 degrees\nCelsius at sea level."
    (src / "s1.txt").write_text(body)
    sha = hashlib.sha256(body.encode()).hexdigest()
    evidence = {
        "sources": {"s1": {"url": "http://x", "sha256": sha}},
        "claims": {
            "c_ok": {"source": "s1", "excerpt": "water boils at 100 degrees Celsius at sea level"},  # line-wrap → normalized
            "c_fab": {"source": "s1", "excerpt": "the moon is made of cheese"},                       # not in source
            "c_nosrc": {"source": "s2", "excerpt": "x"},                                              # undeclared source
            "c_empty": {"source": "s1", "excerpt": ""},                                               # no excerpt
        },
    }
    r = gc.ground_check(evidence, str(src))
    assert r["grounded"] == 1                                       # only c_ok
    kinds = " ".join(r["issues"])
    assert "FABRICATED-QUOTE: c_fab" in kinds
    assert "UNGROUNDED: c_nosrc" in kinds and "UNGROUNDED: c_empty" in kinds


def test_ground_check_stale_on_edit(tmp_path):
    src = tmp_path / "sources"
    src.mkdir()
    (src / "s1.txt").write_text("original text with the exact quote here")
    evidence = {
        "sources": {"s1": {"sha256": "deadbeef"}},                  # wrong sha → edited since fetch
        "claims": {"c1": {"source": "s1", "excerpt": "the exact quote"}},
    }
    r = gc.ground_check(evidence, str(src))
    assert r["grounded"] == 0
    assert any(i.startswith("STALE: c1") for i in r["issues"])      # sha checked BEFORE excerpt


def test_research_context_renders_only_its_section():
    evidence = {
        "sources": {"s1": {"url": "http://x"}, "s2": {"url": "http://y"}},
        "claims": {
            "c_bg1": {"text": "T1", "source": "s1", "excerpt": "e1", "section": "background"},
            "c_bg2": {"text": "T2", "source": "s1", "excerpt": "e2", "section": "background"},
            "c_m1": {"text": "M", "source": "s2", "excerpt": "METHOD-ONLY", "section": "method"},
        },
    }
    out = rc.research_context(evidence, "background")
    assert out.startswith("Grounded evidence for background:")
    assert "c_bg1: T1" in out and "c_bg2: T2" in out
    assert "source s1 http://x" in out and "» e1" in out
    assert "METHOD-ONLY" not in out and "c_m1" not in out          # no cross-section leak
    assert rc.research_context(evidence, "nosuch") == "Grounded evidence for nosuch:\n  (none)"


def test_stamp_evidence_records_real_sha(tmp_path):
    src = tmp_path / "sources"
    src.mkdir()
    body = "water boils at 100 degrees Celsius at sea level"
    (src / "s1.txt").write_text(body)
    evidence = {"sources": {"s1": {"url": "http://x"}}, "claims": {}}  # shaless input
    stamped = se.stamp_evidence(evidence, str(src))
    assert stamped["sources"]["s1"]["sha256"] == hashlib.sha256(body.encode()).hexdigest()
