#!/usr/bin/env bash
# Proof for "The auditor catches each weakness — and doesn't cry wolf": every rule hb-audit
# can emit fires on a minimal must-trip DAG, and a clean DAG trips none. The rule set is
# DERIVED from the auditor source (not a hardcoded copy) so a newly added rule with no
# fixture fails this check. Prints AUDIT-RULES-PROVEN:<n> only when all hold.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
AUD="$ROOT/plugin/templates/hb-audit.js"
command -v node >/dev/null 2>&1 || { echo "node absent"; exit 1; }
fail(){ echo "FAIL: $1"; exit 1; }

rules_of(){ node "$AUD" "$1" --json 2>/dev/null | node -pe 'JSON.parse(require("fs").readFileSync(0)).findings.map(x=>x.rule).join(" ")'; }

# A minimal DAG that MUST trip the named rule.
gen(){ case "$1" in
  unguarded_phase) echo '{"phases":[{"id":"P","tasks":[{"id":"T","title":"x"}]}],"gates":{}}';;
  ungated)         echo '{"phases":[{"id":"P","gate_exit":"G","tasks":[{"id":"T","title":"x"}]}],"gates":{"G":{"criteria":[]}}}';;
  hollow_gate)     echo '{"phases":[{"id":"P","gate_exit":"G","tasks":[{"id":"T","title":"x"}]}],"gates":{"G":{"criteria":[{"id":"c","cmd":"true"}]}}}';;
  vacuous)         echo '{"phases":[{"id":"P","gate_exit":"G","tasks":[{"id":"T","title":"x"}]}],"gates":{"G":{"criteria":[{"id":"c","cmd":"true"}]}}}';;
  existence)       echo '{"phases":[{"id":"P","gate_exit":"G","tasks":[{"id":"T","title":"make out.txt"}]}],"gates":{"G":{"criteria":[{"id":"c","cmd":"test -f \"$PROJECT_DIR/out.txt\""}]}}}';;
  nondeterministic)echo '{"phases":[{"id":"P","gate_exit":"G","tasks":[{"id":"T","title":"x"}]}],"gates":{"G":{"criteria":[{"id":"c","cmd":"[ $((RANDOM % 2)) -eq 0 ]"}]}}}';;
  side_effecting)  echo '{"phases":[{"id":"P","gate_exit":"G","tasks":[{"id":"T","title":"make out.txt"}]}],"gates":{"G":{"criteria":[{"id":"c","cmd":"echo ok > \"$PROJECT_DIR/out.txt\"; grep -q ok \"$PROJECT_DIR/out.txt\""}]}}}';;
  gate_offphase)   echo '{"phases":[{"id":"P","gate_exit":"G","tasks":[{"id":"T","title":"x"}]}],"gates":{"G":{"criteria":[{"id":"c","cmd":"grep -q ok \"$PROJECT_DIR/orphan.txt\""}]}}}';;
  *) echo "";;
esac; }

# Derive the rule set the auditor can emit: string-literal rules from F(...) calls plus the
# classify() return values (vacuous/existence), minus the non-finding 'behavioral'.
rules="$( { grep -oE "F\('[a-z]+', *'[a-z0-9_]+'" "$AUD" | grep -oE "'[a-z0-9_]+'$" | tr -d "'";
            grep -oE "return '[a-z0-9_]+'" "$AUD" | grep -oE "'[a-z0-9_]+'" | tr -d "'"; } \
          | sort -u | grep -v '^behavioral$' )"
[ -n "$rules" ] || fail "could not derive any rules from the auditor source"

n=0
for r in $rules; do
  dag="$(gen "$r")"
  [ -n "$dag" ] || fail "auditor emits rule '$r' but this check has no fixture for it (add one)"
  f="$(mktemp)"; printf '%s' "$dag" > "$f"
  got="$(rules_of "$f")"; rm -f "$f"
  case " $got " in *" $r "*) n=$((n + 1));; *) fail "fixture for '$r' did not trip it (got: $got)";; esac
done

# No cry wolf: a clean, behavioral DAG trips none of the rules.
clean="$(mktemp)"
printf '%s' '{"phases":[{"id":"P","gate_exit":"G","tasks":[{"id":"T","title":"write out.txt"}]}],"gates":{"G":{"criteria":[{"id":"c","cmd":"grep -q ok \"$PROJECT_DIR/out.txt\""}]}}}' > "$clean"
cgot="$(rules_of "$clean")"; rm -f "$clean"
for r in $rules; do case " $cgot " in *" $r "*) fail "clean DAG wrongly tripped '$r' (cry wolf): $cgot";; esac; done

echo "AUDIT-RULES-PROVEN:$n (every auditor rule fires on a must-trip DAG; a clean DAG trips none)."
