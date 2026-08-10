#!/usr/bin/env bash
# Proof for "Install the HeartBeat plugin": the install/update guide's structural claims are real,
# deterministically (no network — a real pip install can't be a gate). Verifies the components the
# guide relies on, so a renamed manifest, a dropped `hb` console script, or a vanished `mcp-serve`
# can't ship in the prose. Prints INSTALL-GUIDE-OK only when every claim holds.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }

# 1. PEP 668 fallback tool: `python3 -m venv` is available (the guide's externally-managed path).
python3 -c "import venv" 2>/dev/null || { echo "FAIL: python venv module unavailable (the guide's PEP 668 fallback)"; exit 1; }

# 2. `pip install ./py` yields the `hb` console: pyproject declares the entry point.
grep -qE '^[[:space:]]*hb[[:space:]]*=[[:space:]]*"heartbeat\.cli:main"' "$ROOT/py/pyproject.toml" \
  || { echo "FAIL: pyproject does not declare the hb console script"; exit 1; }

# 3. `hb mcp-serve` (the plugin's server command) is a real subcommand.
PYTHONPATH="$ROOT/py/src" python3 -m heartbeat.cli mcp-serve --help >/dev/null 2>&1 \
  || { echo "FAIL: hb mcp-serve is not a real subcommand"; exit 1; }

# 4. the marketplace manifest registers the `heartbeat` plugin (what /plugin install adds).
python3 -c "import json,sys; d=json.load(open('$ROOT/.claude-plugin/marketplace.json')); sys.exit(0 if 'heartbeat' in [p.get('name') for p in d.get('plugins',[])] else 1)" \
  || { echo "FAIL: marketplace.json does not register the 'heartbeat' plugin"; exit 1; }

echo "INSTALL-GUIDE-OK: venv fallback present; pip yields the hb console; hb mcp-serve real; marketplace registers heartbeat."
