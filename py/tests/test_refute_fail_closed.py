"""A refute verdict only when the reviewer gave one (twin of tests/refute-fail-closed.sh).

A refutation that could not run, or whose reply carries no final REFUTED/CLEAR token, is an
{"error": …} the driver escalates — never {"refuted": False}, which reads as "could not refute".
The ollama backend asks for an explicit context and refuses a result whose prompt filled it.
"""
import io
import json
import os
import stat
import urllib.error

import pytest

from heartbeat import backends
from heartbeat.backends import ollama, refute_result


def test_refute_result_is_three_state():
    assert refute_result("the gate is hollow. REFUTED") == {"refuted": True, "findings": "the gate is hollow. REFUTED"}
    assert refute_result("looks complete. CLEAR")["refuted"] is False
    r = refute_result("some thoughts, no conclusion")
    assert "error" in r and "refuted" not in r
    assert "error" in refute_result("") and "error" in refute_result(None)


def test_the_verdict_is_a_whole_upper_case_word():
    # "unclear" after a REFUTED must not read as the final CLEAR; a lower-case "clear" is no verdict
    assert refute_result("The rest is unclear. Hollow. REFUTED")["refuted"] is True
    assert "error" in refute_result("Looks fine to me, all clear.")
    assert "error" in refute_result("UNCLEAR")
    assert refute_result("**CLEAR**")["refuted"] is False
    # a verdict line carrying both tokens (a copied answer template) is no verdict
    assert "error" in refute_result("## Findings\nnone\n## Verdict\nREFUTED | CLEAR")
    assert refute_result("I first thought CLEAR.\nThe gate is hollow. REFUTED")["refuted"] is True
    # a negated final token ("NOT CLEAR") is no verdict — read as CLEAR it would pass a refutation
    assert "error" in refute_result("The criterion never runs the edge case, so the gate is NOT CLEAR.")
    # the token must stand alone: a token inside a sentence ("NOT yet CLEAR", "far from CLEAR") is none
    for s in ("Several criteria fail, so the gate is NOT yet CLEAR.", "far from CLEAR", "It is never CLEAR."):
        assert "error" in refute_result(s), s
    assert refute_result("I checked every criterion.\n\n**Verdict:** CLEAR")["refuted"] is False
    assert refute_result("Final verdict — REFUTED")["refuted"] is True
    # the verdict must be the reply's final word, standing alone (review 5's forms are none)
    for s in ("Hollow. REFUTED. The rest is unclear.", "P1: VIOLATED (reproduced). CLEAR would be premature.",
              "P1: VIOLATED. The gate fails, so it is not\nCLEAR.", "Choose one:\n* REFUTED\n* CLEAR"):
        assert "error" in refute_result(s), s


def test_opencode_reads_the_models_text_not_tool_output(tmp_path, monkeypatch):
    mod = backends.get("opencode")
    fake = tmp_path / "opencode"
    def ev(*pairs):
        out = []
        for kind, val in pairs:
            part = {"type": "text", "text": val} if kind == "text" else \
                {"type": "tool", "tool": "read", "state": {"status": "completed", "output": val}}
            out.append(json.dumps({"type": "text" if kind == "text" else "tool_use", "part": part}))
        return "\n".join(out)
    monkeypatch.setenv("PATH", f"{tmp_path}:{os.environ['PATH']}")
    for events, want in ((ev(("text", "Some thoughts, no conclusion."), ("tool", "const CLEAR = 1")), "error"),
                         (ev(("text", "The gate is hollow. REFUTED"), ("tool", "clear() is called")), True),
                         (ev(("tool", "REFUTED in a comment"), ("text", "Every criterion holds. CLEAR")), False)):
        (tmp_path / "ev.jsonl").write_text(events + "\n")
        fake.write_text('#!/usr/bin/env bash\ncase "$*" in *--help*) exit 0;; esac\ncat "' + str(tmp_path / "ev.jsonl") + '"\n')
        fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
        r = mod.refute({"prompt": "Refute.", "cwd": str(tmp_path)})
        if want == "error":
            assert "error" in r and "refuted" not in r, r
        else:
            assert r.get("refuted") is want, r


def test_refute_raw_passthrough_for_the_author_fallback(monkeypatch):
    monkeypatch.setenv("HB_REFUTE_RAW", "1")
    assert refute_result('[{"id":"G1"}]') == {"refuted": False, "findings": '[{"id":"G1"}]'}


class _Reply(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


def _mock_ollama(monkeypatch, response, prompt_eval_count):
    seen = {}

    def urlopen(req, timeout=None):
        seen["body"] = json.loads(req.data.decode())
        n = prompt_eval_count if prompt_eval_count is not None else seen["body"]["options"]["num_ctx"]
        return _Reply(json.dumps({"response": response, "prompt_eval_count": n}).encode())
    monkeypatch.setattr(ollama.urllib.request, "urlopen", urlopen)
    return seen


def test_ollama_sends_an_explicit_context_and_honours_the_env(monkeypatch):
    seen = _mock_ollama(monkeypatch, "fine. CLEAR", 900)
    monkeypatch.delenv("HB_OLLAMA_NUM_CTX", raising=False)
    assert ollama.refute({"prompt": "Refute."}) == {"refuted": False, "findings": "fine. CLEAR"}
    assert seen["body"]["options"]["num_ctx"] >= 16384
    monkeypatch.setenv("HB_OLLAMA_NUM_CTX", "24576")
    ollama.refute({"prompt": "Refute."})
    assert seen["body"]["options"]["num_ctx"] == 24576


def test_ollama_refuses_a_truncated_prompt(monkeypatch):
    _mock_ollama(monkeypatch, "fine. CLEAR", None)           # prompt_eval_count == num_ctx
    r = ollama.refute({"prompt": "Refute."})
    assert "error" in r and "truncated" in r["error"] and "refuted" not in r
    e = ollama.execute({"context": "task", "cwd": os.getcwd()})
    assert e["ok"] is False and "truncated" in e["summary"]


def test_ollama_no_verdict_and_unreachable_are_errors(monkeypatch):
    _mock_ollama(monkeypatch, "some thoughts, no conclusion", 900)
    assert "error" in ollama.refute({"prompt": "Refute."})

    def down(req, timeout=None):
        raise urllib.error.URLError("connection refused")
    monkeypatch.setattr(ollama.urllib.request, "urlopen", down)
    r = ollama.refute({"prompt": "Refute."})
    assert "error" in r and "refuted" not in r


@pytest.mark.parametrize("name", ["claude", "codex"])   # opencode: JSON events, below
def test_cli_backends_without_a_verdict_token_are_errors(name, tmp_path, monkeypatch):
    mod = backends.get(name)
    fake = tmp_path / name
    for reply, want in (("thoughts but no conclusion", "error"), ("looks complete. CLEAR", False), ("hollow. REFUTED", True)):
        fake.write_text("#!/usr/bin/env bash\ncat >/dev/null 2>&1 </dev/null; printf %s " + json.dumps(reply) + "\n")
        fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
        monkeypatch.setenv("PATH", f"{tmp_path}:{os.environ['PATH']}")
        r = mod.refute({"prompt": "Refute.", "cwd": str(tmp_path)})
        if want == "error":
            assert "error" in r and "refuted" not in r, (name, reply, r)
        else:
            assert r.get("refuted") is want, (name, reply, r)


def test_author_fallback_still_parses_the_raw_reply(tmp_path, monkeypatch):
    """a backend without author() — the executor reuses its refute(); the constraint array (no
    verdict token) must reach author_reply, not be turned into a no-verdict error"""
    from heartbeat import executor
    from types import SimpleNamespace
    reply = '[{"id": "G1", "claim": "c", "subjects": ["a.py"], "violation": "v"}]'
    fake = SimpleNamespace(execute=lambda p: {"ok": True, "summary": ""}, refute=lambda p: refute_result(reply))
    monkeypatch.setattr(executor.backends, "get", lambda name: fake)
    hb = tmp_path / ".hb"
    hb.mkdir()
    out = executor.dispatch({"backend": "fake", "cmd": None, "heartbeat_s": 0}, "author", {"prompt": "author"}, str(hb), None, cwd=str(tmp_path))
    assert out.get("ok") is True and out["constraints"][0]["id"] == "G1", out
    assert os.environ.get("HB_REFUTE_RAW") is None       # restored
