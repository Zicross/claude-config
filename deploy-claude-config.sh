#!/usr/bin/env bash
# Deploy the shared Claude config into ONE home directory. Idempotent.
#
# Usage: deploy-claude-config.sh <home-dir> [--skel]
#
# Two tiers:
#   symlink  -> CLAUDE.md, statusline-command.sh, skills/, commands/, agents/
#               (never written by Claude at runtime; symlinked to the shared repo
#                so `git pull` in the repo updates every user instantly)
#   copy+exp -> settings.json
#               (repo copy authoritative; path-expanded for this home)
#   seed-once -> plugins/installed_plugins.json, plugins/known_marketplaces.json
#               (Claude OWNS these at runtime: installed plugin versions +
#                marketplace state. Deployed ONLY when absent, so a login-hook
#                redeploy never reverts live plugin/marketplace state. The repo
#                copy is the provisioning manifest read by restore-plugins.sh.)
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
# settings.json is MERGED, not overwritten: the keys below are taken from the
# repo (central config), everything else -- enabledPlugins, model, effortLevel,
# UI prefs -- is preserved from the live file Claude Code writes at runtime.
# Move a key in/out of this list to change what central config controls.
SETTINGS_AUTHORITATIVE_KEYS="permissions statusLine extraKnownMarketplaces autoUpdates autoUpdatesChannel"
# Runtime-owned by Claude Code; deployed only if ABSENT (seed once), never
# overwritten -- otherwise every login reverts plugin versions + marketplace
# state and the plugin manager reports corrupted marketplaces.
SEED_FILES=(plugins/installed_plugins.json plugins/known_marketplaces.json)

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
    # Seed-once tier: Claude owns these at runtime -- deploy only when missing.
    for rel in "${SEED_FILES[@]}"; do
        src="$REPO_CLAUDE/$rel"
        dst="$CLAUDE_DIR/$rel"
        [[ -f "$src" ]] || { echo "    [skip] $rel (not in repo)"; continue; }
        if [[ -e "$dst" ]]; then
            echo "    [keep] $rel (runtime-owned, exists)"
            continue
        fi
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        bash "$REPO_DIR/normalize.sh" expand "$dst" "$CLAUDE_DIR" >/dev/null
        echo "    [seed] $rel"
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
