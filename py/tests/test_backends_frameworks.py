import importlib.util

import pytest

from heartbeat.backends import get, langgraph, openai_agents


def _installed(*mods):
    return all(importlib.util.find_spec(m) is not None for m in mods)


def test_registry_resolves_new_backends():
    assert get("langgraph") is langgraph
    assert get("openai-agents") is openai_agents


@pytest.mark.skipif(_installed("langgraph", "langchain_core"), reason="langgraph installed")
def test_langgraph_degrades_to_protocol_valid():
    e = langgraph.execute({"context": "x", "cwd": "/tmp"})
    assert e.get("ok") is False and "summary" in e
    r = langgraph.refute({"context": "x"})
    assert r.get("refuted") is False and "findings" in r


@pytest.mark.skipif(_installed("agents"), reason="openai-agents installed")
def test_openai_agents_degrades_to_protocol_valid():
    e = openai_agents.execute({"context": "x", "cwd": "/tmp"})
    assert e.get("ok") is False and "summary" in e
    r = openai_agents.refute({"context": "x"})
    assert r.get("refuted") is False and "findings" in r
