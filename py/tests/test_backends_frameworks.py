import importlib.util

import pytest

from heartbeat.backends import get, langgraph, openai_agents, autogen, smolagents, pydanticai


def _installed(*mods):
    return all(importlib.util.find_spec(m) is not None for m in mods)


def test_registry_resolves_new_backends():
    assert get("langgraph") is langgraph
    assert get("openai-agents") is openai_agents
    assert get("autogen") is autogen
    assert get("smolagents") is smolagents
    assert get("pydantic-ai") is pydanticai


@pytest.mark.skipif(_installed("langgraph", "langchain_core"), reason="langgraph installed")
def test_langgraph_degrades_to_protocol_valid():
    e = langgraph.execute({"context": "x", "cwd": "/tmp"})
    assert e.get("ok") is False and "summary" in e
    r = langgraph.refute({"context": "x"})
    assert not isinstance(r.get("refuted"), bool) and ("error" in r or "findings" in r)  # sentinel, never a fail-open pass


@pytest.mark.skipif(_installed("agents"), reason="openai-agents installed")
def test_openai_agents_degrades_to_protocol_valid():
    e = openai_agents.execute({"context": "x", "cwd": "/tmp"})
    assert e.get("ok") is False and "summary" in e
    r = openai_agents.refute({"context": "x"})
    assert not isinstance(r.get("refuted"), bool) and ("error" in r or "findings" in r)  # sentinel, never a fail-open pass


@pytest.mark.skipif(_installed("autogen_agentchat", "autogen_ext"), reason="autogen installed")
def test_autogen_degrades_to_protocol_valid():
    assert autogen.execute({"context": "x", "cwd": "/tmp"}).get("ok") is False
    assert not isinstance(autogen.refute({"context": "x"}).get("refuted"), bool)  # degrade → sentinel


@pytest.mark.skipif(_installed("smolagents"), reason="smolagents installed")
def test_smolagents_degrades_to_protocol_valid():
    assert smolagents.execute({"context": "x", "cwd": "/tmp"}).get("ok") is False
    assert not isinstance(smolagents.refute({"context": "x"}).get("refuted"), bool)  # degrade → sentinel


@pytest.mark.skipif(_installed("pydantic_ai"), reason="pydantic-ai installed")
def test_pydanticai_degrades_to_protocol_valid():
    assert pydanticai.execute({"context": "x", "cwd": "/tmp"}).get("ok") is False
    assert not isinstance(pydanticai.refute({"context": "x"}).get("refuted"), bool)  # degrade → sentinel
