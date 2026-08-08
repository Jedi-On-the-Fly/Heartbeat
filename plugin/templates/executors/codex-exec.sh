#!/usr/bin/env bash
# HeartBeat executor backend: codex (headless `codex exec` — OpenAI's Claude-Code analog).
# Wire protocol: argv1 = execute|refute ; stdin = payload JSON ; stdout = ONE JSON line.
#   execute → {"ok":bool,"summary":str}   refute → {"refuted":bool,"findings":str}
# Provider: default is the authed one (codex login / OpenAI key); HB_EXEC_PROVIDER=oss uses a
# keyless local model via Ollama. Degrades to protocol-valid JSON if `codex` isn't on PATH.
# NOTE: `codex exec` BLOCKS reading stdin when the prompt is an arg — always run it with </dev/null.
set -uo pipefail

mode="${1:-execute}"
payload="$(cat)"
field() { printf '%s' "$payload" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{process.stdout.write(String((JSON.parse(d)$1)??''))}catch(e){process.stdout.write('')}})"; }
jstr()  { node -pe 'JSON.stringify(require("fs").readFileSync(0,"utf8"))'; }

ctx="$(field .context)"

if ! command -v codex >/dev/null 2>&1; then
  if [ "$mode" = refute ]; then echo '{"refuted":false,"findings":"codex CLI not available — could not run the refuter"}'
  else echo '{"ok":false,"summary":"codex CLI not available"}'; fi
  exit 0
fi

# Build the provider args (authed by default; keyless local with HB_EXEC_PROVIDER=oss).
prov=()
if [ "${HB_EXEC_PROVIDER:-}" = "oss" ]; then
  prov=(--oss --local-provider ollama -m "${HB_EXEC_MODEL:-qwen2.5:7b-instruct}")
fi

if [ "$mode" = refute ]; then
  rp="$(field .prompt)"
  ans="$(codex exec -s workspace-write -C "$(pwd)" --skip-git-repo-check "${prov[@]}" "You are a SKEPTICAL adversarial reviewer for a HeartBeat phase gate.
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
  if codex exec -s workspace-write -C "$(pwd)" --skip-git-repo-check "${prov[@]}" "You are a HeartBeat Stage-B worker. Do EXACTLY this one task, then stop. Work in $(pwd). Never edit .hb/ or gate.sh.

${ctx}" </dev/null >/tmp/hb-exec-codex.$$.log 2>&1; then
    echo '{"ok":true,"summary":"codex completed the task"}'
  else
    echo '{"ok":false,"summary":"codex exited non-zero (see /tmp/hb-exec-codex.'"$$"'.log)"}'
  fi
fi
