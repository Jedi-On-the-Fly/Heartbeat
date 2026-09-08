#!/usr/bin/env bash
# Proof (bug: bootstrap-noninteractive-hang): re-bootstrapping a project that already has .hb/ must
# NOT block when stdin is an open-but-silent pipe (a descriptor that never delivers a byte and never
# reaches EOF — a test harness / agent / CI runner holding a pipe open). bootstrap.sh must prompt only
# with a real terminal; otherwise take the safe default (refuse), never overwriting. --force still
# overwrites. Portable: stock macOS has no coreutils, so timeout(1) is ABSENT — the very platform the
# bug hangs on — hence this proof carries its own run_bounded (background + poll + kill), never `timeout`.
# Prints BOOTSTRAP-NI-OK. --selftest proves the silent-pipe detector has teeth (RED on the unguarded read).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BS="$ROOT/plugin/bootstrap.sh"

# Run <cmd...> with a live-but-silent pipe on stdin and a portable time bound; return 0 if it returned
# in time, 124 if it had to be killed (i.e. it blocked). The fifo redirection MUST sit directly on the
# backgrounded command: in a non-interactive shell without job control, bash redirects an async command's
# stdin to /dev/null (instant EOF) UNLESS it carries its own explicit redirection — which would mask the
# very hang we're testing. No timeout(1): background + poll + kill, so it runs on stock macOS too.
silent_pipe_returns() {  # <bound_s> <cmd...>  → 0 returned in time, 124 hung
  local bound="$1"; shift
  local fifo; fifo="$(mktemp -u)"; mkfifo "$fifo"
  sleep $((bound + 5)) > "$fifo" & local w=$!    # writer holds the pipe open but never writes a byte
  "$@" < "$fifo" & local p=$!                     # explicit < fifo ON the async command (see note above)
  local i=0 n=$(( bound * 10 )) rc=0
  while kill -0 "$p" 2>/dev/null; do
    i=$((i + 1)); if [ "$i" -ge "$n" ]; then kill -9 "$p" 2>/dev/null; rc=124; break; fi
    sleep 0.1
  done
  [ "$rc" -eq 0 ] && { wait "$p"; rc=$?; }
  kill "$w" 2>/dev/null; wait "$w" 2>/dev/null; rm -f "$fifo"
  return "$rc"
}

check_all() {
  local bs="$1" tmp rc bad=""
  tmp="$(mktemp -d)"; export HB_NO_GIT=1
  bash "$bs" "$tmp/proj" </dev/null >/dev/null 2>&1 || bad="$bad; first-bootstrap-failed"
  # sentinel in a template that bootstrap always copies — survives a refuse, is wiped by --force.
  echo "#HB-SENTINEL" >> "$tmp/proj/.hb/tick.sh"

  # (A) silent pipe on stdin → must RETURN, not hang.
  silent_pipe_returns 4 bash "$bs" "$tmp/proj" || bad="$bad; A:silent-pipe-blocked(rc=$?)"

  # (B) non-tty (/dev/null) → refuses: sentinel survives (no overwrite) AND says Aborted.
  local out; out="$(bash "$bs" "$tmp/proj" </dev/null 2>&1)"
  grep -q '#HB-SENTINEL' "$tmp/proj/.hb/tick.sh" || bad="$bad; B:refuse-overwrote-the-file"
  echo "$out" | grep -qi 'abort'                || bad="$bad; B:no-abort-message"

  # (C) --force → overwrites: sentinel is gone (template recopied pristine).
  bash "$bs" "$tmp/proj" --force </dev/null >/dev/null 2>&1 || bad="$bad; C:force-bootstrap-failed"
  grep -q '#HB-SENTINEL' "$tmp/proj/.hb/tick.sh" && bad="$bad; C:force-did-not-overwrite"

  rm -rf "$tmp"
  [ -z "$bad" ] || { echo "FAIL:$bad"; return 1; }
  return 0
}

if [ "${1:-}" = "--selftest" ]; then
  # Teeth: the silent-pipe detector must flag the UNGUARDED read (the bug) and clear the [-t 0]-guarded one.
  old='read -p "Overwrite? (y/N) " -n 1 -r R || R="n"'          # returns non-zero on EOF, but a silent pipe never returns
  new='if [ -t 0 ]; then read -p "Overwrite? (y/N) " -n 1 -r R || R="n"; else R="n"; fi'
  silent_pipe_returns 2 bash -c "$old" && { echo "FAIL: selftest did not detect the unguarded-read hang"; exit 1; }
  silent_pipe_returns 2 bash -c "$new" || { echo "FAIL: selftest wrongly flagged the guarded read as hanging"; exit 1; }
  echo "SELFTEST-OK: silent-pipe detector flags the unguarded read AND clears the [-t 0]-guarded one"
  exit 0
fi

check_all "$BS" || exit 1
echo "BOOTSTRAP-NI-OK"
