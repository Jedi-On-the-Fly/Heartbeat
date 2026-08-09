#!/usr/bin/env bash
# Proof for "Add HeartBeat to an existing repository": bootstrapping into a repo that ALREADY
# has tracked files and history is non-destructive — it adds .hb, leaves your files byte-for-byte
# unchanged, and keeps your existing commit reachable. Deterministic. Prints EXISTING-REPO-OK
# only when every claim holds.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v git  >/dev/null 2>&1 || { echo "git absent";  exit 1; }
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# A pre-existing repo: a tracked file with real content, plus a commit.
repo="$tmp/repo"; mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email "dev@example.com"
git -C "$repo" config user.name  "Dev"
printf 'print("existing app")\n' > "$repo/app.py"
mkdir -p "$repo/src"; printf 'x = 1\n' > "$repo/src/lib.py"
git -C "$repo" add -A
git -C "$repo" commit -q -m "existing work"
orig_sha=$(git -C "$repo" rev-parse HEAD)
orig_app=$(cat "$repo/app.py")
orig_lib=$(cat "$repo/src/lib.py")

# Add HeartBeat to it.
HB_NO_HOOK=1 bash "$ROOT/plugin/bootstrap.sh" "$repo" >/dev/null 2>&1 </dev/null

# 1. .hb scaffolding was added.
[ -d "$repo/.hb" ] && [ -f "$repo/.hb/dag.json" ] || { echo "FAIL: .hb was not created"; exit 1; }
# 2. existing files are byte-for-byte unchanged (on disk).
[ "$(cat "$repo/app.py")" = "$orig_app" ] || { echo "FAIL: app.py was modified by bootstrap"; exit 1; }
[ "$(cat "$repo/src/lib.py")" = "$orig_lib" ] || { echo "FAIL: src/lib.py was modified by bootstrap"; exit 1; }
# 3. the pre-existing commit is still reachable (history intact, not re-init'd).
git -C "$repo" merge-base --is-ancestor "$orig_sha" HEAD 2>/dev/null || { echo "FAIL: the pre-existing commit is no longer reachable"; exit 1; }
# 4. that file's content is unchanged in git history too (HEAD's version == original).
[ "$(git -C "$repo" show HEAD:app.py)" = "$orig_app" ] || { echo "FAIL: app.py content changed in history"; exit 1; }

echo "EXISTING-REPO-OK: bootstrap added .hb, left existing files unchanged, and kept prior history reachable."
