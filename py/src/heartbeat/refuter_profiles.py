"""Refuter profiles — resolve a NAME into a normalized adversarial-review profile.

A profile is a named bundle {persona, questions[], model, provider, verdict} that a gate or a
project selects instead of re-writing free-text refute prompts. This module is PURE resolution:
name -> profile dict. Composition of the actual refute prompt lives at the dispatch site (see
`hb refute-prompt`); dispatch/cross-model wiring is unchanged.

Node twin: plugin/templates/refuter_profiles.js — the two MUST resolve identical input to the
identical normalized dict (parity oracle: docs/howto/gate-examples/refuter-profile-resolve.sh).
"""
import os
import json

# The built-in `default` persona — a generic skeptic. Opt-in (name it / HB_REFUTER=default): the
# no-profile automated path stays byte-identical to today (see refute-prompt), so this never changes
# existing behaviour. MUST stay byte-for-byte identical to DEFAULT_PERSONA in the node twin.
DEFAULT_PERSONA = (
    "You are a skeptical adversarial reviewer for a HeartBeat phase gate. Try to REFUTE that the "
    "phase is truly complete: hollow tests, criteria not really met, faked or stubbed outputs, the "
    "wrong behaviour asserted. Cite concrete evidence from the phase. End with REFUTED or CLEAR."
)


def _builtin_default():
    return {"persona": DEFAULT_PERSONA, "questions": [], "model": None, "provider": None, "verdict": None}


# The `hb refuters new` starter template (no --from). Skill-creator ethos: imperative, name the
# concrete failure classes, explain WHY — no rigid MUSTs, no placeholders. Kept byte-identical to the
# node twin so scaffolded output matches across runtimes.
TEMPLATE_DESC = ("Refute that a phase is truly complete. A starting point — tailor the persona and "
                 "checklist below to your domain's real failure classes.")
TEMPLATE_PERSONA = ("You are a refuter for a HeartBeat phase gate. Name the concrete ways this phase's "
                    "work could be wrong or incomplete, and hunt each one — a generic \"looks fine\" "
                    "review is exactly what lets real defects through. Cite specific evidence from the "
                    "phase. End with REFUTED or CLEAR.")
TEMPLATE_QUESTIONS = [
    "What is the single most likely way this phase's work is wrong or incomplete?",
    "Which claim or output has no evidence actually backing it?",
]


def render_skill(name, description, profile):
    """Serialize a profile to canonical SKILL.md text (node twin: renderSkill). Byte-identical across
    runtimes — the parity surface `hb refuters new` relies on."""
    lines = ["---", "name: " + name, "description: " + description]
    if profile.get("model"):
        lines.append("model: " + profile["model"])
    if profile.get("provider"):
        lines.append("provider: " + profile["provider"])
    if profile.get("author_model"):
        lines.append("author_model: " + profile["author_model"])
    v = profile.get("verdict") or {}
    if v.get("panel"):
        lines.append("panel: " + str(v["panel"]))
        lines.append("refute_if: " + (v.get("refute_if") or "majority"))
    lines.append("---")
    lines.append(profile.get("persona") or "")
    lines.append("")
    lines.append("## Checklist")
    for q in (profile.get("questions") or []):
        lines.append("- " + q)
    return "\n".join(lines) + "\n"


def scaffold(hbdir, name, from_=None, lite=False):
    """Create a new refuter under .hb/refuters/ — a canonical `<name>/SKILL.md` folder (default) or a
    lite `<name>.md` (lite=True). --from resolves a starter as the template. No-clobber across ALL
    formats; a name with a path separator is rejected. Returns the written path."""
    if not name or name in (".", "..") or "/" in name or "\\" in name or os.sep in name:
        raise ValueError("invalid refuter name %r — must be a plain name (no path separator, not '.'/'..')" % name)
    refdir = os.path.join(hbdir, "refuters")
    if (os.path.exists(os.path.join(refdir, name + ".json")) or
            os.path.exists(os.path.join(refdir, name + ".md")) or
            os.path.exists(os.path.join(refdir, name, "SKILL.md"))):
        raise ValueError("refuter %r already exists — refusing to overwrite" % name)
    if from_:
        profile = resolve(hbdir, from_)
        description = "Refute a phase using the '%s' lens." % from_
    else:
        profile = {"persona": TEMPLATE_PERSONA, "questions": list(TEMPLATE_QUESTIONS),
                   "model": None, "provider": None, "verdict": None}
        description = TEMPLATE_DESC
    text = render_skill(name, description, profile)
    if lite:
        path = os.path.join(refdir, name + ".md")
        os.makedirs(refdir, exist_ok=True)
    else:
        os.makedirs(os.path.join(refdir, name), exist_ok=True)
        path = os.path.join(refdir, name, "SKILL.md")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    return path


def _normalize(d):
    """Fill the full profile shape from a partial file/inline definition — so every profile (and
    both runtimes) return the same keys AND coerce mistyped fields identically (a non-string persona
    or a non-list `questions` from hand-written JSON must not diverge node vs python)."""
    persona = d.get("persona")
    questions = d.get("questions")
    return {
        "persona": persona if isinstance(persona, str) else "",
        "questions": list(questions) if isinstance(questions, list) else [],
        "model": d.get("model"),
        "provider": d.get("provider"),
        "verdict": d.get("verdict"),
        "author_model": d.get("author_model"),
    }


def search_dirs(hbdir):
    """Ordered profile directories — first match wins. Project profiles come first so they SHADOW
    shipped ones; RL inserts the shipped `plugin/templates/refuters/` dir after this."""
    return [os.path.join(hbdir, "refuters")]


def parse_skill(text):
    """Parse an agent-SKILL-format refuter (frontmatter + persona body + `## Checklist`) into a raw
    profile dict. Node twin: parseSkill. A SHARED minimal line-parser — NOT YAML — so node ≡ python:
    split frontmatter on the FIRST `:`, trim key (case-insensitive) + value, strip one surrounding
    quote layer, ignore blank lines, last-duplicate-key wins, tolerate BOM/CRLF; persona = body before
    a case-insensitive `## Checklist`; questions = the `-`/`*` bullets after it; panel → verdict."""
    lines = text.split("\n")
    if lines and lines[0][:1] == "﻿":
        lines[0] = lines[0][1:]
    lines = [l[:-1] if l.endswith("\r") else l for l in lines]
    fm = {}
    body_start = 0
    if lines and lines[0].strip() == "---":
        close = None
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                close = i
                break
        if close is not None:
            for l in lines[1:close]:
                if l.strip() == "" or ":" not in l:
                    continue
                k, _, v = l.partition(":")
                k = k.strip().lower()
                v = v.strip()
                if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                    v = v[1:-1]
                fm[k] = v
            body_start = close + 1
    body = "\n".join(lines[body_start:])
    bl = body.split("\n")
    idx = None
    for i, l in enumerate(bl):
        if l.strip().lower() == "## checklist":
            idx = i
            break
    if idx is None:
        persona, questions = body.strip(), []
    else:
        persona = "\n".join(bl[:idx]).strip()
        questions = []
        for l in bl[idx + 1:]:
            ls = l.strip()
            if ls.startswith("## "):
                break
            if ls[:1] in ("-", "*"):
                questions.append(ls[1:].strip())
    verdict = None
    if "panel" in fm:
        pv = fm["panel"]
        digits = pv[1:] if pv.startswith("-") else pv
        if not digits or not all("0" <= c <= "9" for c in digits):
            raise ValueError("invalid panel value: %r — must be an integer" % pv)
        iv = int(pv)
        if abs(iv) > 9007199254740991:  # MAX_SAFE_INTEGER — so node parseInt == python int (parity)
            raise ValueError("panel value out of range: %r" % pv)
        verdict = {"panel": iv, "refute_if": fm.get("refute_if", "majority")}
    return {"persona": persona, "questions": questions, "model": fm.get("model"),
            "provider": fm.get("provider"), "verdict": verdict, "author_model": fm.get("author_model")}


def _load_from_dirs(hbdir, name):
    for d in search_dirs(hbdir):
        cands = []
        jp = os.path.join(d, name + ".json")
        mp = os.path.join(d, name + ".md")
        sp = os.path.join(d, name, "SKILL.md")
        if os.path.isfile(jp):
            cands.append(("json", jp))
        if os.path.isfile(mp):
            cands.append(("md", mp))
        if os.path.isfile(sp):
            cands.append(("skill", sp))
        if len(cands) > 1:
            raise ValueError("refuter %r is defined in multiple formats in %s (%s) — remove all but one"
                             % (name, d, ", ".join(c[0] for c in cands)))
        if cands:
            kind, path = cands[0]
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
            return json.loads(text) if kind == "json" else parse_skill(text)
    return None


def _load_from_executor(hbdir, name):
    """Optional inline definitions under executor.json {"refuters": {name: {...}}}."""
    ep = os.path.join(hbdir, "executor.json")
    if os.path.isfile(ep):
        try:
            refs = (json.load(open(ep, encoding="utf-8")) or {}).get("refuters") or {}
        except (ValueError, OSError):
            refs = {}
        if name in refs:
            return refs[name]
    return None


def aggregate_verdict(verdicts, rule):
    """Aggregate a panel of boolean refute verdicts (node twin: aggregateVerdict). majority ⇒ refuted
    iff >N/2; any ⇒ iff ≥1; all ⇒ iff every panelist refuted."""
    t = sum(1 for v in verdicts if v)
    n = len(verdicts)
    if rule == "any":
        return t >= 1
    if rule == "all":
        return n > 0 and t == n
    return 2 * t > n


def gate_profile(hbdir, review):
    """The profile a gate's review selects, or None when NONE is selected (no `review.profile` and no
    HB_REFUTER) — the backward-compat signal. Raises (via resolve) on an unknown explicit name."""
    name = (review or {}).get("profile")
    if not name and not os.environ.get("HB_REFUTER"):
        return None
    return resolve(hbdir, name)


def compose_prompt(hbdir, dag, gate):
    """The ONE refute-prompt compose, shared by every refute surface (node twin: composePrompt).

    No profile selected ⇒ EXACTLY today's prompt (review.prompt, or the fallback) — existing projects
    are byte-unchanged. Otherwise: persona + the gate's BASE review_questions + the profile's EXTRA
    questions (APPENDED, never replacing the base) + review.prompt. An unknown explicit profile raises
    — the caller must fail closed, never skip the review.
    """
    from . import audit
    g = ((dag or {}).get("gates") or {}).get(gate) or {}
    review = g.get("review") or {}
    prompt = review.get("prompt") or ("Refute that %s is truly complete." % gate)
    prof = gate_profile(hbdir, review)
    if prof is None:
        return prompt
    parts = []
    if prof.get("persona"):
        parts.append(prof["persona"])
    parts.append(audit.review_questions(dag, gate).rstrip("\n"))
    extra = prof.get("questions") or []
    if extra:
        parts.append("Domain checks from the refuter profile:\n" + "\n".join("  - " + q for q in extra))
    parts.append(prompt)
    return "\n\n".join(parts)


def resolve(hbdir, name=None):
    """Resolve a profile name to a normalized dict.

    Precedence for WHICH name: explicit `name` (a gate's review.profile) > HB_REFUTER env > `default`.
    Precedence for WHERE a name resolves: project files (search_dirs) > executor.json inline >
    built-in `default`. An unknown EXPLICIT name errors — it never silently degrades to no-review.
    """
    eff = name or os.environ.get("HB_REFUTER") or "default"
    if eff in (".", "..") or "/" in eff or "\\" in eff or os.sep in eff:
        raise ValueError("invalid refuter profile name %r — must be a plain name (no path separator, not '.'/'..')" % eff)
    raw = _load_from_dirs(hbdir, eff)
    if raw is None:
        raw = _load_from_executor(hbdir, eff)
    if raw is not None:
        return _normalize(raw)
    if eff == "default":
        return _builtin_default()
    raise ValueError(
        "unknown refuter profile: %r — no .hb/refuters/%s.json, no executor.json entry, and it is "
        "not the built-in 'default'" % (eff, eff)
    )
