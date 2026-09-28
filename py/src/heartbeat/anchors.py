"""Anchors — HeartBeat's own record of the tree at plan start and at each gate acceptance.

Node twin: the anchor section of hb.js. `.hb/anchors/<name>.json` =
{gate, ts, commit, files:{path:sha256}}. Listing: inside a git worktree
`git ls-files -co --exclude-standard` (read-only — HB_NO_GIT only disables writes);
outside git a walk that skips ANCHOR_SKIP dirs at any depth. .hb/ and .git/ are never
listed; only regular files are hashed. `changed` diffs the phase's entry anchor against
the gate's own anchor once accepted, else against the live working tree.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

from . import state as st

ANCHOR_SKIP = {".hb", ".git", "node_modules", "__pycache__", ".venv"}


def _anchors_dir(hbdir):
    return Path(hbdir) / "anchors"


def _project_dir(hbdir):
    return Path(hbdir).resolve().parent


def _git_out(pd, *args):
    if not shutil.which("git"):
        return None
    r = subprocess.run(["git", "-C", str(pd), *args], stdin=subprocess.DEVNULL,
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return r.stdout if r.returncode == 0 else None


def _in_git_worktree(pd):
    out = _git_out(pd, "rev-parse", "--is-inside-work-tree")
    return out is not None and out.decode().strip() == "true"


def list_project_files(hbdir):
    pd = _project_dir(hbdir)
    hb_rel = os.path.relpath(Path(hbdir).resolve(), pd).replace(os.sep, "/")
    rels = []
    if _in_git_worktree(pd):
        out = _git_out(pd, "ls-files", "-co", "--exclude-standard", "-z") or b""
        rels = [r for r in out.decode("utf-8", "surrogateescape").split("\0") if r]
    else:
        def walk(rel):
            try:
                ents = sorted(os.scandir(pd / rel if rel else pd), key=lambda e: e.name)
            except OSError:
                return
            for d in ents:
                r = f"{rel}/{d.name}" if rel else d.name
                if d.is_dir(follow_symlinks=False):
                    if d.name not in ANCHOR_SKIP:
                        walk(r)
                else:
                    rels.append(r)
        walk("")
    files = {}
    # sort by UTF-16 code units == JS default sort (parity on non-BMP names)
    for r in sorted(rels, key=lambda s: s.encode("utf-16-be")):
        if r == hb_rel or r.startswith(hb_rel + "/") or r.split("/")[0] == ".git":
            continue
        p = pd / r
        try:
            if not p.is_file() or p.is_symlink():   # tracked-but-deleted, or not a regular file
                continue
            files[r] = hashlib.sha256(p.read_bytes()).hexdigest()
        except OSError:
            continue
    return files


def write_anchor(hbdir, name):
    pd = _project_dir(hbdir)
    commit = None
    if _in_git_worktree(pd):
        out = _git_out(pd, "rev-parse", "HEAD")
        commit = (out.decode().strip() or None) if out else None
    a = {"gate": name, "ts": st.now_iso(), "commit": commit, "files": list_project_files(hbdir)}
    d = _anchors_dir(hbdir)
    d.mkdir(parents=True, exist_ok=True)
    st.atomic_write(d / f"{name}.json", json.dumps(a, indent=2, ensure_ascii=False) + "\n")
    return a


def try_anchor(hbdir, name):
    """Report, never swallow: a silently missing anchor would make `changed` lie later."""
    try:
        write_anchor(hbdir, name)
        return True
    except Exception as e:  # noqa: BLE001 — any failure is reported, not fatal
        sys.stderr.write(f"⚠ anchor {name} not recorded: {e}\n")
        return False


def read_anchor(hbdir, name):
    try:
        return json.loads((_anchors_dir(hbdir) / f"{name}.json").read_text())
    except (OSError, ValueError):
        return None


def maybe_start_anchor(hbdir):
    """The plan's start anchor: on the first LIVE task_started only (called from state.mutate)."""
    if read_anchor(hbdir, "_start") is not None:
        return
    if sum(1 for e in st.read_events(hbdir) if e.get("event") == "task_started") == 1:
        try_anchor(hbdir, "_start")


def changed(hbdir, gate):
    phase = next((p for p in (st.read_dag(hbdir).get("phases") or []) if p.get("gate_exit") == gate), None)
    if not phase:
        raise ValueError(f"no phase exits through gate {gate}")
    base = phase.get("gate_entry") or "_start"
    frm = read_anchor(hbdir, base)
    if not frm:
        raise ValueError(f"no entry anchor '{base}' for {gate} (recorded at the first task start / "
                         "the entry gate's acceptance)")
    own = read_anchor(hbdir, gate)
    to = own["files"] if own else list_project_files(hbdir)
    a = frm.get("files") or {}
    key = lambda s: s.encode("utf-16-be")  # noqa: E731
    return {"gate": gate, "base": base, "target": gate if own else "worktree",
            "added": [p for p in sorted(to, key=key) if p not in a],
            "modified": [p for p in sorted(to, key=key) if p in a and a[p] != to[p]],
            "deleted": [p for p in sorted(a, key=key) if p not in to]}
