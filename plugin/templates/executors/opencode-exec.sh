#!/usr/bin/env bash
# HeartBeat executor backend: opencode (headless `opencode run` — SST's provider-agnostic agent).
# Wire protocol: argv1 = execute|refute|author ; stdin = payload JSON ; stdout = ONE JSON line.
#   execute → {"ok":bool,"summary":str}   refute → {"refuted":bool,"findings":str}
# Model via HB_EXEC_MODEL (-m provider/model, e.g. ollama/qwen2.5:7b-instruct). Degrades to
# protocol-valid JSON if `opencode` isn't on PATH.
# Autonomy: opencode's `run` blocks on an "ask" permission with no TTY — configure opencode.json
# `permission: allow` for unattended use (0.15.3 has no --auto). The prompt travels as an argv
# message, so we run with </dev/null defensively.
set -uo pipefail

mode="${1:-execute}"
payload="$(cat)"
case "$mode" in execute|refute|author) ;; *)
  printf '{"error":%s}\n' "$(printf 'unsupported mode %s (execute | refute | author)' "$mode" | node -pe 'JSON.stringify(require("fs").readFileSync(0,"utf8"))')"; exit 0;; esac
author_json() { node -e '
let t="";process.stdin.on("data",c=>t+=c).on("end",()=>{
  const cands=[...t.matchAll(/```(?:json)?\s*(\[[\s\S]*?\])\s*```/g)].map(m=>m[1]);
  const op=[],cl=[];for(let k=0;k<t.length;k++){if(t[k]==="[")op.push(k);else if(t[k]==="]")cl.push(k);}
  for(const i of op.slice(0,50))for(const j of cl.slice(-50))if(j>i)cands.push(t.slice(i,j+1));
  for(const c of cands){ try{ const v=JSON.parse(c); if(Array.isArray(v)&&v.length&&v.every(x=>x&&typeof x==="object"&&!Array.isArray(x))){ process.stdout.write(JSON.stringify({ok:true,constraints:v})+"\n"); return; } }catch(e){} }
  process.stdout.write(JSON.stringify({ok:false,error:"no JSON array of constraints in the author reply: "+t.slice(0,200)})+"\n");
});'; }
field() { printf '%s' "$payload" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{process.stdout.write(String((JSON.parse(d)$1)??''))}catch(e){process.stdout.write('')}})"; }
jstr()  { node -pe 'JSON.stringify(require("fs").readFileSync(0,"utf8"))'; }

ctx="$(field .context)"

if ! command -v opencode >/dev/null 2>&1; then
  if [ "$mode" = author ]; then echo '{"ok":false,"error":"opencode CLI not available — could not run the constraint author"}'
  elif [ "$mode" = refute ]; then echo '{"error":"opencode CLI not available — could not run the refuter"}'
  else echo '{"ok":false,"summary":"opencode CLI not available"}'; fi
  exit 0
fi

mdl=()
if [ -n "${HB_EXEC_MODEL:-}" ]; then mdl=(-m "${HB_EXEC_MODEL}"); fi

# The gate-time constraint AUTHOR: a read-only model call whose reply must carry a JSON array.
if [ "$mode" = author ]; then
  opencode run ${mdl[@]+"${mdl[@]}"} "$(field .prompt)" </dev/null 2>/dev/null | author_json
  exit 0
fi

if [ "$mode" = refute ]; then
  rp="$(field .prompt)"
  ans="$(opencode run --format json ${mdl[@]+"${mdl[@]}"} "You are a SKEPTICAL adversarial reviewer for a HeartBeat phase gate.
${rp}

Context:
${ctx}

Do not modify files. Hunt for a real hole: a hollow test, a criterion not truly met, a faked or hard-coded output. End your reply with the single token REFUTED (you found a hole) or CLEAR (you could not)." </dev/null 2>/dev/null)"
  verdict="$(printf '%s' "$ans" | tr '[:lower:]' '[:upper:]' | grep -oE 'REFUTED|CLEAR' | tail -1)"
  if [ "$verdict" = REFUTED ]; then
    printf '{"refuted":true,"findings":%s}\n' "$(printf '%s' "$ans" | head -c 20000 | jstr)"
  else
    printf '{"refuted":false,"findings":%s}\n' "$(printf '%s' "$ans" | head -c 20000 | jstr)"
  fi
else
  if opencode run --format json ${mdl[@]+"${mdl[@]}"} "You are a HeartBeat Stage-B worker. Do EXACTLY this one task, then stop. Work in $(pwd). Never edit .hb/ or gate.sh.

${ctx}" </dev/null >/tmp/hb-exec-opencode.$$.log 2>&1; then
    echo '{"ok":true,"summary":"opencode completed the task"}'
  else
    echo '{"ok":false,"summary":"opencode exited non-zero (see /tmp/hb-exec-opencode.'"$$"'.log)"}'
  fi
fi
