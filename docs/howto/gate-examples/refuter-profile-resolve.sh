#!/usr/bin/env bash
# Proof: the refuter-PROFILE resolver (heartbeat.refuter_profiles / plugin/templates/refuter_profiles.js)
# turns a NAME into a normalized profile dict {persona, questions[], model, provider, verdict}, node ≡ python.
# It proves the three requirements the design turns on:
#   • a NAMED profile in .hb/refuters/<name>.json resolves to its fields;
#   • a built-in `default` is ALWAYS resolvable (so refutation can never fail-open for lack of a profile);
#   • an UNKNOWN EXPLICIT name ERRORS (non-zero) — it never silently degrades to "no review";
# and the precedence that makes it predictable: explicit-name > HB_REFUTER env > project-file > built-in-default,
# with EACH tier (esp. the env default and the project-file shadow of `default`) proven load-bearing.
# node and python must resolve the same input to the same canonical dict (parity oracle).
# Prints REFUTER-RESOLVE-OK. Fails before the resolver exists (spec-first, RED).
#
# `--selftest` swaps the real resolver for a self-contained FAKE (python + node) whose one behaviour is
# mutated per run (drop_persona / noerror / ignore_env / noshadow / badmodel); the full property suite must
# PASS on the un-mutated fake and FAIL on every mutant — so each property is individually load-bearing.
# Prints SELFTEST-OK.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
command -v node    >/dev/null 2>&1 || { echo "node absent";    exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 absent"; exit 1; }

# The resolver under test — overridable so --selftest can point the SAME suite at a fake.
: "${RP_PY_MOD:=heartbeat.refuter_profiles}"
: "${RP_PY_PATH:=$ROOT/py/src}"
: "${RP_NODE_MOD:=$ROOT/plugin/templates/refuter_profiles.js}"
export RP_NODE_MOD

fail() { echo "FAIL: $*" >&2; exit 1; }

# py_resolve <hbdir> <name> [field] -> canonical JSON of the field (or whole dict); non-zero on resolver error
py_resolve() {
  PYTHONPATH="$RP_PY_PATH" python3 - "$RP_PY_MOD" "$@" <<'PY'
import sys, json, importlib
mod, hbdir, name = sys.argv[1], sys.argv[2], sys.argv[3]
field = sys.argv[4] if len(sys.argv) > 4 else ""
m = importlib.import_module(mod)
prof = m.resolve(hbdir, name or None)
val = prof.get(field) if field else prof
print(json.dumps(val, sort_keys=True, separators=(",", ":")))
PY
}

# node_resolve <hbdir> <name> [field] -> canonical JSON matching python's (sorted keys, tight separators)
node_resolve() {
  node -e '
    const m = require(process.env.RP_NODE_MOD);
    const [hbdir, name, field] = process.argv.slice(1);
    const canon = (x) => Array.isArray(x) ? "[" + x.map(canon).join(",") + "]"
      : (x && typeof x === "object") ? "{" + Object.keys(x).sort().map(k => JSON.stringify(k) + ":" + canon(x[k])).join(",") + "}"
      : JSON.stringify(x === undefined ? null : x);
    const p = m.resolve(hbdir, name || null);
    console.log(canon(field ? p[field] : p));
  ' "$1" "$2" "${3:-}"
}

# The full property suite. Returns 0 iff EVERY property holds against the configured resolver.
# Silenced internally; callers decide what an outcome means.
run_suite() {
  local work HB p q m vp dp dpn ep gp sp pj nj pjd njd
  work="$(mktemp -d)" || return 2
  HB="$work/.hb"; mkdir -p "$HB/refuters"
  printf '%s' '{"persona":"SECBOT hunts injection and authz gaps","questions":["q-authz-siblings","q-secret-logged"],"model":"claude-opus-4-8","provider":"anthropic","verdict":{"panel":3,"refute_if":"majority"}}' > "$HB/refuters/security.json"

  # 1) a NAMED profile resolves each field from its file (python)
  p="$(py_resolve "$HB" security persona)"   || { rm -rf "$work"; return 1; }
  case "$p"  in *SECBOT*) : ;; *) rm -rf "$work"; return 1;; esac
  q="$(py_resolve "$HB" security questions)" || { rm -rf "$work"; return 1; }
  case "$q"  in *q-authz-siblings*) : ;; *) rm -rf "$work"; return 1;; esac
  m="$(py_resolve "$HB" security model)"      || { rm -rf "$work"; return 1; }
  [ "$m" = '"claude-opus-4-8"' ]              || { rm -rf "$work"; return 1; }
  vp="$(py_resolve "$HB" security verdict)"   || { rm -rf "$work"; return 1; }
  case "$vp" in *'"panel":3'*) : ;; *) rm -rf "$work"; return 1;; esac

  # 2) built-in `default` is ALWAYS resolvable (no file present), both runtimes, persona non-empty
  dp="$(py_resolve "$HB" default persona)"    || { rm -rf "$work"; return 1; }
  [ -n "$dp" ] && [ "$dp" != '""' ] && [ "$dp" != 'null' ] || { rm -rf "$work"; return 1; }
  dpn="$(node_resolve "$HB" default persona)" || { rm -rf "$work"; return 1; }
  [ -n "$dpn" ] && [ "$dpn" != '""' ] && [ "$dpn" != 'null' ] || { rm -rf "$work"; return 1; }

  # 3) an UNKNOWN EXPLICIT name ERRORS (non-zero) in BOTH runtimes — never a silent no-review
  if py_resolve   "$HB" no-such-xyz persona >/dev/null 2>&1; then rm -rf "$work"; return 1; fi
  if node_resolve "$HB" no-such-xyz persona >/dev/null 2>&1; then rm -rf "$work"; return 1; fi

  # 4a) precedence: HB_REFUTER env supplies the default when no explicit name is given
  ep="$(HB_REFUTER=security py_resolve "$HB" "" persona)" || { rm -rf "$work"; return 1; }
  case "$ep" in *SECBOT*) : ;; *) rm -rf "$work"; return 1;; esac
  # 4b) precedence: an explicit name BEATS the HB_REFUTER env (default wins over security here)
  gp="$(HB_REFUTER=security py_resolve "$HB" default persona)" || { rm -rf "$work"; return 1; }
  case "$gp" in *SECBOT*) rm -rf "$work"; return 1;; esac
  # 4c) precedence: a project .hb/refuters/default.json SHADOWS the built-in default
  printf '%s' '{"persona":"PROJECT-DEFAULT-OVERRIDE marker"}' > "$HB/refuters/default.json"
  sp="$(py_resolve "$HB" default persona)" || { rm -rf "$work"; return 1; }
  case "$sp" in *PROJECT-DEFAULT-OVERRIDE*) : ;; *) rm -rf "$work"; return 1;; esac
  rm -f "$HB/refuters/default.json"

  # 5) PARITY: node ≡ python resolve the same input to the same canonical dict (security AND default)
  pj="$(py_resolve "$HB" security)";  nj="$(node_resolve "$HB" security)"
  [ -n "$pj" ] && [ "$pj" = "$nj" ] || { rm -rf "$work"; return 1; }
  pjd="$(py_resolve "$HB" default)";  njd="$(node_resolve "$HB" default)"
  [ -n "$pjd" ] && [ "$pjd" = "$njd" ] || { rm -rf "$work"; return 1; }

  # 5b) PARITY on MALFORMED-but-valid-JSON fields: hand-written profiles carry mistyped fields
  #     (persona: null, questions: a bare string). Normalization must COERCE identically across
  #     runtimes — else a profile silently means different things in node vs python. Canonical:
  #     a non-string persona -> "", a non-list questions -> [].
  printf '%s' '{"persona":null,"questions":"authz","model":null,"provider":123,"verdict":"lens"}' > "$HB/refuters/malformed.json"
  local pm nm
  pm="$(py_resolve "$HB" malformed)"; nm="$(node_resolve "$HB" malformed)"
  [ -n "$pm" ] && [ "$pm" = "$nm" ] || { rm -rf "$work"; return 1; }
  case "$pm" in *'"persona":""'*) : ;; *) rm -rf "$work"; return 1;; esac
  case "$pm" in *'"questions":[]'*) : ;; *) rm -rf "$work"; return 1;; esac
  rm -f "$HB/refuters/malformed.json"

  rm -rf "$work"; return 0
}

# ── selftest: prove every property is load-bearing via a mutated fake resolver ────────────────────
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT

  # A correct, self-contained fake resolver (python). MUT (env) breaks exactly one behaviour.
  cat > "$d/fake_rp.py" <<'PY'
import os, json
def _builtin(): return {"persona": "generic skeptic baseline", "questions": [], "model": None, "provider": None, "verdict": None}
def _norm(d):
    p = d.get("persona"); q = d.get("questions")
    return {"persona": p if isinstance(p, str) else "", "questions": list(q) if isinstance(q, list) else [],
            "model": d.get("model"), "provider": d.get("provider"), "verdict": d.get("verdict")}
def _norm_div(d):  # the real-world bug: passes null persona through, char-explodes a string questions
    return {"persona": d.get("persona", ""), "questions": list(d.get("questions", []) or []),
            "model": d.get("model"), "provider": d.get("provider"), "verdict": d.get("verdict")}
def resolve(hbdir, name=None):
    mut = os.environ.get("MUT", "none")
    eff = name or (None if mut == "ignore_env" else os.environ.get("HB_REFUTER")) or "default"
    path = os.path.join(hbdir, "refuters", eff + ".json")
    if os.path.exists(path) and not (mut == "noshadow" and eff == "default"):
        prof = (_norm_div if mut == "divnorm" else _norm)(json.load(open(path)))
    elif eff == "default":
        prof = _builtin()
    else:
        if mut == "noerror":
            prof = _builtin()
        else:
            raise ValueError("unknown refuter profile: %s" % eff)
    if mut == "drop_persona": prof["persona"] = ""
    if mut == "badmodel":     prof["model"] = None
    return prof
PY

  # The same fake in node (must match python byte-for-byte for MUT=none so the parity check holds).
  cat > "$d/fake_rp.js" <<'JS'
const fs = require("fs"), path = require("path");
const builtin = () => ({ persona: "generic skeptic baseline", questions: [], model: null, provider: null, verdict: null });
const norm = (d) => ({ persona: typeof d.persona === "string" ? d.persona : "",
  questions: Array.isArray(d.questions) ? d.questions.slice() : [],
  model: d.model === undefined ? null : d.model, provider: d.provider === undefined ? null : d.provider,
  verdict: d.verdict === undefined ? null : d.verdict });
function resolve(hbdir, name) {
  const mut = process.env.MUT || "none";
  const eff = name || (mut === "ignore_env" ? null : process.env.HB_REFUTER) || "default";
  const p = path.join(hbdir, "refuters", eff + ".json");
  let prof;
  if (fs.existsSync(p) && !(mut === "noshadow" && eff === "default")) prof = norm(JSON.parse(fs.readFileSync(p, "utf8")));
  else if (eff === "default") prof = builtin();
  else if (mut === "noerror") prof = builtin();
  else throw new Error("unknown refuter profile: " + eff);
  if (mut === "drop_persona") prof.persona = "";
  if (mut === "badmodel") prof.model = null;
  return prof;
}
module.exports = { resolve };
JS

  export RP_PY_MOD="fake_rp" RP_PY_PATH="$d" RP_NODE_MOD="$d/fake_rp.js"

  # un-mutated fake must satisfy the WHOLE suite (else the fake, not the checks, is wrong)
  MUT=none run_suite || { echo "SELFTEST FAIL: correct fake did not pass the suite" >&2; exit 1; }
  # each mutant breaks ≥1 property → the suite MUST fail (that property's check is load-bearing)
  for mut in drop_persona noerror ignore_env noshadow badmodel divnorm; do
    if MUT="$mut" run_suite; then echo "SELFTEST FAIL: mutant '$mut' slipped past the suite (a check is not load-bearing)" >&2; exit 1; fi
  done
  echo "SELFTEST-OK"
  exit 0
fi

run_suite || fail "resolver property suite did not hold (resolver missing or wrong — expected RED before rs2)"
echo "REFUTER-RESOLVE-OK"
