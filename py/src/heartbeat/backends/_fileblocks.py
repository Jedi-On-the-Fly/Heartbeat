"""Shared: parse ===FILE: path=== / ===END=== blocks from model text and write them
into a base dir (normalizing absolute/$PROJECT_DIR paths, concatenating split files)."""
import os
import re

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
