#!/usr/bin/env bash
# Runs inside the framework image. Drives the REAL framework backend (HB_EXEC_BACKEND, set at
# build) through the REAL HeartBeat adapter + driver + gate, against the host's Ollama
# (--network host). Verifies the WIRING: did the framework produce output the behavioral gate
# can evaluate? Emits a machine-readable LIVE: line. The strict pass depends on model
# capability — this proves the path runs end to end, not that a given local model always wins.
set -u
fw="${HB_EXEC_BACKEND:-?}"
model="${HB_EXEC_MODEL:-qwen2.5:7b-instruct}"
ver="$(pip show "${fw%%-*}" 2>/dev/null | awk '/^Version:/{print $2}')"
[ -z "$ver" ] && ver="$(pip freeze 2>/dev/null | grep -iE "^${fw%%-*}==" | head -1 | cut -d= -f3)"

hb(){ python3 -m heartbeat.cli "$@"; }
p="$(mktemp -d)"
hb init "$p" >/dev/null 2>&1
python3 - "$p/.hb/dag.json" <<'PY'
import json, sys
json.dump({"phases":[{"id":"P0","gate_entry":None,"gate_exit":"GATE_P0",
                      "tasks":[{"id":"T1","title":"Create greeting.py defining greet(name) returning \"Hello, <name>!\" so greet(\"Ada\")==\"Hello, Ada!\""}]}],
           "gates":{"GATE_P0":{"desc":"greet works",
                     "criteria":[
                       {"id":"structural","cmd":"python3 -c \"import ast; ast.parse(open('$PROJECT_DIR/greeting.py').read())\""},
                       {"id":"behavioral","cmd":"cd \"$PROJECT_DIR\" && python3 -c \"import greeting,sys; sys.exit(0 if greeting.greet('Ada')=='Hello, Ada!' else 1)\""}]}}},
          open(sys.argv[1],"w"))
PY
hb rebuild --dir "$p" >/dev/null 2>&1

# Drive the real framework backend for one task, then evaluate the gate criteria directly.
HB_EXEC_MAX_ITERS=6 hb exec run --dir "$p" >/tmp/exec.log 2>&1 || true

produced=false; struct=false; behav=false
[ -f "$p/greeting.py" ] && produced=true
python3 -c "import ast; ast.parse(open('$p/greeting.py').read())" 2>/dev/null && struct=true
( cd "$p" && python3 -c "import greeting,sys; sys.exit(0 if greeting.greet('Ada')=='Hello, Ada!' else 1)" ) 2>/dev/null && behav=true

if $behav; then verdict="phase-complete (strict gate passed)"
elif $struct; then verdict="wiring-ok, strict gate missed (model-luck)"
elif $produced; then verdict="wiring-ok, output not valid python (model-luck)"
else verdict="no output (model/degrade)"; fi

echo "LIVE:$fw version=$ver model=$model produced=$produced structural=$struct behavioral=$behav"
echo "VERDICT:$fw: $verdict"
rm -rf "$p"
