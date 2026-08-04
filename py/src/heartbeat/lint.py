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
    return {"errors": errors, "warnings": warnings}


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


def extract_paths(cmd):
    out = set()
    for tok in re.findall(r"[\w.\-/${}]+", cmd or ""):
        if "/" not in tok:
            continue
        if "HB_DIR" in tok:
            continue
        p = re.sub(r"\$\{?PROJECT_DIR\}?/", "", tok)
        p = re.sub(r"^\./", "", p)
        if not p or p.startswith("$"):
            continue
        if ".hb/" in p:
            continue
        base = p.rstrip("/").split("/")[-1]
        if base in ("state.json", "dag.json", "events.jsonl"):
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
