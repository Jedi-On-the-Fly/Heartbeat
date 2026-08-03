"""Shared helper for HeartBeat text-model backends.

Parse ===FILE: <path>=== / ===END=== blocks out of a model's text response and write
them into the working directory. Normalizes model quirks (absolute paths, a
$PROJECT_DIR prefix) back into cwd, refuses to escape the tree or touch .hb/, and
CONCATENATES multiple blocks that target the same file (small models often split one
file across blocks). Returns the list of relative paths written.

Used as a robust fallback by every text backend (and as the primary writer for the
raw `ollama` backend, which has no tool-calling).
"""
import os, re

BLOCK = re.compile(r"===FILE:\s*(.+?)\s*===\s*\n(.*?)\n===END===", re.DOTALL)


def write_blocks(text, cwd=None):
    cwd = os.path.realpath(cwd or os.getcwd())

    def normalize(rel):
        rel = re.sub(r"^\$\{?PROJECT_DIR\}?/?", "", rel.strip())
        if os.path.isabs(rel):
            ab = os.path.realpath(rel)
            rel = os.path.relpath(ab, cwd) if ab.startswith(cwd + os.sep) else os.path.basename(rel)
        return rel.lstrip("/")

    files = {}
    for raw, content in BLOCK.findall(text or ""):
        rel = normalize(raw)
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
