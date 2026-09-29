#!/usr/bin/env bash
# HeartBeat executor backend: opencode (headless `opencode run` — SST's provider-agnostic agent).
# Wire protocol: argv1 = execute|refute|author ; stdin = payload JSON ; stdout = ONE JSON line.
#   execute → {"ok":bool,"summary":str}   refute → {"refuted":bool,"findings":str}
# Model via HB_EXEC_MODEL (-m provider/model, e.g. ollama/qwen2.5:7b-instruct). Degrades to
# protocol-valid JSON if `opencode` isn't on PATH.
# Autonomy + isolation, by feature (not version): when `opencode run --help` advertises them, execute and
# refute pass --auto (else a permission "ask" blocks with no TTY) and every mode passes --standalone (else
# v2 attaches to a background service whose cwd/config may not be the project's). An older CLI without
# them needs opencode.json `permission: allow`. The prompt travels as an argv message, so </dev/null.
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
# The reviewer's verdict (twin of _verdict in the python adapters): read from the reply's LAST non-empty
# line by an exact grammar — (A) only the verdict (optional bullet/markup, optional "Verdict:" label, the
# token, optional "."/"!") or (B) a finished sentence or a "verdict:" label then the token as the final
# word; no verdict line just before it; a bare line not glued to an unfinished sentence. Else nothing.
verdict_of() { node -e 'const t=require("fs").readFileSync(0,"utf8");const A=/^[ \t]*(?:(?:[-*+]|[0-9]+[.)])[ \t]+)?[ \t*_\x60]*(?:(?:[Ff]inal[ \t]+)?(?:[Vv]erdict|VERDICT)[ \t*_\x60]*[:\u2014\u2013-])?[ \t*_\x60"\x27\u201c\u201d]*(REFUTED|CLEAR)[ \t*_\x60"\x27\u201c\u201d.!]*$/;const B=/^([^\n]*[A-Za-z][^\n]*(?:[.!?][)"\x27\u201d*_\x60]*|(?:[Vv]erdict|VERDICT)[ \t*_\x60]*[:\u2014\u2013-]))[ \t]+[*_\x60"\x27\u201c]*(REFUTED|CLEAR)[*_\x60"\x27\u201d.!]*[ \t]*$/;const L=t.split("\n").map(l=>l.replace(/[ \t\r]+$/,""));while(L.length&&!L[L.length-1])L.pop();let v="";if(L.length){let m=L[L.length-1].match(A);const bare=!!m;let ok=true;if(!m){m=L[L.length-1].match(B);if(!m||A.test(m[1].split(/(?<=[.!?])[ \t]+/).pop()))ok=false;}if(ok){let k=L.length-2;while(k>=0&&!L[k])k--;if(k>=0){const p=L[k];if(A.test(p)||B.test(p))ok=false;else if(bare&&k===L.length-2&&!(/^[ \t]*#/.test(p)||/[.!?:)\]]["\x27\u201d*_\x60]*$/.test(p)))ok=false;}}if(ok)v=m[m.length-1];}process.stdout.write(v)'; }
field() { printf '%s' "$payload" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{process.stdout.write(String((JSON.parse(d)$1)??''))}catch(e){process.stdout.write('')}})"; }
jstr()  { node -pe 'JSON.stringify(require("fs").readFileSync(0,"utf8"))'; }
# the model's own words in a --format json event stream: its "text" parts, in order — never a tool's
# output (a file the reviewer read or a grep hit may contain REFUTED/CLEAR)
texts() { node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{const o=[];for(const l of d.split("\n")){let e;try{e=JSON.parse(l)}catch(x){continue}const p=(e&&e.part)||{};if(e.type==="text"&&p.type==="text"&&typeof p.text==="string")o.push(p.text)}process.stdout.write(o.join("\n"))})'; }

ctx="$(field .context)"

if ! command -v opencode >/dev/null 2>&1; then
  if [ "$mode" = author ]; then echo '{"ok":false,"error":"opencode CLI not available — could not run the constraint author"}'
  elif [ "$mode" = refute ]; then echo '{"error":"opencode CLI not available — could not run the refuter"}'
  else echo '{"ok":false,"summary":"opencode CLI not available"}'; fi
  exit 0
fi

mdl=()
if [ -n "${HB_EXEC_MODEL:-}" ]; then mdl=(-m "${HB_EXEC_MODEL}"); fi
ochelp="$(opencode run --help 2>&1 </dev/null)"
case "$ochelp" in *--standalone*) mdl+=(--standalone);; esac
run_auto=()
case "$ochelp" in *--auto*) run_auto=(--auto);; esac

# The gate-time constraint AUTHOR: a read-only model call whose reply must carry a JSON array.
if [ "$mode" = author ]; then
  opencode run ${mdl[@]+"${mdl[@]}"} "$(field .prompt)" </dev/null 2>/dev/null | author_json
  exit 0
fi

if [ "$mode" = refute ]; then
  rp="$(field .prompt)"
  ans="$(opencode run --format json ${mdl[@]+"${mdl[@]}"} ${run_auto[@]+"${run_auto[@]}"} "You are a SKEPTICAL adversarial reviewer for a HeartBeat phase gate.
${rp}

Context:
${ctx}

Do not modify files. Hunt for a real hole: a hollow test, a criterion not truly met, a faked or hard-coded output. End your reply with the single token REFUTED (you found a hole) or CLEAR (you could not)." </dev/null 2>/dev/null | texts)"
  verdict="$(printf '%s' "$ans" | verdict_of)"
  if [ "$verdict" = REFUTED ]; then
    printf '{"refuted":true,"findings":%s}\n' "$(printf '%s' "$ans" | head -c 20000 | jstr)"
  elif [ "$verdict" = CLEAR ]; then
    printf '{"refuted":false,"findings":%s}\n' "$(printf '%s' "$ans" | head -c 20000 | jstr)"
  else
    # no final REFUTED/CLEAR token (the CLI failed, or the reviewer never concluded): NOT a CLEAR —
    # an error, which the driver escalates (fail-closed)
    printf '{"error":%s}\n' "$(printf 'no REFUTED/CLEAR verdict in the reviewer reply (fail-closed): %s' "$(printf '%s' "$ans" | head -c 300)" | jstr)"
  fi
else
  if opencode run --format json ${mdl[@]+"${mdl[@]}"} ${run_auto[@]+"${run_auto[@]}"} "You are a HeartBeat Stage-B worker. Do EXACTLY this one task, then stop. Work in $(pwd). Never edit .hb/ or gate.sh.

${ctx}" </dev/null >/tmp/hb-exec-opencode.$$.log 2>&1; then
    echo '{"ok":true,"summary":"opencode completed the task"}'
  else
    echo '{"ok":false,"summary":"opencode exited non-zero (see /tmp/hb-exec-opencode.'"$$"'.log)"}'
  fi
fi
