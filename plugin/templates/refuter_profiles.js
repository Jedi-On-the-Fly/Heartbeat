'use strict';
// Refuter profiles — resolve a NAME into a normalized adversarial-review profile.
// Node twin of py/src/heartbeat/refuter_profiles.py: the two MUST resolve identical input to the
// identical normalized dict (parity oracle: docs/howto/gate-examples/refuter-profile-resolve.sh).
// PURE resolution: name -> {persona, questions[], model, provider, verdict}. No dispatch changes.
const fs = require('fs');
const path = require('path');

// The built-in `default` persona — MUST stay byte-for-byte identical to DEFAULT_PERSONA in the
// python twin (parity compares the resolved dict).
const DEFAULT_PERSONA =
  "You are a skeptical adversarial reviewer for a HeartBeat phase gate. Try to REFUTE that the " +
  "phase is truly complete: hollow tests, criteria not really met, faked or stubbed outputs, the " +
  "wrong behaviour asserted. Cite concrete evidence from the phase. End with REFUTED or CLEAR.";

function builtinDefault() {
  return { persona: DEFAULT_PERSONA, questions: [], model: null, provider: null, verdict: null };
}

// Fill the full profile shape from a partial definition — same keys in both runtimes AND coerce
// mistyped fields identically to python (a non-string persona or a non-list `questions` from
// hand-written JSON must not diverge — parity contract).
function normalize(d) {
  return {
    persona: typeof d.persona === "string" ? d.persona : "",
    questions: Array.isArray(d.questions) ? d.questions.slice() : [],
    model: d.model !== undefined ? d.model : null,
    provider: d.provider !== undefined ? d.provider : null,
    verdict: d.verdict !== undefined ? d.verdict : null,
  };
}

// Ordered profile directories — first match wins; project profiles SHADOW shipped ones. RL inserts
// the shipped plugin/templates/refuters/ dir after this.
function searchDirs(hbdir) {
  return [path.join(hbdir, "refuters")];
}

function loadFromDirs(hbdir, name) {
  for (const d of searchDirs(hbdir)) {
    const p = path.join(d, name + ".json");
    if (fs.existsSync(p) && fs.statSync(p).isFile()) return JSON.parse(fs.readFileSync(p, "utf8"));
  }
  return null;
}

function loadFromExecutor(hbdir, name) {
  const ep = path.join(hbdir, "executor.json");
  if (fs.existsSync(ep)) {
    let refs = {};
    try { refs = (JSON.parse(fs.readFileSync(ep, "utf8")) || {}).refuters || {}; } catch (e) { refs = {}; }
    if (Object.prototype.hasOwnProperty.call(refs, name)) return refs[name];
  }
  return null;
}

// Precedence for WHICH name: explicit name > HB_REFUTER env > "default". Precedence for WHERE a name
// resolves: project files > executor.json inline > built-in default. Unknown explicit name throws.
function resolve(hbdir, name) {
  const eff = name || process.env.HB_REFUTER || "default";
  let raw = loadFromDirs(hbdir, eff);
  if (raw === null) raw = loadFromExecutor(hbdir, eff);
  if (raw !== null) return normalize(raw);
  if (eff === "default") return builtinDefault();
  throw new Error(
    "unknown refuter profile: '" + eff + "' — no .hb/refuters/" + eff + ".json, no executor.json " +
    "entry, and it is not the built-in 'default'"
  );
}

module.exports = { resolve, DEFAULT_PERSONA, searchDirs, normalize };
