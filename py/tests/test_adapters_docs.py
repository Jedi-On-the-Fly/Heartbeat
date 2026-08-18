"""The Python docs adapter (a parity surface with plugin/adapters/docs/*.js — proofs T95)."""
from heartbeat.adapters.docs import docs_map as dm, docs_context as dc


def test_docs_map_citations_and_exclusions(tmp_path):
    (tmp_path / "a.md").write_text("# A\nsee [b](b.md), an [ext](https://x/results.md), a [self](a.md)")
    (tmp_path / "b.md").write_text("# B\nno links")
    m = dm.citation_map(str(tmp_path))
    assert set(map(tuple, m["edges"])) == {("a", "b")}          # external + self excluded
    assert m["tasks"] == {"a": ["a"], "b": ["b"]}               # one task per section


def test_docs_context_renders_direct_cited_text(tmp_path):
    (tmp_path / "m.md").write_text("# Method\nThe approach body.")
    (tmp_path / "bg.md").write_text("# Background\nProblem statement.")
    # results cites method (direct); method cites bg (2-hop) -> only method's text should render
    codemap = {"edges": [["r", "m"], ["m", "bg"]], "tasks": {"r": ["r"]}}
    out = dc.cited_context(str(tmp_path), codemap, "r")
    assert "--- m ---" in out and "The approach body." in out
    assert "Problem statement." not in out                     # 2-hop excluded


def test_docs_context_cites_nothing_and_missing_file(tmp_path):
    assert "(this task cites nothing)" in dc.cited_context(str(tmp_path), {"edges": [], "tasks": {"t": ["t"]}}, "t")
    out = dc.cited_context(str(tmp_path), {"edges": [["t", "ghost"]], "tasks": {"t": ["t"]}}, "t")
    assert "--- ghost ---" in out and "(section text unavailable)" in out


def test_js_trim_strips_bom_keeps_nel(tmp_path):
    # a BOM-prefixed section must render byte-identically to node (JS .trim() strips U+FEFF)
    (tmp_path / "s.md").write_text("﻿# Section\nbody\x85tail")
    out = dc.cited_context(str(tmp_path), {"edges": [["t", "s"]], "tasks": {"t": ["t"]}}, "t")
    assert "﻿" not in out and "\x85" in out                # BOM stripped, NEL kept (like JS)
