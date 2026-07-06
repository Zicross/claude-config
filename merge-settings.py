#!/usr/bin/env python3
"""Merge central Claude settings onto the live settings.json without clobbering
runtime-owned state.

    merge-settings.py <repo-settings-expanded> <live-settings>

The LIVE file is the base: everything Claude Code writes at runtime
(enabledPlugins, model, effortLevel, tui, spinnerVerbs, ...) is preserved.
Only the keys named in the REPO_AUTH_KEYS env var (space-separated) are taken
from the repo copy, and only when the repo actually defines them. This lets
central config (permissions, statusLine, marketplaces, update policy) propagate
on every deploy while personal/runtime settings stay put.

Writes atomically; on any error nothing is written and it exits non-zero, so the
caller can leave the live file untouched.
"""
import json
import os
import sys
import tempfile

if len(sys.argv) != 3:
    print("usage: merge-settings.py <repo-settings> <live-settings>", file=sys.stderr)
    sys.exit(2)

repo_path, live_path = sys.argv[1], sys.argv[2]
auth_keys = os.environ.get("REPO_AUTH_KEYS", "").split()

with open(live_path, encoding="utf-8") as f:
    live = json.load(f)
with open(repo_path, encoding="utf-8") as f:
    repo = json.load(f)

if not isinstance(live, dict) or not isinstance(repo, dict):
    print("merge-settings: both files must be JSON objects", file=sys.stderr)
    sys.exit(1)

# Overlay authoritative keys from the repo onto the live base. Absent-in-repo
# keys are left as-is on the live side (central config removes a permission by
# editing the permissions object, not by dropping the whole key).
for key in auth_keys:
    if key in repo:
        live[key] = repo[key]

# Atomic replace so a crash never leaves a half-written settings.json.
dst_dir = os.path.dirname(os.path.abspath(live_path))
fd, tmp = tempfile.mkstemp(dir=dst_dir, prefix=".settings-merge-")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(live, f, indent=2)
        f.write("\n")
    os.replace(tmp, live_path)
except BaseException:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
