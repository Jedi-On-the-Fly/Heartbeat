#!/usr/bin/env bash
# HeartBeat executor backend: codex (headless `codex exec` — OpenAI's Claude-Code analog).
# Wire protocol: argv1 = execute|refute|author ; stdin = payload JSON ; stdout = ONE JSON line.
#   execute → {"ok":bool,"summary":str}   refute → {"refuted":bool,"findings":str}
# Provider: default is the authed one (codex login / OpenAI key); HB_EXEC_PROVIDER=oss uses a
# keyless local model via Ollama. Degrades to protocol-valid JSON if `codex` isn't on PATH.
# NOTE: `codex exec` BLOCKS reading stdin when the prompt is an arg — always run it with </dev/null.
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
# The reviewer's verdict (twin of _verdict in the python adapters; contract: py/tests/verdict_cases.json):
# the reply's last non-empty line is ONLY the verdict (optional markup, optional "Verdict:" label, the
# token, optional "."/"!") and the line before it neither begins with a verdict token nor ends with one after a separator. Else nothing.
verdict_of() { node -e 'const t=require("fs").readFileSync(0,"utf8");const A=/^[ \t]*[*_\x60]*(?:(?:[Ff]inal[ \t]+)?(?:[Vv]erdict|VERDICT)[*_\x60]*[ \t]*[:\u2014\u2013-][ \t*_\x60]*)?["\x27\u201c\u201d]?(REFUTED|CLEAR)["\x27\u201c\u201d]?[*_\x60]*[.!]?[*_\x60]*[ \t]*$/;const P=/^[ \t]*(?:(?:[-*+]|[0-9]+[.)])[ \t]+)?[ \t*_\x60]*(?:(?:[Ff]inal[ \t]+)?(?:[Vv]erdict|VERDICT)[*_\x60]*[ \t]*[:\u2014\u2013-][ \t*_\x60]*)?["\x27\u201c\u201d]?(?:REFUTED|CLEAR)(?![A-Za-z0-9_])/;const L=t.split("\n").map(l=>l.replace(/[ \t\r]+$/,""));while(L.length&&!L[L.length-1])L.pop();const m=L.length?L[L.length-1].match(A):null;let v="";if(m){let k=L.length-2;while(k>=0&&!L[k])k--;if(!(k>=0&&(P.test(L[k])||/(?:^|[.!?:;|\/\u2014\u2013-])[ \t*_\x60"\x27\u201c\u201d]*(?:REFUTED|CLEAR)["\x27\u201c\u201d*_\x60.!?:;)\]]*[ \t]*$/.test(L[k]))))v=m[1];}process.stdout.write(v)'; }
field() { printf '%s' "$payload" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{process.stdout.write(String((JSON.parse(d)$1)??''))}catch(e){process.stdout.write('')}})"; }
jstr()  { node -pe 'JSON.stringify(require("fs").readFileSync(0,"utf8"))'; }

ctx="$(field .context)"

if ! command -v codex >/dev/null 2>&1; then
  if [ "$mode" = author ]; then echo '{"ok":false,"error":"codex CLI not available — could not run the constraint author"}'
  elif [ "$mode" = refute ]; then echo '{"error":"codex CLI not available — could not run the refuter"}'
  else echo '{"ok":false,"summary":"codex CLI not available"}'; fi
  exit 0
fi

# Build the provider args (authed by default; keyless local with HB_EXEC_PROVIDER=oss).
prov=()
if [ "${HB_EXEC_PROVIDER:-}" = "oss" ]; then
  prov=(--oss --local-provider ollama -m "${HB_EXEC_MODEL:-qwen2.5:7b-instruct}")
elif [ -n "${HB_EXEC_MODEL:-}" ]; then
  prov=(-m "${HB_EXEC_MODEL}")   # per-role models: the recorded model must be the model that ran
fi
# Network is an explicit opt-in: the workspace-write sandbox has none — not even loopback, so a refuter
# cannot exercise a local server. HB_CODEX_NETWORK=1 (only "1") opens it for execute and refute; the
# constraint author stays read-only. It opens the sandbox's network generally, not just loopback.
net=()
if [ "${HB_CODEX_NETWORK:-}" = "1" ]; then net=(-c sandbox_workspace_write.network_access=true); fi

# The gate-time constraint AUTHOR: a read-only model call whose reply must carry a JSON array.
if [ "$mode" = author ]; then
  codex exec -s read-only -C "$(pwd)" --skip-git-repo-check ${prov[@]+"${prov[@]}"} "$(field .prompt)" </dev/null 2>/dev/null | author_json
  exit 0
fi

if [ "$mode" = refute ]; then
  rp="$(field .prompt)"
  ans="$(codex exec -s workspace-write -C "$(pwd)" --skip-git-repo-check ${net[@]+"${net[@]}"} ${prov[@]+"${prov[@]}"} "You are a SKEPTICAL adversarial reviewer for a HeartBeat phase gate.
${rp}

Context:
${ctx}

Do not modify files. Hunt for a real hole: a hollow test, a criterion not truly met, a faked or hard-coded output. End your reply with a final line containing only the verdict, REFUTED if you found a hole or CLEAR if you could not, with nothing else on that line." </dev/null 2>/dev/null)"
  verdict="$(printf '%s' "$ans" | verdict_of)"
  if [ "$verdict" = REFUTED ]; then
    printf '{"refuted":true,"findings":%s}\n' "$(printf '%s' "$ans" | head -c 20000 | jstr)"
  elif [ "$verdict" = CLEAR ]; then
    printf '{"refuted":false,"findings":%s}\n' "$(printf '%s' "$ans" | head -c 20000 | jstr)"
  else
    # no final REFUTED/CLEAR token (the CLI failed, or the reviewer never concluded): NOT a CLEAR —
    # an error, which the driver escalates (fail-closed)
    printf '{"error":%s}\n' "$(printf 'no verdict line at the end of the reviewer reply (fail-closed); the reply ends: %s' "$(printf '%s' "$ans" | tail -c 300)" | jstr)"
  fi
else
  if codex exec -s workspace-write -C "$(pwd)" --skip-git-repo-check ${net[@]+"${net[@]}"} ${prov[@]+"${prov[@]}"} "You are a HeartBeat Stage-B worker. Do EXACTLY this one task, then stop. Work in $(pwd). Never edit .hb/ or gate.sh.

${ctx}" </dev/null >/tmp/hb-exec-codex.$$.log 2>&1; then
    echo '{"ok":true,"summary":"codex completed the task"}'
  else
    echo '{"ok":false,"summary":"codex exited non-zero (see /tmp/hb-exec-codex.'"$$"'.log)"}'
  fi
fi
