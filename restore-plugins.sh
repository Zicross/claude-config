#!/usr/bin/env bash
# Materialize the plugin cache for the CURRENT user from the deployed manifests.
#
#     bash /opt/claude-config/restore-plugins.sh
#
# Deploying the config lays down plugins/installed_plugins.json +
# known_marketplaces.json, which Claude reads — but it does NOT clone the
# marketplace repos or populate the per-user plugin cache. This script does that
# deterministically by driving the `claude` CLI:
#   1. clone/refresh every configured marketplace
#   2. install every plugin listed in installed_plugins.json
#
# Run it once per account (it is idempotent). The enabled/disabled state lives in
# settings.json and is respected automatically — this script does not toggle it.
#
# Kept OUT of the login hook on purpose: it needs the network and the `claude`
# binary, and we don't want either to slow down or hang a login.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
MANIFEST="$CLAUDE_DIR/plugins/installed_plugins.json"

# Locate the claude binary (each user needs it on PATH or in a standard spot).
CLAUDE_BIN="$(command -v claude 2>/dev/null || true)"
for cand in "$HOME/.local/bin/claude" /usr/local/bin/claude /usr/bin/claude; do
    [[ -n "$CLAUDE_BIN" ]] && break
    [[ -x "$cand" ]] && CLAUDE_BIN="$cand"
done
if [[ -z "$CLAUDE_BIN" ]]; then
    echo "restore-plugins: 'claude' binary not found on PATH for $(id -un)." >&2
    echo "  Install Claude Code for this user first, then re-run." >&2
    exit 1
fi
if [[ ! -f "$MANIFEST" ]]; then
    echo "restore-plugins: $MANIFEST missing — deploy the config first." >&2
    exit 1
fi

# Extract "plugin@marketplace" keys from installed_plugins.json.
extract_plugins() {
    if command -v jq >/dev/null 2>&1; then
        jq -r '.plugins | keys[]' "$MANIFEST"
    else
        # Plugin keys are the only "...@...": entries in the file.
        grep -oE '"[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+"[[:space:]]*:' "$MANIFEST" \
            | grep -oE '[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+'
    fi
}

mapfile -t PLUGINS < <(extract_plugins | sort -u)
if [[ "${#PLUGINS[@]}" -eq 0 ]]; then
    echo "restore-plugins: no plugins found in manifest; nothing to do."
    exit 0
fi

# The intended enabled/disabled state is authoritative in the REPO settings.json,
# not the live one (which `claude plugin install` flips to enabled, and which may
# already have drifted). Read the disabled set from the repo so re-runs stay
# faithful regardless of live-file drift.
REPO_SETTINGS="$REPO_DIR/claude/settings.json"
extract_disabled() {
    [[ -f "$REPO_SETTINGS" ]] || return 0
    if command -v jq >/dev/null 2>&1; then
        jq -r '(.enabledPlugins // {}) | to_entries[] | select(.value==false) | .key' "$REPO_SETTINGS"
    else
        grep -oE '"[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+"[[:space:]]*:[[:space:]]*false' "$REPO_SETTINGS" \
            | grep -oE '[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+'
    fi
}
mapfile -t DISABLED < <(extract_disabled | sort -u)

echo "==> Refreshing marketplaces..."
"$CLAUDE_BIN" plugin marketplace update || echo "    (marketplace update reported an issue; continuing)"

echo "==> Installing ${#PLUGINS[@]} plugin(s)..."
fail=0
for p in "${PLUGINS[@]}"; do
    if "$CLAUDE_BIN" plugin install "$p" >/dev/null 2>&1; then
        echo "    [ok]   $p"
    else
        echo "    [fail] $p"
        fail=$((fail + 1))
    fi
done

if [[ "${#DISABLED[@]}" -gt 0 ]]; then
    echo "==> Re-applying disabled state for ${#DISABLED[@]} plugin(s)..."
    for p in "${DISABLED[@]}"; do
        "$CLAUDE_BIN" plugin disable "$p" >/dev/null 2>&1 && echo "    [off]  $p" || echo "    [warn] could not disable $p"
    done
fi

echo ""
if [[ "$fail" -eq 0 ]]; then
    echo "==> All plugins restored. Verify with: claude plugin list"
else
    echo "==> Done with $fail failure(s). Check: claude plugin list"
    exit 1
fi
