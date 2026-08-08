#!/usr/bin/env bash
# Reproducible framework-proof runner. Docker is the LIVE tier only — it NEVER gates the suite.
#   run.sh --check <fw>    validate the harness for one framework, WITHOUT Docker
#   run.sh --check-all     validate every framework in the matrix, WITHOUT Docker
#   run.sh <fw>            build the pinned image + drive the real adapter against local Ollama
# --check derives the valid framework set from source (the backend registry ∩ pyproject extras)
# so a bogus framework or a matrix entry without an extra is rejected — not a hardcoded list.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$ROOT/tests/frameworks"
MATRIX="$HERE/matrix.txt"
REG="$ROOT/py/src/heartbeat/backends/__init__.py"
PYPROJECT="$ROOT/py/pyproject.toml"

registry(){ sed -n '/_KNOWN *= *{/,/}/p' "$REG" | grep -oE '"[a-z-]+"' | tr -d '"'; }
extras(){ awk '/\[project.optional-dependencies\]/{f=1;next} /^\[/{f=0} f && /=/{print $1}' "$PYPROJECT"; }
pin_for(){ awk -v fw="$1" '$1==fw{$1="";sub(/^[[:space:]]+/,"");print;exit}' "$MATRIX"; }

valid_fw(){ local fw="$1"
  extras   | grep -qx "$fw" || return 1     # must be a declared framework extra
  registry | grep -qx "$fw" || return 1     # must be a real backend
  [ -n "$(pin_for "$fw")" ] || return 1     # must be pinned in the matrix
}

check_one(){ local fw="$1"
  grep -q 'ARG FRAMEWORK' "$HERE/Dockerfile" && grep -q 'ARG VERSION' "$HERE/Dockerfile" \
    || { echo "Dockerfile is not parametrized (missing ARG FRAMEWORK/VERSION)"; return 1; }
  valid_fw "$fw" \
    || { echo "'$fw' is not a real backend with a pyproject extra pinned in the matrix"; return 1; }
  echo "FRAMEWORK-HARNESS-OK:$fw"
}

case "${1:-}" in
  --check)     check_one "${2:-}";;
  --check-all)
     ok=1
     while read -r fw _; do
       case "$fw" in ''|\#*) continue;; esac
       check_one "$fw" >/dev/null 2>&1 || { echo "harness invalid for: $fw"; ok=0; }
     done < "$MATRIX"
     [ "$ok" = 1 ] && echo "HARNESS-ALL-OK" || { echo "HARNESS-ALL-FAIL"; exit 1; } ;;
  ''|-h|--help) echo "usage: run.sh <framework> | --check <fw> | --check-all"; exit 2;;
  *)
     fw="$1"
     check_one "$fw" >/dev/null || { echo "invalid framework: $fw (see matrix.txt)"; exit 1; }
     command -v docker >/dev/null 2>&1 || { echo "docker not available — live tier needs Docker"; exit 1; }
     spec="$(pin_for "$fw")"; img="hb-fw-$fw"
     echo "==> build $img  ($spec)"
     docker build -f "$HERE/Dockerfile" --build-arg FRAMEWORK="$fw" --build-arg VERSION="$spec" -t "$img" "$ROOT" \
       || { echo "BUILD-FAIL:$fw"; exit 1; }
     echo "==> run $img against Ollama (${OLLAMA_HOST:-http://localhost:11434})"
     docker run --rm --network host \
       -e OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}" \
       -e HB_EXEC_MODEL="${HB_EXEC_MODEL:-qwen2.5:7b-instruct}" "$img"
     ;;
esac
