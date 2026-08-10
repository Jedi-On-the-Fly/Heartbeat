#!/usr/bin/env bash
# Parity of the BACKENDS REGISTRY: both runtimes must offer the same set of backend names, so you
# can't add a backend to one runtime and forget the other. The one documented divergence is the
# python-only `claude` alias for `claude-code` (both resolve to the same adapter); it is normalized
# out before comparing. Prints REGISTRY-PARITY-OK only when the canonical sorted sets are identical.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }

# python: _KNOWN minus the documented `claude` alias
py_set=$(PYTHONPATH="$ROOT/py/src" python3 -c "from heartbeat.backends import _KNOWN; print('\n'.join(sorted(n for n in _KNOWN if n != 'claude')))")
# node: the backend cases in hb-exec.js defaultCmd (they all dispatch to an executor under ex/)
node_set=$(grep -E "case '[a-z-]+':.*path\.join\(ex" "$ROOT/plugin/templates/hb-exec.js" \
  | grep -oE "case '[a-z-]+'" | sed "s/case '//; s/'//" | sort -u)

n_py=$(printf '%s\n' "$py_set" | grep -c .)
n_node=$(printf '%s\n' "$node_set" | grep -c .)
[ "$n_py" -gt 0 ] && [ "$n_node" -gt 0 ] || { echo "FAIL: empty registry set (py=$n_py node=$n_node)"; exit 1; }

if [ "$py_set" != "$node_set" ]; then
  echo "FAIL: backend registries differ (canonical):"
  diff <(printf '%s\n' "$node_set") <(printf '%s\n' "$py_set") | sed 's/^/    /'
  exit 1
fi

echo "REGISTRY-PARITY-OK: node ≡ python backend registry ($n_py canonical backends; python-only 'claude' alias normalized)."
