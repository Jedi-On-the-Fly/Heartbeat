#!/usr/bin/env bash
# HeartBeat executor backend: opencode (headless `opencode run` — SST's provider-agnostic agent).
# Wire protocol: argv1 = execute|refute ; stdin = payload JSON ; stdout = ONE JSON line.
#   execute → {"ok":bool,"summary":str}   refute → {"refuted":bool,"findings":str}
# Model via HB_EXEC_MODEL (-m provider/model, e.g. ollama/qwen2.5:7b-instruct). Degrades to
# protocol-valid JSON if `opencode` isn't on PATH.
# Autonomy: opencode's `run` blocks on an "ask" permission with no TTY — configure opencode.json
# `permission: allow` for unattended use (0.15.3 has no --auto). The prompt travels as an argv
# message, so we run with </dev/null defensively.
set -uo pipefail

mode="${1:-execute}"
payload="$(cat)"
field() { printf '%s' "$payload" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{process.stdout.write(String((JSON.parse(d)$1)??''))}catch(e){process.stdout.write('')}})"; }
jstr()  { node -pe 'JSON.stringify(require("fs").readFileSync(0,"utf8"))'; }

ctx="$(field .context)"

if ! command -v opencode >/dev/null 2>&1; then
  if [ "$mode" = refute ]; then echo '{"refuted":false,"findings":"opencode CLI not available — could not run the refuter"}'
  else echo '{"ok":false,"summary":"opencode CLI not available"}'; fi
  exit 0
fi

mdl=()
if [ -n "${HB_EXEC_MODEL:-}" ]; then mdl=(-m "${HB_EXEC_MODEL}"); fi

if [ "$mode" = refute ]; then
  rp="$(field .prompt)"
  ans="$(opencode run --format json "${mdl[@]}" "You are a SKEPTICAL adversarial reviewer for a HeartBeat phase gate.
${rp}

Context:
${ctx}

Do not modify files. Hunt for a real hole: a hollow test, a criterion not truly met, a faked or hard-coded output. End your reply with the single token REFUTED (you found a hole) or CLEAR (you could not)." </dev/null 2>/dev/null)"
  if printf '%s' "$ans" | grep -q 'REFUTED'; then
    printf '{"refuted":true,"findings":%s}\n' "$(printf '%s' "$ans" | head -c 500 | jstr)"
  else
    echo '{"refuted":false,"findings":"reviewer could not refute"}'
  fi
else
  if opencode run --format json "${mdl[@]}" "You are a HeartBeat Stage-B worker. Do EXACTLY this one task, then stop. Work in $(pwd). Never edit .hb/ or gate.sh.

${ctx}" </dev/null >/tmp/hb-exec-opencode.$$.log 2>&1; then
    echo '{"ok":true,"summary":"opencode completed the task"}'
  else
    echo '{"ok":false,"summary":"opencode exited non-zero (see /tmp/hb-exec-opencode.'"$$"'.log)"}'
  fi
fi
