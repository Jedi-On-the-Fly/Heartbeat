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

// `hb refuters new` starter template — byte-identical to the python twin (TEMPLATE_* in refuter_profiles.py).
const TEMPLATE_DESC = "Refute that a phase is truly complete. A starting point — tailor the persona and " +
  "checklist below to your domain's real failure classes.";
const TEMPLATE_PERSONA = "You are a refuter for a HeartBeat phase gate. Name the concrete ways this phase's " +
  "work could be wrong or incomplete, and hunt each one — a generic \"looks fine\" review is exactly what " +
  "lets real defects through. Cite specific evidence from the phase. End with REFUTED or CLEAR.";
const TEMPLATE_QUESTIONS = [
  "What is the single most likely way this phase's work is wrong or incomplete?",
  "Which claim or output has no evidence actually backing it?",
];

// Serialize a profile to canonical SKILL.md text (python twin: render_skill). Byte-identical.
function renderSkill(name, description, profile) {
  const lines = ["---", "name: " + name, "description: " + description];
  if (profile.model) lines.push("model: " + profile.model);
  if (profile.provider) lines.push("provider: " + profile.provider);
  if (profile.author_model) lines.push("author_model: " + profile.author_model);
  const v = profile.verdict || {};
  if (v.panel) {
    lines.push("panel: " + String(v.panel));
    lines.push("refute_if: " + (v.refute_if || "majority"));
  }
  lines.push("---");
  lines.push(profile.persona || "");
  lines.push("");
  lines.push("## Checklist");
  for (const q of (profile.questions || [])) lines.push("- " + q);
  return lines.join("\n") + "\n";
}

// Create a new refuter — <name>/SKILL.md folder (default) or <name>.md (lite). No-clobber across ALL
// formats; a name with a path separator is rejected. Returns the written path.
function scaffold(hbdir, name, opts) {
  opts = opts || {};
  if (!name || name === "." || name === ".." || name.includes("/") || name.includes("\\")) {
    throw new Error("invalid refuter name '" + name + "' — must be a plain name (no path separator, not '.'/'..')");
  }
  const refdir = path.join(hbdir, "refuters");
  if (fs.existsSync(path.join(refdir, name + ".json")) || fs.existsSync(path.join(refdir, name + ".md")) ||
      fs.existsSync(path.join(refdir, name, "SKILL.md"))) {
    throw new Error("refuter '" + name + "' already exists — refusing to overwrite");
  }
  let profile, description;
  if (opts.from) {
    profile = resolve(hbdir, opts.from);
    description = "Refute a phase using the '" + opts.from + "' lens.";
  } else {
    profile = { persona: TEMPLATE_PERSONA, questions: TEMPLATE_QUESTIONS.slice(), model: null, provider: null, verdict: null };
    description = TEMPLATE_DESC;
  }
  const text = renderSkill(name, description, profile);
  let p;
  if (opts.lite) { fs.mkdirSync(refdir, { recursive: true }); p = path.join(refdir, name + ".md"); }
  else { fs.mkdirSync(path.join(refdir, name), { recursive: true }); p = path.join(refdir, name, "SKILL.md"); }
  fs.writeFileSync(p, text);
  return p;
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
    author_model: d.author_model !== undefined ? d.author_model : null,
  };
}

// Ordered profile directories — first match wins; project profiles SHADOW shipped ones. RL inserts
// the shipped plugin/templates/refuters/ dir after this.
function searchDirs(hbdir) {
  return [path.join(hbdir, "refuters")];
}

// Parse an agent-SKILL-format refuter (frontmatter + persona body + `## Checklist`) into a raw profile
// dict. Python twin: parse_skill. SHARED minimal line-parser (NOT YAML) so node ≡ python.
function parseSkill(text) {
  let lines = text.split("\n");
  if (lines.length && lines[0][0] === "﻿") lines[0] = lines[0].slice(1);
  lines = lines.map(l => l.endsWith("\r") ? l.slice(0, -1) : l);
  const fm = {};
  let bodyStart = 0;
  if (lines.length && lines[0].trim() === "---") {
    let close = null;
    for (let i = 1; i < lines.length; i++) if (lines[i].trim() === "---") { close = i; break; }
    if (close !== null) {
      for (const l of lines.slice(1, close)) {
        if (l.trim() === "" || !l.includes(":")) continue;
        const ci = l.indexOf(":");
        const k = l.slice(0, ci).trim().toLowerCase();
        let v = l.slice(ci + 1).trim();
        if (v.length >= 2 && v[0] === v[v.length - 1] && (v[0] === '"' || v[0] === "'")) v = v.slice(1, -1);
        fm[k] = v;
      }
      bodyStart = close + 1;
    }
  }
  const bl = lines.slice(bodyStart);
  let idx = null;
  for (let i = 0; i < bl.length; i++) if (bl[i].trim().toLowerCase() === "## checklist") { idx = i; break; }
  let persona, questions = [];
  if (idx === null) { persona = bl.join("\n").trim(); }
  else {
    persona = bl.slice(0, idx).join("\n").trim();
    for (const l of bl.slice(idx + 1)) {
      const ls = l.trim();
      if (ls.startsWith("## ")) break;
      if (ls[0] === "-" || ls[0] === "*") questions.push(ls.slice(1).trim());
    }
  }
  let verdict = null;
  if ("panel" in fm) {
    const pv = fm.panel;
    const digits = pv.startsWith("-") ? pv.slice(1) : pv;
    if (!digits || ![...digits].every(c => c >= "0" && c <= "9")) {
      throw new Error("invalid panel value: '" + pv + "' — must be an integer");
    }
    if (BigInt(pv) > 9007199254740991n || BigInt(pv) < -9007199254740991n) {  // MAX_SAFE_INTEGER — parseInt == python int
      throw new Error("panel value out of range: '" + pv + "'");
    }
    verdict = { panel: parseInt(pv, 10), refute_if: fm.refute_if || "majority" };
  }
  return { persona, questions, model: fm.model === undefined ? null : fm.model,
           provider: fm.provider === undefined ? null : fm.provider, verdict,
           author_model: fm.author_model === undefined ? null : fm.author_model };
}

function loadFromDirs(hbdir, name) {
  for (const d of searchDirs(hbdir)) {
    const cands = [];
    const jp = path.join(d, name + ".json");
    const mp = path.join(d, name + ".md");
    const sp = path.join(d, name, "SKILL.md");
    if (fs.existsSync(jp) && fs.statSync(jp).isFile()) cands.push(["json", jp]);
    if (fs.existsSync(mp) && fs.statSync(mp).isFile()) cands.push(["md", mp]);
    if (fs.existsSync(sp) && fs.statSync(sp).isFile()) cands.push(["skill", sp]);
    if (cands.length > 1) {
      throw new Error("refuter '" + name + "' is defined in multiple formats in " + d + " (" +
        cands.map(c => c[0]).join(", ") + ") — remove all but one");
    }
    if (cands.length) {
      const [kind, p] = cands[0];
      const text = fs.readFileSync(p, "utf8");
      return kind === "json" ? JSON.parse(text) : parseSkill(text);
    }
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
  if (eff === "." || eff === ".." || eff.includes("/") || eff.includes("\\")) {
    throw new Error("invalid refuter profile name '" + eff + "' — must be a plain name (no path separator, not '.'/'..')");
  }
  let raw = loadFromDirs(hbdir, eff);
  if (raw === null) raw = loadFromExecutor(hbdir, eff);
  if (raw !== null) return normalize(raw);
  if (eff === "default") return builtinDefault();
  throw new Error(
    "unknown refuter profile: '" + eff + "' — no .hb/refuters/" + eff + ".json, no executor.json " +
    "entry, and it is not the built-in 'default'"
  );
}

// The ONE refute-prompt compose, shared by every refute surface (python twin: compose_prompt).
// No profile selected (no gate review.profile AND no HB_REFUTER) ⇒ EXACTLY today's prompt
// (byte-unchanged for existing projects). Otherwise: persona + BASE review_questions + the profile's
// EXTRA questions (APPENDED, never replacing the base) + review.prompt. Unknown explicit profile
// throws (via resolve) — the caller must fail closed.
// Aggregate a panel of boolean refute verdicts (python twin: aggregate_verdict). majority ⇒ refuted
// iff >N/2; any ⇒ iff ≥1; all ⇒ iff every panelist refuted.
function aggregateVerdict(verdicts, rule) {
  const t = verdicts.filter(Boolean).length, n = verdicts.length;
  if (rule === "any") return t >= 1;
  if (rule === "all") return n > 0 && t === n;
  return 2 * t > n;
}

// The profile a gate's review selects, or null when NONE is (no review.profile and no HB_REFUTER) —
// the backward-compat signal. Throws (via resolve) on an unknown explicit name.
function gateProfile(hbdir, review) {
  const name = (review || {}).profile;
  if (!name && !process.env.HB_REFUTER) return null;
  return resolve(hbdir, name || null);
}

function composePrompt(hbdir, dag, gate) {
  const g = (((dag || {}).gates) || {})[gate] || {};
  const review = g.review || {};
  const prompt = review.prompt || ("Refute that " + gate + " is truly complete.");
  const prof = gateProfile(hbdir, review);
  if (prof === null) return prompt;
  const { reviewQuestions } = require('./hb-audit.js');
  const parts = [];
  if (prof.persona) parts.push(prof.persona);
  parts.push(reviewQuestions(dag, gate).replace(/\n+$/, ""));
  const extra = prof.questions || [];
  if (extra.length) parts.push("Domain checks from the refuter profile:\n" + extra.map(q => "  - " + q).join("\n"));
  parts.push(prompt);
  return parts.join("\n\n");
}

module.exports = { resolve, composePrompt, gateProfile, aggregateVerdict, parseSkill, renderSkill, scaffold, DEFAULT_PERSONA, searchDirs, normalize };
