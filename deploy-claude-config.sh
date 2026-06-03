#!/usr/bin/env bash
# Deploy the shared Claude config into ONE home directory. Idempotent.
#
# Usage: deploy-claude-config.sh <home-dir> [--skel]
#
# Two tiers:
#   symlink  -> CLAUDE.md, statusline-command.sh, skills/, commands/, agents/
#               (never written by Claude at runtime; symlinked to the shared repo
#                so `git pull` in the repo updates every user instantly)
#   copy+exp -> settings.json, plugins/installed_plugins.json,
#               plugins/known_marketplaces.json
#               (Claude rewrites these at runtime and they embed per-user paths,
#                so they are real local files, path-expanded for this home)
#
# Run by root for another user's home -> files are chown'd to that user.
# Run by a user for their own home (e.g. from the login hook) -> no chown needed.
# With --skel (for /etc/skel) only the symlink tier is laid down; the copy+expand
# files are created per-user on first login by the hook.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_CLAUDE="$REPO_DIR/claude"

HOME_DIR="${1:-}"
SKEL=false
[[ "${2:-}" == "--skel" ]] && SKEL=true
if [[ -z "$HOME_DIR" ]]; then
    echo "Usage: deploy-claude-config.sh <home-dir> [--skel]" >&2
    exit 1
fi

CLAUDE_DIR="$HOME_DIR/.claude"

SYMLINK_ITEMS=(CLAUDE.md statusline-command.sh skills commands agents)
EXPAND_FILES=(settings.json plugins/installed_plugins.json plugins/known_marketplaces.json)

mkdir -p "$CLAUDE_DIR/plugins"

# ── Symlink tier ───────────────────────────────────────────────
for item in "${SYMLINK_ITEMS[@]}"; do
    src="$REPO_CLAUDE/$item"
    dst="$CLAUDE_DIR/$item"
    [[ -e "$src" ]] || continue                 # item absent in repo (e.g. agents/)
    if [[ ! -L "$dst" && -e "$dst" ]]; then
        # A real (non-symlink) file/dir is in the way — preserve it once.
        rm -rf "$dst.bak"
        mv "$dst" "$dst.bak"
        echo "    [back] $item -> $item.bak"
    fi
    ln -sfn "$src" "$dst"
    echo "    [link] $item"
done

# ── Copy + expand tier ─────────────────────────────────────────
if ! $SKEL; then
    for rel in "${EXPAND_FILES[@]}"; do
        src="$REPO_CLAUDE/$rel"
        dst="$CLAUDE_DIR/$rel"
        [[ -f "$src" ]] || { echo "    [skip] $rel (not in repo)"; continue; }
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        bash "$REPO_DIR/normalize.sh" expand "$dst" "$CLAUDE_DIR" >/dev/null
        echo "    [expd] $rel"
    done
    # Record the deployed repo revision so the login hook can detect staleness.
    if rev="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null)"; then
        printf '%s\n' "$rev" > "$CLAUDE_DIR/.deployed-rev"
    fi
fi

# ── Ownership (only meaningful when root deploys for another user) ──
if [[ "$(id -u)" -eq 0 ]] && ! $SKEL; then
    owner="$(stat -c '%U' "$HOME_DIR")"
    group="$(stat -c '%G' "$HOME_DIR")"
    if [[ -n "$owner" && "$owner" != "UNKNOWN" ]]; then
        # -h: chown the symlinks themselves; -R does not traverse symlinked dirs.
        chown -Rh "$owner:$group" "$CLAUDE_DIR"
    fi
fi
