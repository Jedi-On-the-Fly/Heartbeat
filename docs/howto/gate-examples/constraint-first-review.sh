#!/usr/bin/env bash
# Proof for "Run a constraint-first review" (docs/howto/constraint-first-review.md): the page's
# fenced ```bash blocks are EXTRACTED and run, in order, on a scratch project (stand-in files play
# the agents' outputs: author.json, refute.md, free.md) — not re-typed — and the gate must end
# ACCEPTED with a recorded gate-time set, a recorded free review and a review_passed carrying answer
# counts. A doc that drifts from the code (a renamed flag, a missing step) fails here.
# Also: the page and the SKILL's plan + review_pending guidance name no vendor MODEL as a
# requirement — a model identifier (opus, sonnet, haiku, gpt-N, gemini, llama, mistral, qwen, or a
# claude-<model> id) may only appear on a line marked as an example ("e.g." / "for example"). A
# harness name ("Claude Code") is not a model and is allowed.
# Prints CONSTRAINT-FIRST-REVIEW-OK. `--selftest` runs the same proof against broken COPIES of the
# page / SKILL (a step removed, a flag renamed, a vendor model required) — each must go RED.
# Prints SELFTEST-OK.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
unset HB_DIR DAG_FILE EVENTS_FILE HB_ACTOR HB_REFUTER 2>/dev/null || true
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }
fail() { echo "FAIL: $*" >&2; exit 1; }
export HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
DOC="${CFR_DOC:-$ROOT/docs/howto/constraint-first-review.md}"
SKILL="${CFR_SKILL:-$ROOT/plugin/skills/heartbeat/SKILL.md}"

# check <doc> <skill> → 0 iff the flow runs and the vendor rule holds; reason on stderr
check() {
  local doc="$1" skill="$2" work p
  work="$(mktemp -d)"; p="$work/proj"; mkdir -p "$p/src"
  bash "$ROOT/plugin/bootstrap.sh" "$p" --no-git >/dev/null 2>&1 </dev/null || { echo "bootstrap failed" >&2; rm -rf "$work"; return 1; }
  cat > "$p/.hb/dag.json" <<'DAG'
{"phases":[{"id":"P_API","title":"upload endpoint","gate_entry":null,"gate_exit":"GATE_API","tasks":[{"id":"api1","title":"write src/upload.py with the 413 limit"}]}],
 "gates":{"GATE_API":{"desc":"the upload endpoint rejects oversize bodies","review":{"profile":"security","prompt":"Refute that the upload endpoint is safe.",
   "constraints":[{"id":"P1","claim":"An upload larger than the limit is rejected with 413","subjects":["src/upload.py"],"violation":"an over-limit upload is stored, or answered with anything but 413"}]},
   "criteria":[{"id":"c","cmd":"grep -q 413 \"$PROJECT_DIR/src/upload.py\""}]}}}
DAG
  mkdir -p "$p/.hb/refuters"
  printf '%s' '{"persona":"You are a SECURITY refuter.","free_review":true}' > "$p/.hb/refuters/security.json"
  ( cd "$p" && node .hb/hb.js rebuild >/dev/null && HB_ACTOR=doer node .hb/hb.js start api1 >/dev/null \
    && printf 'LIMIT = 10\ndef upload(n):\n    return 413 if n > LIMIT else 200\n' > src/upload.py \
    && HB_ACTOR=doer node .hb/hb.js done api1 >/dev/null && bash .hb/gate.sh GATE_API >/dev/null ) \
    || { echo "scenario setup failed (the gate did not pass deterministically)" >&2; rm -rf "$work"; return 1; }
  # stand-ins for the agents' outputs the page tells you to save
  printf '%s' '[{"id":"G1","claim":"upload() returns 200 at exactly the limit","subjects":["src/upload.py"],"violation":"a body of exactly LIMIT is rejected"}]' > "$p/author.json"
  printf 'Refutation attempt on GATE_API / api1: called upload() at, above and below the limit.\n- **P1**: NOT-REPRODUCED — upload(11) returned 413\nG1: NOT-REPRODUCED — upload(10) returned 200\n' > "$p/refute.md"
  printf 'Free review of GATE_API / api1 in src/upload.py: looked for bypasses in breadth; nothing exploitable.\n' > "$p/free.md"
  # the page's bash blocks, in order, verbatim
  python3 - "$doc" > "$work/steps.sh" <<'EOF' || { rm -rf "$work"; return 1; }
import re, sys
blocks = re.findall(r"```bash\n(.*?)```", open(sys.argv[1]).read(), re.S)
if not blocks: sys.exit("no bash blocks in the page")
print("set -e")
print("\n".join(blocks))
EOF
  if ! ( cd "$p" && bash "$work/steps.sh" > "$work/run.log" 2>&1 ); then
    echo "the page's commands failed: $(tail -3 "$work/run.log")" >&2; rm -rf "$work"; return 1
  fi
  python3 - "$p/.hb/events.jsonl" <<'EOF' || { rm -rf "$work"; return 1; }
import json, sys
evs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
kinds = [e.get("event") for e in evs if e.get("gate") == "GATE_API"]
for need in ("constraints_recorded", "free_review_recorded", "review_passed"):
    if need not in kinds: sys.exit("after the page's steps there is no " + need)
rp = [e for e in evs if e.get("event") == "review_passed"][-1]
if rp.get("answers") != {"violated": 0, "not_reproduced": 2, "na": 0}: sys.exit("the pass carries no enforced answers: " + json.dumps(rp.get("answers")))
cr = [e for e in evs if e.get("event") == "constraints_recorded"][-1]
if cr.get("actor") == "doer": sys.exit("the page lets the doer author the constraints")
EOF
  rm -rf "$work"
  # vendor-model rule on the page + the SKILL's plan and review_pending guidance
  python3 - "$doc" "$skill" <<'EOF' || return 1
import re, sys
doc, skill = open(sys.argv[1]).read(), open(sys.argv[2]).read()
MODEL = re.compile(r"(?i)\b(opus|sonnet|haiku|gpt-?[0-9][\w.-]*|gemini|llama|mistral|qwen[\w.-]*|claude-[a-z0-9][\w.-]*)\b")
def sections(text):
    out = []
    m = re.search(r"(?ms)^### `/heartbeat plan.*?(?=^### )", text)
    if m: out.append(m.group(0))
    out += [l for l in text.splitlines() if "review_pending" in l]
    return "\n".join(out)
for name, text in (("the how-to", doc), ("SKILL plan/review_pending", sections(skill))):
    for line in text.splitlines():
        if MODEL.search(line) and "e.g." not in line and "for example" not in line.lower():
            sys.exit(name + " names a vendor model as a requirement: " + line.strip()[:160])
EOF
  return 0
}

if [ "${1:-}" = "--selftest" ]; then
  check "$DOC" "$SKILL" 2>/dev/null || fail "selftest needs a green baseline"
  w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
  mut() { # <label> <python transform of the text> <which: doc|skill>
    local d="$w/doc.md" s="$w/skill.md"; cp "$DOC" "$d"; cp "$SKILL" "$s"
    local tgt="$d"; [ "$3" = skill ] && tgt="$s"
    python3 -c "import sys; p=sys.argv[1]; t=open(p).read(); exec(sys.argv[2]); open(p,'w').write(t)" "$tgt" "$2" || fail "selftest: mutation '$1' could not be applied"
    if check "$d" "$s" 2>/dev/null; then fail "selftest: '$1' still passes — not load-bearing"; fi
    echo "  caught: $1"
  }
  mut "the --record step removed"        't = t.replace("HB_ACTOR=author-agent node .hb/hb.js constraints GATE_API --record author.json --model author-model", "true")' doc
  mut "a flag renamed (--artifact → --file)" 't = t.replace("review GATE_API pass --artifact refute.md", "review GATE_API pass --file refute.md")' doc
  mut "the free review step removed"     't = t.replace("HB_ACTOR=free-agent node .hb/hb.js review GATE_API free --artifact free.md --model free-model", "true")' doc
  mut "the doer authors the constraints" 't = t.replace("HB_ACTOR=author-agent", "HB_ACTOR=doer")' doc
  mut "the page requires a vendor model" 't = t.replace("- **The author and security gates**", "- **The author and security gates** — use opus-4.")' doc
  mut "the SKILL review step requires one" 't = t.replace("review_pending", "review_pending (use gpt-5)", 1)' skill
  echo "SELFTEST-OK"; exit 0
fi

check "$DOC" "$SKILL" || fail "the constraint-first review how-to does not hold"
echo "the page's commands run end to end; no vendor model required"
echo "CONSTRAINT-FIRST-REVIEW-OK"
