from heartbeat import lint


def test_clean_dag():
    dag = {"phases": [{"id": "P0", "gate_entry": None, "gate_exit": "G0",
                       "tasks": [{"id": "A", "requires": []}]}],
           "gates": {"G0": {"criteria": [{"id": "c", "cmd": "true"}]}}}
    assert lint.lint(dag)["errors"] == []


def test_duplicate_ids():
    dag = {"phases": [{"id": "P0", "gate_exit": "G0", "tasks": [{"id": "A"}, {"id": "A"}]}],
           "gates": {"G0": {}}}
    assert any("duplicate" in e for e in lint.lint(dag)["errors"])


def test_broken_requires():
    dag = {"phases": [{"id": "P0", "gate_exit": "G0", "tasks": [{"id": "A", "requires": ["Z"]}]}],
           "gates": {"G0": {}}}
    assert any("non-existent" in e for e in lint.lint(dag)["errors"])


def test_cycle():
    dag = {"phases": [{"id": "P0", "gate_exit": "G0",
                       "tasks": [{"id": "A", "requires": ["B"]}, {"id": "B", "requires": ["A"]}]}],
           "gates": {"G0": {}}}
    assert any("cycle" in e for e in lint.lint(dag)["errors"])


def test_undefined_gate():
    dag = {"phases": [{"id": "P0", "gate_exit": "MISSING", "tasks": [{"id": "A"}]}], "gates": {}}
    assert any("undefined gate" in e for e in lint.lint(dag)["errors"])


def test_extract_paths_strips_project_dir():
    paths = lint.extract_paths('node -e "require(\'$PROJECT_DIR/greeting.js\')"')
    assert "greeting.js" in paths
