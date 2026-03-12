#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR"
REPO_CLAUDE_DIR="$REPO_DIR/claude"
CLAUDE_HOME="$HOME/.claude"

# Portable files to sync (relative to ~/.claude/)
SYNC_FILES=(
    "settings.json"
    "CLAUDE.md"
    "plugins/installed_plugins.json"
    "plugins/known_marketplaces.json"
)

# Portable directories to sync (relative to ~/.claude/)
SYNC_DIRS=(
    "commands"
)

# Files that need path normalization
needs_path_normalization() {
    local file="$1"
    case "$file" in
        plugins/installed_plugins.json|plugins/known_marketplaces.json)
            return 0 ;;
        *)
            return 1 ;;
    esac
}

# ── OS Detection ───────────────────────────────────────────────
detect_os() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            echo "windows"
            ;;
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "wsl"
            else
                echo "linux"
            fi
            ;;
        Darwin)
            echo "macos"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

OS_TYPE="$(detect_os)"

# ── Save Mode ──────────────────────────────────────────────────
do_save() {
    echo "==> Saving Claude config to repo..."
    echo "    OS: $OS_TYPE | CLAUDE_HOME: $CLAUDE_HOME"
    echo ""

    mkdir -p "$REPO_CLAUDE_DIR/plugins"

    local changed=false

    for file in "${SYNC_FILES[@]}"; do
        local src="$CLAUDE_HOME/$file"
        local dst="$REPO_CLAUDE_DIR/$file"

        if [[ ! -f "$src" ]]; then
            echo "    [skip] $file (not found)"
            continue
        fi

        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"

        if needs_path_normalization "$file"; then
            node "$REPO_DIR/normalize.js" normalize "$dst"
            echo "    [norm] $file"
        else
            echo "    [copy] $file"
        fi

        changed=true
    done

    # Sync directories
    for dir in "${SYNC_DIRS[@]}"; do
        local src_dir="$CLAUDE_HOME/$dir"
        local dst_dir="$REPO_CLAUDE_DIR/$dir"

        if [[ -d "$src_dir" ]]; then
            mkdir -p "$dst_dir"
            # Remove files in dest that no longer exist in source
            if [[ -d "$dst_dir" ]]; then
                find "$dst_dir" -type f | while read -r f; do
                    local rel="${f#$dst_dir/}"
                    if [[ ! -f "$src_dir/$rel" ]]; then
                        rm "$f"
                        echo "    [del]  $dir/$rel"
                    fi
                done
            fi
            # Copy all files from source
            find "$src_dir" -type f | while read -r f; do
                local rel="${f#$src_dir/}"
                mkdir -p "$(dirname "$dst_dir/$rel")"
                cp "$f" "$dst_dir/$rel"
                echo "    [copy] $dir/$rel"
            done
            changed=true
        else
            echo "    [skip] $dir/ (not found)"
        fi
    done

    if [[ "$changed" == false ]]; then
        echo "No portable files found to save."
        exit 0
    fi

    # Git operations
    cd "$REPO_DIR"
    git add claude/

    if git diff --cached --quiet; then
        echo ""
        echo "==> No changes to commit."
        exit 0
    fi

    echo ""
    echo "==> Changes to be committed:"
    git diff --cached --stat
    echo ""

    read -r -p "Commit and push? [Y/n] " confirm
    confirm="${confirm:-Y}"
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        local timestamp
        timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
        git commit -m "sync: update claude config ($timestamp)"

        if git remote get-url origin &>/dev/null; then
            git push
            echo "==> Pushed to remote."
        else
            echo "==> Committed locally (no remote configured yet)."
        fi
    else
        git reset HEAD claude/ >/dev/null
        echo "==> Aborted."
    fi
}

# ── Load Mode ──────────────────────────────────────────────────
do_load() {
    echo "==> Loading Claude config from repo..."
    echo "    OS: $OS_TYPE | CLAUDE_HOME: $CLAUDE_HOME"
    echo ""

    # Pull latest if remote exists
    cd "$REPO_DIR"
    if git remote get-url origin &>/dev/null; then
        echo "    Pulling latest from remote..."
        git pull --ff-only
        echo ""
    fi

    mkdir -p "$CLAUDE_HOME/plugins"

    for file in "${SYNC_FILES[@]}"; do
        local src="$REPO_CLAUDE_DIR/$file"
        local dst="$CLAUDE_HOME/$file"

        if [[ ! -f "$src" ]]; then
            echo "    [skip] $file (not in repo)"
            continue
        fi

        # Backup existing file
        if [[ -f "$dst" ]]; then
            cp "$dst" "${dst}.bak"
            echo "    [back] $file -> ${file}.bak"
        fi

        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"

        if needs_path_normalization "$file"; then
            node "$REPO_DIR/normalize.js" expand "$dst"
            echo "    [expd] $file"
        else
            echo "    [copy] $file"
        fi
    done

    # Sync directories
    for dir in "${SYNC_DIRS[@]}"; do
        local src_dir="$REPO_CLAUDE_DIR/$dir"
        local dst_dir="$CLAUDE_HOME/$dir"

        if [[ -d "$src_dir" ]]; then
            mkdir -p "$dst_dir"
            find "$src_dir" -type f | while read -r f; do
                local rel="${f#$src_dir/}"
                mkdir -p "$(dirname "$dst_dir/$rel")"
                cp "$f" "$dst_dir/$rel"
                echo "    [copy] $dir/$rel"
            done
        else
            echo "    [skip] $dir/ (not in repo)"
        fi
    done

    echo ""
    echo "==> Done. Restart Claude Code to pick up changes."
}

# ── Entry Point ────────────────────────────────────────────────
usage() {
    echo "Usage: $(basename "$0") {save|load}"
    echo ""
    echo "  save  - Export portable config from ~/.claude/ into this repo,"
    echo "          normalize paths, commit, and push."
    echo "  load  - Pull latest config from remote, expand paths for"
    echo "          the current OS, and deploy into ~/.claude/."
    exit 1
}

case "${1:-}" in
    save) do_save ;;
    load) do_load ;;
    *)    usage ;;
esac
