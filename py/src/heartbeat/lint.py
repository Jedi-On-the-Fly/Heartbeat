"""Static DAG validation — ported from the node hb-lint.js with the same rules."""
import re

PLACEHOLDER_MARKERS = [
    "Implement feature A", "Implement feature B",
    "Description of what this task produces.",
    "Create all required directories and config files.",
    "Check that all required tools and dependencies are available.",
    "Verify A and B work together correctly.",
    "output/result.json",
]


def lint(dag):
    errors, warnings = [], []
    gates = dag.get("gates") or {}
    phases = dag.get("phases") or []
    task_ids, task_map = set(), {}

    for p in phases:
        tasks = p.get("tasks") or []
        if len(tasks) > 8:
            warnings.append(f"[{p['id']}] {len(tasks)} tasks (>8) — context-loss risk, consider sub-phases")
        for t in tasks:
            if t["id"] in task_ids:
                errors.append(f"duplicate task ID: {t['id']}")
            task_ids.add(t["id"])
            task_map[t["id"]] = t
        for g in (p.get("gate_entry"), p.get("gate_exit")):
            if g and g not in gates:
                errors.append(f"[{p['id']}] undefined gate: {g}")
        if p.get("gate_entry") and not any(q.get("gate_exit") == p["gate_entry"] for q in phases):
            errors.append(f"[{p['id']}] gate_entry {p['gate_entry']} is no phase's gate_exit — phase locked forever")

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

    _check_placeholders(dag, warnings)
    _check_gate_artifacts(dag, warnings)
    _check_constraints(dag, errors)
    return {"errors": errors, "warnings": warnings}


# "Non-blank" with ONE explicit whitespace set — str.strip() and JS trim() disagree on \ufeff /
# \x1c-\x1f / \x85, and the two lints must return identical errors (twin: blankFree).
_ASCII_WS = " \t\n\r\f\v"


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
    if dag.get("_meta", {}).get("project") == "my-project":
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
        f"{t.get('title', '')} {t.get('description', '')}"
        for p in phases for t in (p.get("tasks") or [])
    ).lower()
    seen = set()
    for g in (dag.get("gates") or {}).values():
        for c in (g.get("criteria") or []):
            for p in extract_paths(c.get("cmd", "")):
                if p in seen:
                    continue
                seen.add(p)
                base = p.rstrip("/").split("/")[-1].lower()
                noext = re.sub(r"\.\w+$", "", base)
                pl = p.lower()
                if pl in task_text or base in task_text or (len(noext) >= 3 and noext in task_text):
                    continue
                warnings.append(f"gate references {p} — no task appears to produce it (make sure a task writes it)")
