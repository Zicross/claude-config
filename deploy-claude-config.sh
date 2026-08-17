#!/usr/bin/env bash
# Deploy the shared Claude config into ONE home directory. Idempotent.
#
# Usage: deploy-claude-config.sh <home-dir> [--skel]
#
# Two tiers:
#   symlink  -> CLAUDE.md, statusline-command.sh, skills/
#               (never written by Claude at runtime; symlinked to the shared repo
#                so `git pull` in the repo updates every user instantly)
#   copy+exp -> settings.json
#               (selected repo keys authoritative; other live preferences kept)
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

SYMLINK_ITEMS=(CLAUDE.md statusline-command.sh skills)
# The live file is the base. Central config owns only the minimal cross-account
# policy below. In particular, it does not force a model, effort level, TUI, or
# permission mode. Empty plugin/marketplace maps deliberately retire the old
# globally provisioned plugin surface; projects may still configure their own.
SETTINGS_AUTHORITATIVE_KEYS="statusLine extraKnownMarketplaces enabledPlugins autoUpdates autoUpdatesChannel"

mkdir -p "$CLAUDE_DIR"

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

# Remove only obsolete links previously managed by this repository. Preserve
# any real per-user directory or link with a different target.
for item in commands agents; do
    dst="$CLAUDE_DIR/$item"
    if [[ -L "$dst" && "$(readlink "$dst")" == "$REPO_CLAUDE/$item" ]]; then
        rm "$dst"
        echo "    [drop] $item (retired global surface)"
    fi
done

# ── Copy + expand tier ─────────────────────────────────────────
if ! $SKEL; then
    # ── settings.json: seed if absent, else merge central keys onto live ──
    src="$REPO_CLAUDE/settings.json"
    dst="$CLAUDE_DIR/settings.json"
    if [[ ! -f "$src" ]]; then
        echo "    [skip] settings.json (not in repo)"
    elif [[ ! -e "$dst" ]]; then
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        bash "$REPO_DIR/normalize.sh" expand "$dst" "$CLAUDE_DIR" >/dev/null
        echo "    [seed] settings.json"
    elif command -v python3 >/dev/null 2>&1; then
        # Expand a temp copy of the repo settings for THIS home, then merge only
        # the authoritative keys onto the live file (which stays the base).
        tmp="$(mktemp)"
        cp "$src" "$tmp"
        bash "$REPO_DIR/normalize.sh" expand "$tmp" "$CLAUDE_DIR" >/dev/null
        if REPO_AUTH_KEYS="$SETTINGS_AUTHORITATIVE_KEYS" \
             python3 "$REPO_DIR/merge-settings.py" "$tmp" "$dst"; then
            echo "    [merge] settings.json (central keys; runtime state kept)"
        else
            echo "    [warn] settings.json merge failed; left live file untouched"
        fi
        rm -f "$tmp"
    else
        echo "    [keep] settings.json (no python3; not clobbering runtime state)"
    fi
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
