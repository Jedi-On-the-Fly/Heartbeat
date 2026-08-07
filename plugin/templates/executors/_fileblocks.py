"""Shared helper for HeartBeat text-model backends.

Parse ===FILE: <path>=== / ===END=== blocks out of a model's text response and write
them into the working directory. Normalizes model quirks (absolute paths, a $PROJECT_DIR
prefix) back into cwd, refuses to escape the tree or touch .hb/, and CONCATENATES multiple
blocks that target the same file. `norm_rel` is reused by the tool-based backends.
"""
import os
import re

BLOCK = re.compile(r"===FILE:\s*(.+?)\s*===\s*\n(.*?)\n===END===", re.DOTALL)


def norm_rel(rel, cwd=None):
    """Normalize a model-supplied path to a safe relative path under cwd: strip a
    $PROJECT_DIR prefix, map an absolute path to relative-if-under-cwd else basename."""
    cwd = os.path.realpath(cwd or os.getcwd())
    rel = re.sub(r"^\$\{?PROJECT_DIR\}?/?", "", (rel or "").strip())
    if os.path.isabs(rel):
        ab = os.path.realpath(rel)
        rel = os.path.relpath(ab, cwd) if ab.startswith(cwd + os.sep) else os.path.basename(rel)
    return rel.lstrip("/")


def write_blocks(text, cwd=None):
    cwd = os.path.realpath(cwd or os.getcwd())
    files = {}
    for raw, content in BLOCK.findall(text or ""):
        rel = norm_rel(raw, cwd)
        dest = os.path.realpath(os.path.join(cwd, rel))
        if not rel or rel.startswith(".hb/") or not dest.startswith(cwd + os.sep):
            continue
        files.setdefault(dest, []).append(content)

    written = []
    for dest, parts in files.items():
        os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
        with open(dest, "w") as f:
            f.write("\n".join(parts))
        written.append(os.path.relpath(dest, cwd))
    return written
