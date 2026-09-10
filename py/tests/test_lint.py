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


def test_extract_paths_rejects_non_file_slash_tokens():
    # path-shaped but not files: module specifiers, URL paths, relative route args — must not rot-trip
    assert "playwright/test" not in lint.extract_paths('node -e "require.resolve(\'playwright/test\')"')
    assert "3000/health" not in lint.extract_paths("curl -s localhost:3000/health 2>/dev/null")
    assert "api/v1/users" not in lint.extract_paths("node app.js api/v1/users")


def test_extract_paths_keeps_real_artifacts():
    # a file extension, or a known extensionless artifact name, is still tracked for rot
    assert "tests/e2e/x.spec.js" in lint.extract_paths("node tests/e2e/x.spec.js")
    assert "tests/frameworks/Dockerfile" in lint.extract_paths("docker build -f tests/frameworks/Dockerfile .")
    assert "build/Makefile" in lint.extract_paths("make -f build/Makefile all")


def test_extract_paths_drops_single_quoted_grep_literals():
    # a single-quoted string is text the command searches FOR, not a file it depends on —
    # grep '@import "blocks/dock.css" …' must not rot-trip on blocks/dock.css
    cmd = "grep -q '@import \"blocks/dock.css\" layer(jotf.bricks)' \"$PROJECT_DIR/public/blocks.css\""
    paths = lint.extract_paths(cmd)
    assert "blocks/dock.css" not in paths
    assert "public/blocks.css" in paths


def test_extract_paths_keeps_single_quotes_nested_in_double_quotes():
    # inside double quotes a single quote is just a character; the path still expands and counts
    assert "src/App.php" in lint.extract_paths('php -r "require(\'$PROJECT_DIR/src/App.php\');"')


def test_extract_paths_rejects_unresolved_vars_anywhere():
    # loop variables and ${X:-default} shrapnel are not statically checkable paths
    assert lint.extract_paths('cmp "$PROJECT_DIR/blocks/$n.css" "$SRC/blocks/$n.css"') == set()
    paths = lint.extract_paths('S="${SRC:-/opt/kit}"; cmp "$S/blocks/dock.css" "$PROJECT_DIR/vendor/dock.css"')
    assert paths == {"vendor/dock.css"}
