#!/usr/bin/env bash
# codex-network.sh — the codex adapter's network is an explicit opt-in. `codex exec -s workspace-write`
# has no network — not even loopback — so a codex refuter cannot exercise the local server it reviews.
# HB_CODEX_NETWORK=1 adds `-c sandbox_workspace_write.network_access=true` to the execute and refute
# calls (the workspace-write sandbox); the constraint author stays read-only and never gets it. Any other
# value, or unset, adds nothing. Both runtimes: the shell adapter (codex-exec.sh) and the in-process
# python backend (which now has its own read-only author, like the shell adapter). Observed with a fake
# `codex` on PATH that logs its argv — no model, no network.
#   bash tests/codex-network.sh      prints CODEX-NETWORK-OK
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*"; exit 1; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin"
cat > "$W/bin/codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\x1f' "$@" >> "$CODEX_LOG"; printf '\n' >> "$CODEX_LOG"
echo '[{"id":"G1","claim":"c","subjects":["a.txt"],"violation":"v"}]'
printf 'looked.\nCLEAR\n'
EOF
chmod +x "$W/bin/codex"
NET="sandbox_workspace_write.network_access=true"

# <runtime> <mode> <HB_CODEX_NETWORK value or UNSET> → prints "sandbox|net" for each codex call
calls() { local rt="$1" mode="$2" v="$3" log="$W/log" d; : > "$log"; d="$(mktemp -d "$W/d.XXXX")"
  local envs=(PATH="$W/bin:$PATH" CODEX_LOG="$log")
  [ "$v" = UNSET ] || envs+=(HB_CODEX_NETWORK="$v")
  if [ "$rt" = shell ]; then
    ( cd "$d" && printf '{"prompt":"p","context":"c"}' | env -u HB_CODEX_NETWORK "${envs[@]}" bash "$ROOT/plugin/templates/executors/codex-exec.sh" "$mode" >/dev/null 2>&1 )
  else
    ( cd "$d" && env -u HB_CODEX_NETWORK "${envs[@]}" PYTHONPATH="$ROOT/py/src" python3 -c '
import sys; from heartbeat.backends import codex as c
getattr(c, sys.argv[1])({"prompt": "p", "context": "c", "cwd": sys.argv[2]})' "$mode" "$d" >/dev/null 2>&1 )
  fi
  python3 - "$log" "$NET" <<'PY'
import sys
log, net = sys.argv[1:3]
for rec in open(log).read().split("\x1f\n"):   # one record per call (a prompt argument spans lines)
    a = rec.split("\x1f")
    if not rec: continue
    sb = a[a.index("-s") + 1] if "-s" in a else "?"
    has = any(a[i] == "-c" and i + 1 < len(a) and a[i + 1] == net for i in range(len(a)))
    print("%s|%s" % (sb, "net" if has else "nonet"))
PY
}

for rt in shell python; do
  for mode in execute refute; do
    o="$(calls "$rt" "$mode" 1)"
    [ -n "$o" ] || fail "$rt $mode: codex was not called"
    printf '%s\n' "$o" | grep -qv '^workspace-write|net$' && fail "$rt $mode: HB_CODEX_NETWORK=1 did not give every workspace-write call network ($o)"
    for v in UNSET 0 true yes ""; do
      o="$(calls "$rt" "$mode" "$v")"
      printf '%s\n' "$o" | grep -q '|net$' && fail "$rt $mode: network added although HB_CODEX_NETWORK=${v} (only 1 opts in)"
    done
  done
  o="$(calls "$rt" author 1)"
  [ -n "$o" ] || fail "$rt author: codex was not called"
  [ "$(printf '%s\n' "$o" | sort -u)" = "read-only|nonet" ] || fail "$rt author: the constraint author must run read-only without network, got: $o"
done

# the python author returns the constraint list (read from the reply), like the shell adapter
out="$(cd "$W" && PATH="$W/bin:$PATH" CODEX_LOG="$W/log" PYTHONPATH="$ROOT/py/src" python3 -c '
import json; from heartbeat.backends import codex as c
print(json.dumps(c.author({"prompt": "p", "cwd": "."})))')"
printf '%s' "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get("ok") is True and d["constraints"][0]["id"] == "G1" else 1)' \
  || fail "python author: no constraint list from the reply ($out)"
echo "CODEX-NETWORK-OK"
