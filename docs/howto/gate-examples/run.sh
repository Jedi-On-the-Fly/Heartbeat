#!/usr/bin/env bash
# Self-verifying runner for the behavioral-gate examples in this directory.
# See SPEC.md for the proof contract. Each <name>/example.sh proves ONE weakness,
# in discriminating mode (setup_stub/setup_real/weak_gate/strong_gate) or property
# mode (a prove function). Every check runs in its own temp dir. Exit 0 and print
# ALL-EXAMPLES-PROVEN only when every example is proven.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run one hook of an example in a clean temp dir; return that hook's exit code.
_phase() { # $1=example.sh  $2=setup fn  $3=gate fn
  local ex="$1" setup="$2" gate="$3" wd rc
  wd="$(mktemp -d)"
  ( cd "$wd" || exit 99
    setup_stub(){ :; }; setup_real(){ :; }
    weak_gate(){ return 1; }; strong_gate(){ return 1; }
    . "$ex"
    "$setup"
    "$gate"
  ) >/dev/null 2>&1
  rc=$?; rm -rf "$wd"; return $rc
}

prove_example() { # $1=example.sh -> 0 if the weakness is proven
  local ex="$1" wd rc
  if ( . "$ex"; declare -F prove >/dev/null ) 2>/dev/null; then
    wd="$(mktemp -d)"
    ( cd "$wd" || exit 99; . "$ex"; prove ) >/dev/null 2>&1
    rc=$?; rm -rf "$wd"; return $rc
  fi
  _phase "$ex" setup_stub weak_gate   || return 1   # 1. weak PASSES on the stub
  _phase "$ex" setup_stub strong_gate && return 1   # 2. strong FAILS on the stub
  _phase "$ex" setup_real strong_gate || return 1   # 3. strong PASSES on real
  return 0
}

if [ "${1:-}" = "--selftest" ]; then
  bd="$(mktemp -d)"
  cat > "$bd/example.sh" <<'EOF'
setup_stub(){ : > out.txt; }
setup_real(){ echo ok > out.txt; }
weak_gate(){ test -f out.txt; }
strong_gate(){ test -f out.txt; }   # deliberately hollow: passes on the stub too
EOF
  if prove_example "$bd/example.sh"; then
    echo "SELFTEST-ESCAPED: the runner accepted a hollow example"; rm -rf "$bd"; exit 1
  fi
  echo "SELFTEST-CAUGHT: the runner rejected a hollow example"; rm -rf "$bd"; exit 0
fi

total=0; proven=0
for d in "$HERE"/*/; do
  ex="${d}example.sh"; [ -f "$ex" ] || continue
  total=$((total + 1))
  if prove_example "$ex"; then
    echo "PROVEN:$(basename "$d")"; proven=$((proven + 1))
  else
    echo "FAILED:$(basename "$d")"
  fi
done
echo "examples: ${proven}/${total} proven"
if [ "$total" -gt 0 ] && [ "$proven" = "$total" ]; then
  echo "ALL-EXAMPLES-PROVEN:${proven}"; exit 0
fi
exit 1
