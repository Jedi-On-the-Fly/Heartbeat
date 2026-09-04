import heartbeat
from heartbeat import cli, protocol


def test_version():
    assert heartbeat.__version__


def test_cli_no_args_prints_help(capsys):
    assert cli.main([]) == 1
    assert "hb" in capsys.readouterr().out.lower()


def test_protocol_render_md():
    md = protocol.render_md()
    assert "pulse protocol" in md and "next_task" in md and "gate_pending" in md


def test_protocol_matches_reason_set():
    # every reason the tick can emit has an action
    for r in ("next_task", "gate_pending", "review_pending", "gate_blocked", "all_done", "deadlock"):
        assert r in protocol.PROTOCOL
