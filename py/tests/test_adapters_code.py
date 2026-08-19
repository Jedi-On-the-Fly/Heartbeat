"""The Python code adapter (a parity surface with plugin/adapters/code/*.js — proofs T94)."""
from heartbeat.adapters.code import deplint as dl, codegraph_map as cm, codegraph_context as cc
from heartbeat.adapters.code import codegraph_discover as cd


def test_deplint_detects_directed_missing():
    dag = {"phases": [{"tasks": [{"id": "TA", "requires": []}, {"id": "TB", "requires": []}]}]}
    codemap = {"edges": [["symA", "symB"]], "tasks": {"TA": ["symA"], "TB": ["symB"]}}
    r = dl.deplint(dag, codemap)
    assert [(m["from"], m["to"]) for m in r["missing"]] == [("TA", "TB")]   # A cites B -> A requires B
    assert not r["redundant"] and not r["collision"]


def test_deplint_transitive_not_flagged():
    dag = {"phases": [{"tasks": [{"id": "TA", "requires": ["TB"]}, {"id": "TB", "requires": ["TC"]},
                                 {"id": "TC", "requires": []}]}]}
    codemap = {"edges": [["symA", "symC"]], "tasks": {"TA": ["symA"], "TC": ["symC"]}}
    assert dl.deplint(dag, codemap)["missing"] == []   # TA already ordered-after TC transitively


def test_map_filters_nondependency_and_resolves_names():
    rows = {"nodes": [{"id": 1, "qualified_name": "a::F"}, {"id": 2, "qualified_name": "b::G"}],
            "edges": [{"from_id": 1, "to_id": 2, "type": "calls"},
                      {"from_id": 2, "to_id": 1, "type": "contains"}]}
    assert cm.map_codegraph(rows)["edges"] == [["a::F", "b::G"]]   # calls kept, contains dropped


def test_context_renders_direct_neighbors_only():
    codemap = {"edges": [["symA", "symB"], ["symZ", "symA"], ["symU", "symB"]], "tasks": {"TA": ["symA"]}}
    out = cc.context_for(codemap, "TA")
    assert "symB" in out and "symZ" in out and "symU" not in out


_DISCO = {"edges": [["main", "service"], ["service", "repo"], ["repo", "db"],
                    ["api", "service"], ["service", "auth"], ["a", "b"], ["b", "a"]]}


def test_discover_dependents_is_reverse_reachability():
    r = cd.discover(_DISCO, ["repo"], "dependents")   # who transitively depends on repo (change impact)
    assert r["affected"] == ["api", "main", "repo", "service"]     # excludes db/auth (dependencies)
    assert r["edges"] == [["api", "service"], ["main", "service"], ["service", "repo"]]


def test_discover_dependencies_is_forward_reachability():
    r = cd.discover(_DISCO, ["repo"], "dependencies")
    assert r["affected"] == ["db", "repo"]            # what repo needs, not its callers


def test_discover_both_is_union_and_cycle_terminates():
    assert cd.discover(_DISCO, ["repo"], "both")["affected"] == ["api", "db", "main", "repo", "service"]
    assert cd.discover(_DISCO, ["a"], "dependents")["affected"] == ["a", "b"]   # cycle terminates, entry included
