"""Static DAG validation — ported from the node hb-lint.js with the same rules."""
import json
import re

PLACEHOLDER_MARKERS = [
    "Implement feature A", "Implement feature B",
    "Description of what this task produces.",
    "Create all required directories and config files.",
    "Check that all required tools and dependencies are available.",
    "Verify A and B work together correctly.",
    "output/result.json",
]


# ── The shape contract ─────────────────────────────────────────────────────────────────────
# STRUCTURE is what every reader dereferences: the schema nodes annotated "x-hb-structure" in
# plugin/dag.schema.json. A violation is ONE path-named error, identical bytes on both runtimes,
# and the other rules then run on a view with the malformed parts dropped — on a structure-valid
# dag the view IS the dag (every existing message unchanged). Twin: hb-lint.js.
def _is_obj(x):
    return isinstance(x, dict)


def _valid_id(x):
    return isinstance(x, str) and len(x) > 0


def _shown(v):
    """A rendered value in a message: a string quoted, anything else by its JSON type (twin: shown)."""
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if v is None:
        return "null"
    if isinstance(v, list):
        return "a list"
    if isinstance(v, dict):
        return "an object"
    if isinstance(v, bool):
        return "a boolean"
    return "a number"


def _type_name(c):
    """The offending value named by its JSON TYPE, never rendered (twin: hb-lint.js typeName)."""
    if c is None:
        return "null"
    if isinstance(c, list):
        return "a list"
    if isinstance(c, str):
        return "a string"
    if isinstance(c, bool):
        return "a boolean"
    if isinstance(c, (int, float)):
        return "a number"
    return "an object whose cmd is not a string"


_MAX_DEPTH = 256


def _too_deep(text):
    """Nesting bounded BEFORE parsing, over the text itself (twin: hb-lint.js tooDeep)."""
    depth, in_str, esc = 0, False, False
    for c in text:
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            continue
        if c == '"':
            in_str = True
        elif c in "[{":
            depth += 1
            if depth > _MAX_DEPTH:
                return True
        elif c in "]}":
            depth -= 1
    return False


def _js_order(d):
    """Keys in JS object order: canonical array-index keys ascending first, then insertion order —
    node cannot see insertion order for integer-like keys, so python adopts node's."""
    idx = [k for k in d if isinstance(k, str) and (k == "0" or (k[:1] in "123456789" and k.isdigit() and k.isascii())) and int(k) < 4294967295]
    return sorted(idx, key=int) + [k for k in d if k not in idx]


def _has_surrogate(v):
    if isinstance(v, str):
        return any("\ud800" <= ch <= "\udfff" for ch in v)
    if isinstance(v, list):
        return any(_has_surrogate(x) for x in v)
    if isinstance(v, dict):
        return any(_has_surrogate(k) or _has_surrogate(x) for k, x in v.items())
    return False


def _reject_constant(name):
    raise ValueError(name)


def _parse_int(s):
    # JS reads every number as a double; python's int() also REFUSES literals over 4300 digits
    # (CPython's str-digits limit) — a giant literal must get node's verdict, not a parse error
    return float(s) if len(s) > 4000 else int(s)


def read_dag_file(path):
    """The checked FILE read — never a silent empty plan. Returns (dag, error) with fixed bytes per
    class (twin: hb-lint.js readDagFile): strict UTF-8, no NaN/Infinity, no lone surrogates."""
    from pathlib import Path
    try:
        raw = Path(path).read_bytes()
    except FileNotFoundError:
        return None, "dag.json unreadable: missing"
    except OSError:
        return None, "dag.json unreadable: cannot be read"
    if not raw.strip(b" \t\n\r"):
        return None, "dag.json unreadable: empty"
    try:
        text = raw.decode("utf-8")
    except Exception:
        return None, "dag.json unreadable: not valid JSON"
    if _too_deep(text):
        return None, "dag.json unreadable: nested too deeply"
    try:
        dag = json.loads(text, parse_constant=_reject_constant, parse_int=_parse_int)
    except Exception:
        return None, "dag.json unreadable: not valid JSON"
    if _has_surrogate(dag):
        return None, "dag.json unreadable: not valid JSON"
    if not isinstance(dag, dict):
        return None, "dag.json unreadable: top level is not an object"
    return dag, None


def shape_errors(dag, entries=False):
    """entries: also report non-object criteria entries. Every caller passes True (lint, audit,
    every reader) — one walk, one order. Twin: hb-lint.js shapeErrors."""
    if not _is_obj(dag):
        return ["dag.json unreadable: top level is not an object"]
    e = []
    if "phases" not in dag:
        e.append("phases: missing")
    elif not isinstance(dag["phases"], list):
        e.append("phases must be a list")
    else:
        for i, p in enumerate(dag["phases"]):
            at = f"phases[{i}]"
            if not _is_obj(p):
                e.append(f"{at} must be an object")
                continue
            if "id" not in p:
                e.append(f"{at}.id: missing")
            elif not _valid_id(p["id"]):
                e.append(f"{at}.id must be a non-empty string")
            for k in ("gate_entry", "gate_exit"):
                if k in p and p[k] is not None and not isinstance(p[k], str):
                    e.append(f"{at}.{k} must be a string or null")
            if "parked" in p and not isinstance(p["parked"], bool):
                e.append(f"{at}.parked must be true or false")
            if "tasks" not in p:
                continue
            if not isinstance(p["tasks"], list):
                e.append(f"{at}.tasks must be a list")
                continue
            for j, t in enumerate(p["tasks"]):
                ta = f"{at}.tasks[{j}]"
                if not _is_obj(t):
                    e.append(f"{ta} must be an object")
                    continue
                if "id" not in t:
                    e.append(f"{ta}.id: missing")
                elif not _valid_id(t["id"]):
                    e.append(f"{ta}.id must be a non-empty string")
                if "requires" not in t:
                    continue
                if not isinstance(t["requires"], list):
                    e.append(f"{ta}.requires must be a list")
                    continue
                for k, r in enumerate(t["requires"]):
                    if not isinstance(r, str):
                        e.append(f"{ta}.requires[{k}] must be a string")
    if "gates" not in dag:
        e.append("gates: missing")
    elif not _is_obj(dag["gates"]):
        e.append("gates must be an object")
    else:
        for g in _js_order(dag["gates"]):
            gv = dag["gates"][g]
            if not _is_obj(gv):
                e.append(f"gates.{g} must be an object")
                continue
            if "criteria" in gv and not isinstance(gv["criteria"], list):
                e.append(f"gates.{g}.criteria must be a list")
            elif entries and isinstance(gv.get("criteria"), list):
                for i, c in enumerate(gv["criteria"]):
                    if not isinstance(c, dict):
                        e.append(f"[{g}] criteria entry {i} must be an object with a string cmd "
                                 f"(got {_type_name(c)})")
    return e


def structure_view(dag):
    """The rules' view: malformed containers, wrong-typed references/items and invalid-id tasks
    dropped; _ntasks keeps the ORIGINAL task count for the >8 warning (twin: structureView)."""
    phases = []
    for p in (dag.get("phases") if isinstance(dag.get("phases"), list) else []):
        if not _is_obj(p):
            continue
        q = dict(p)
        for k in ("gate_entry", "gate_exit"):
            if k in q and q[k] is not None and not isinstance(q[k], str):
                q[k] = None
        if "parked" in q and not isinstance(q["parked"], bool):
            q.pop("parked")  # truthiness splits the runtimes on []/{}
        q["_ntasks"] = len(p["tasks"]) if isinstance(p.get("tasks"), list) else 0
        if "tasks" in p:
            ts = []
            for t in (p["tasks"] if isinstance(p["tasks"], list) else []):
                if not (_is_obj(t) and _valid_id(t.get("id"))):
                    continue
                if "requires" in t:
                    t = dict(t, requires=[r for r in (t["requires"] if isinstance(t["requires"], list) else []) if isinstance(r, str)])
                ts.append(t)
            q["tasks"] = ts
        phases.append(q)
    gates = {}
    if _is_obj(dag.get("gates")):
        for g in _js_order(dag["gates"]):
            gv = dag["gates"][g]
            if not _is_obj(gv):
                continue
            gates[g] = dict(gv, criteria=[]) if ("criteria" in gv and not isinstance(gv["criteria"], list)) else gv
    return dict(dag, phases=phases, gates=gates)


def lint(dag):
    if not _is_obj(dag):
        return {"errors": ["dag.json unreadable: top level is not an object"], "warnings": []}
    errors, warnings = [], []
    errors.extend(shape_errors(dag, True))  # shape-guard: lint — entries mode: the readers' order, one walk
    raw = dag
    dag = structure_view(dag)
    gates = dag.get("gates") or {}
    phases = dag.get("phases") or []
    task_ids, task_map = {}, {}   # insertion-ordered like JS Set: a hash-ordered set made the cycle text vary run to run
    phase_ids = set()

    for p in phases:
        # A duplicate phase id silently MERGES two phases in the projection — the append-time
        # mistake (replanning adds phases to a dag whose ids are already taken). Same bar as tasks.
        # Scoped to non-empty STRING ids so both runtimes classify degenerate shapes (missing id,
        # None, numbers) identically — a refuter catch: p["id"] crashed on an id-less phase.
        pid = p.get("id")
        pid_s = pid if isinstance(pid, str) and pid else "?"   # degenerate ids render '?' on BOTH runtimes (a refuter catch: p['id'] crashed here)
        if isinstance(pid, str) and pid:
            if pid in phase_ids:
                errors.append(f"duplicate phase ID: {pid}")
            phase_ids.add(pid)
        tasks = p.get("tasks") or []
        if p["_ntasks"] > 8:
            warnings.append(f"[{pid_s}] {p['_ntasks']} tasks (>8) — context-loss risk, consider sub-phases")
        # The knowledge-horizon marker is a strict boolean; its POSITION is never linted (a flag left
        # on a no-longer-last phase after an append is historical and inert, by design).
        if "horizon" in p and not isinstance(p["horizon"], bool):
            errors.append(f"[{pid_s}] horizon must be true or false (the knowledge-horizon marker)")
        for t in tasks:
            if t["id"] in task_ids:
                errors.append(f"duplicate task ID: {t['id']}")
            task_ids[t["id"]] = True
            task_map[t["id"]] = t
        for g in (p.get("gate_entry"), p.get("gate_exit")):
            if g and g not in gates:
                errors.append(f"[{pid_s}] undefined gate: {g}")
        if p.get("gate_entry") and not any(q.get("gate_exit") == p["gate_entry"] for q in phases):
            errors.append(f"[{pid_s}] gate_entry {p['gate_entry']} is no phase's gate_exit — phase locked forever")

    for tid in task_ids:
        for r in (task_map[tid].get("requires") or []):
            if r not in task_ids:
                errors.append(f"[{tid}] requires a non-existent task: {r}")

    color, stack = {}, []

    def dfs(tid):
        color[tid] = 1
        stack.append(tid)
        for r in (task_map.get(tid, {}).get("requires") or []):
            if r not in task_map:
                continue
            if color.get(r) == 1:
                idx = stack.index(r)
                errors.append("dependency cycle: " + " → ".join(stack[idx:] + [r]))
                continue
            if not color.get(r):
                dfs(r)
        stack.pop()
        color[tid] = 2

    for tid in task_ids:
        if not color.get(tid):
            dfs(tid)

    for g in gates:
        if not any(p.get("gate_entry") == g or p.get("gate_exit") == g for p in phases):
            warnings.append(f"gate defined but never referenced: {g}")
        # Criteria SHAPE is lint's to own: every entry must be an object with a string cmd — the
        # runners eval cmd and every static reader walks these entries, so garbage here crashed
        # doctor/audit on both runtimes (a refuter catch). Loud, identical bytes across runtimes.
        gv = gates[g] if isinstance(gates[g], dict) else {}
        for i, c in enumerate(gv.get("criteria") or []):
            if isinstance(c, dict) and not isinstance(c.get("cmd"), str):  # a non-object entry is STRUCTURE (the shape layer)
                errors.append(f"[{g}] criteria entry {i} must be an object with a string cmd "
                              f"(got {_type_name(c)})")

    _check_placeholders(raw, warnings)
    _check_gate_artifacts(dag, warnings)
    _check_constraints(dag, errors)
    _check_regate(dag, errors)   # regate-guard
    _check_detach(dag, errors)   # detach-guard
    return {"errors": errors, "warnings": warnings}


# "Non-blank" with ONE explicit whitespace set — str.strip() and JS trim() disagree on \ufeff /
# \x1c-\x1f / \x85, and the two lints must return identical errors (twin: blankFree).
_ASCII_WS = " \t\n\r\f\v"


def _check_regate(dag, errors):
    """A gate's regate record (written by `hb regate`, honored by every evaluation/acceptance
    path): {at?, reason, actor, prev_criteria, pending, rearm?}. A malformed record must ERROR
    on BOTH lints — a shape the runtimes read permissively would let a hand-mangled marker
    silently disarm the fail-closed perimeter. Twin: hb-lint.js checkRegate (messages verbatim)."""
    def _blank_free(s):
        return isinstance(s, str) and bool(s.strip(_ASCII_WS))
    for g, gv in (dag.get("gates") or {}).items():
        if "regate" not in (gv or {}):
            continue
        r = gv["regate"]
        if not isinstance(r, dict) or not r:
            errors.append(f"[{g}] regate must be a non-empty object ({{at?, reason, actor, prev_criteria, pending, rearm?}})")
            continue
        if not isinstance(r.get("pending"), bool):
            errors.append(f"[{g}] regate.pending must be true or false")
        if not _blank_free(r.get("reason")):
            errors.append(f"[{g}] regate.reason must be a non-empty string (why the premises changed)")
        if not _blank_free(r.get("actor")):
            errors.append(f"[{g}] regate.actor must be a non-empty string (who declared the revision)")
        if not isinstance(r.get("prev_criteria"), list):
            errors.append(f"[{g}] regate.prev_criteria must be a list (the criteria snapshot at declare time)")
        if "at" in r and not _blank_free(r.get("at")):
            errors.append(f"[{g}] regate.at must be a non-empty string timestamp")
        if "rearm" in r:
            w = r["rearm"]
            if not isinstance(w, dict) or not all(_blank_free(w.get(k)) for k in ("actor", "artifact", "sha256")):
                errors.append(f"[{g}] regate.rearm must be an object with non-empty actor, artifact and sha256 strings")


_DETACH_SAFE_ID = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.-]*")


def _check_detach(dag, errors):
    """A phase's detach record (written by `hb detach`): the four fields together, gate_entry null
    while they stand, detached_from a defined gate that is some phase's gate_exit (a bare 'defined'
    restore would re-create the 'phase locked forever' resolver brick), the phase id usable as an
    anchor file name, and gate ids matching ^_start$ / ^_detach_ RESERVED for the anchors
    namespace. Twin: hb-lint.js checkDetach (messages verbatim)."""
    def _blank_free(s):
        return isinstance(s, str) and bool(s.strip(_ASCII_WS))
    gates = dag.get("gates") or {}
    for g in gates:
        # exact equality + prefix, NOT a regex: re.match's $ matches before a trailing newline and
        # JS's does not, so the twin regexes diverged on a gate named "_start\n" (a refuter fuzz catch)
        if g == "_start" or str(g).startswith("_detach_"):
            errors.append(f"[{g}] gate ids matching ^_start$ or ^_detach_ are reserved for the anchors namespace — rename the gate")
    exits = {p.get("gate_exit") for p in (dag.get("phases") or []) if p.get("gate_exit")}
    fields = ["detached_from", "detached_reason", "detached_by", "detached_at"]
    for p in (dag.get("phases") or []):
        if not _valid_id(p.get("id")):
            continue  # an invalid id is the structure layer's to report (no '[undefined]'/'[None]' split)
        has = [k for k in fields if k in p]
        if not has:
            continue
        if len(has) < len(fields):
            errors.append(f"[{p.get('id')}] detach fields are partial ({', '.join(has)}) — a detach records detached_from, detached_reason, detached_by and detached_at together")
            continue
        if p.get("gate_entry") is not None:
            errors.append(f"[{p.get('id')}] detach fields alongside a non-null gate_entry — a half-reattach; reattach properly or clear the fields")
        if not _blank_free(p.get("detached_from")) or p.get("detached_from") not in gates or p.get("detached_from") not in exits:
            errors.append(f"[{p.get('id')}] detached_from must name a defined gate that is some phase's gate_exit (got {_shown(p.get('detached_from'))})")
        if not _blank_free(p.get("detached_reason")):
            errors.append(f"[{p.get('id')}] detached_reason must be a non-empty string")
        if not _blank_free(p.get("detached_by")):
            errors.append(f"[{p.get('id')}] detached_by must be a non-empty string")
        if not _blank_free(p.get("detached_at")):
            errors.append(f"[{p.get('id')}] detached_at must be a non-empty string timestamp")
        if not isinstance(p.get("id"), str) or not _DETACH_SAFE_ID.fullmatch(p["id"]):
            errors.append(f"[{p.get('id')}] a detached phase id must be usable as an anchor file name ([A-Za-z0-9_][A-Za-z0-9_.-]*)")


def _check_constraints(dag, errors):
    """Plan-time constraints of a gate's adversarial review: gates.<G>.review.constraints =
    [{id P<n>, claim, subjects:[…], violation}]. G<n> ids are reserved for the constraints
    authored at review time. Twin: hb-lint.js checkConstraints (messages verbatim)."""
    gates = dag.get("gates") or {}
    for g in gates:
        gv = gates[g] if isinstance(gates[g], dict) else {}
        if "constraints" in gv:
            errors.append(f"[{g}] constraints belong in review.constraints (the plan-time constraints of the gate's adversarial review)")
        rv = gv.get("review")
        # A review must be a NON-EMPTY dict: python's bool() and node's truthiness disagree on {} / [],
        # so any other shape would make the runtimes disagree on whether the gate owes a review.
        if rv is not None and (not isinstance(rv, dict) or not rv):
            errors.append(f"[{g}] review must be a non-empty object ({{prompt, profile?, constraints?}})")
        if not isinstance(rv, dict) or "constraints" not in rv:
            continue
        cs = rv["constraints"]
        if not isinstance(cs, list):
            errors.append(f"[{g}] review.constraints must be a list of {{id, claim, subjects, violation}}")
            continue
        for m in constraint_errors(cs, "P"):
            errors.append(f"[{g}] {m}")


_CONSTRAINT_ID_RULE = {
    "P": "id must be P<n> (plan-time; G<n> ids are reserved for gate-time constraints)",
    "G": "id must be G<n> (gate-time; P<n> ids belong to the plan)",
}


def constraint_errors(cs, kind):
    """Validate one constraint list; kind "P" (plan-time, in dag.json) or "G" (gate-time, recorded
    by `hb constraints --record`). Messages carry no gate prefix. Twin: hb-lint.js constraintErrors."""
    import re
    out, seen = [], set()
    id_re = r"G[0-9]+" if kind == "G" else r"P[0-9]+"
    for i, c in enumerate(cs):
        is_obj = isinstance(c, dict)
        cid = c.get("id") if is_obj else None
        label = cid if isinstance(cid, str) and cid else f"#{i + 1}"
        if not is_obj:
            out.append(f"constraint {label}: must be an object {{id, claim, subjects, violation}}")
            continue
        if not isinstance(cid, str) or not re.fullmatch(id_re, cid):
            out.append(f"constraint {label}: {_CONSTRAINT_ID_RULE[kind]}")
        elif cid in seen:
            out.append(f"constraint {cid}: duplicate id in this gate")
        else:
            seen.add(cid)
        for f in ("claim", "violation"):
            if not isinstance(c.get(f), str) or not c[f].strip(_ASCII_WS):
                out.append(f"constraint {label}: {f} must be a non-empty string")
        subj = c.get("subjects")
        if not isinstance(subj, list) or not subj or any(not isinstance(x, str) or not x.strip(_ASCII_WS) for x in subj):
            out.append(f"constraint {label}: subjects must be a non-empty list of non-empty strings (the files/areas it covers)")
    return out


def _check_placeholders(dag, warnings):
    hits = []
    meta = dag.get("_meta")
    if isinstance(meta, dict) and meta.get("project") == "my-project":
        hits.append('_meta.project = "my-project"')
    flat = str(dag)
    for m in PLACEHOLDER_MARKERS:
        if m in flat:
            hits.append(f'"{m}"')
    if hits:
        more = ", …" if len(hits) > 3 else ""
        warnings.append(f"DAG still contains skeleton/template text ({', '.join(hits[:3])}{more}) — replace with the real plan")


def _strip_single_quoted(cmd):
    """Drop single-quoted spans that sit OUTSIDE double quotes: in shell those are literal
    strings the command searches FOR (grep/sed patterns, e.g. grep '@import "blocks/x.css"'),
    not files it depends on. A single quote INSIDE a double-quoted string is just a character
    — "require('$PROJECT_DIR/f.js')" keeps its path."""
    out = []
    i, n, in_double = 0, len(cmd), False
    while i < n:
        c = cmd[i]
        if c == '"':
            in_double = not in_double
            out.append(c)
        elif c == "'" and not in_double:
            j = cmd.find("'", i + 1)
            if j == -1:
                out.append(cmd[i:])
                break
            out.append(" ")
            i = j
        else:
            out.append(c)
        i += 1
    return "".join(out)


def extract_paths(cmd):
    out = set()
    for tok in re.findall(r"[\w.\-/${}]+", _strip_single_quoted(cmd or "")):
        if "/" not in tok:
            continue
        if "HB_DIR" in tok:
            continue
        p = re.sub(r"\$\{?PROJECT_DIR\}?/", "", tok)
        p = re.sub(r"^\./", "", p)
        if not p or re.search(r"[${}]", p):  # unresolved var anywhere (blocks/$n.css, ${X:-…} shrapnel)
            continue
        if p.startswith("/"):   # absolute path — a system/tool path, not a produced artifact
            continue
        if ".hb/" in p:
            continue
        base = p.rstrip("/").split("/")[-1]
        if base in ("state.json", "dag.json", "events.jsonl"):
            continue
        # exclude shell constructs (sed s/a/b/, y/a/b/) — a single-letter first segment — while keeping
        # EXTENSIONLESS artifacts (Dockerfile, Makefile, bin/hb) tracked for rot. (Absolute/awk /re/ are
        # already excluded by the leading-"/" check.)
        if re.match(r"^[A-Za-z]/", p):
            continue
        # Only rot-check tokens that look like a produced FILE: a file extension, or a known extensionless
        # artifact name (Dockerfile/Makefile). Drops relative path-shaped non-files — module specifiers
        # (playwright/test), URL paths (host:3000/health), route args (api/v1/users) — never on disk.
        if not re.search(r"\.[A-Za-z0-9]+$", base) and base not in ("Dockerfile", "Makefile"):
            continue
        out.add(p)
    return out


def _check_gate_artifacts(dag, warnings):
    phases = dag.get("phases") or []
    task_text = " ".join(
        f"{t['title'] if isinstance(t.get('title'), str) else ''} {t['description'] if isinstance(t.get('description'), str) else ''}"
        for p in phases for t in (p.get("tasks") or [])
    ).lower()
    seen = set()
    for g in (dag.get("gates") or {}).values():
        for c in ((g.get("criteria") or []) if isinstance(g, dict) else []):
            if not isinstance(c, dict) or not isinstance(c.get("cmd"), str):
                continue   # hostile shapes are lint ERRORS (the criteria-shape rule), skipped here
            for p in extract_paths(c["cmd"]):
                if p in seen:
                    continue
                seen.add(p)
                base = p.rstrip("/").split("/")[-1].lower()
                noext = re.sub(r"\.\w+$", "", base)
                pl = p.lower()
                if pl in task_text or base in task_text or (len(noext) >= 3 and noext in task_text):
                    continue
                warnings.append(f"gate references {p} — no task appears to produce it (make sure a task writes it)")
