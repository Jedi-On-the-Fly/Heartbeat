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
    }


def search_dirs(hbdir):
    """Ordered profile directories — first match wins. Project profiles come first so they SHADOW
    shipped ones; RL inserts the shipped `plugin/templates/refuters/` dir after this."""
    return [os.path.join(hbdir, "refuters")]


def _load_from_dirs(hbdir, name):
    for d in search_dirs(hbdir):
        p = os.path.join(d, name + ".json")
        if os.path.isfile(p):
            with open(p, encoding="utf-8") as fh:
                return json.load(fh)
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
