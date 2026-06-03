#!/usr/bin/env bash
# System-wide installer for the shared Claude config (Linux, multi-user).
# Run once as root; re-runnable any time:
#
#     sudo bash /opt/claude-config/bootstrap.sh
#
# It deploys the config into every current user's ~/.claude, seeds /etc/skel so
# future users inherit it, and installs a login hook so existing and future users
# self-provision (and self-heal after a `git pull`) on next login.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="$REPO_DIR/deploy-claude-config.sh"
HOOK_DST="/etc/profile.d/claude-config.sh"
PULL=true
[[ "${1:-}" == "--no-pull" ]] && PULL=false

if [[ "$(id -u)" -ne 0 ]]; then
    echo "bootstrap.sh must run as root (try: sudo bash $REPO_DIR/bootstrap.sh)" >&2
    exit 1
fi

echo "==> Shared Claude config installer"
echo "    repo: $REPO_DIR"
echo ""

# ── Refresh the shared checkout ────────────────────────────────
if $PULL && git -C "$REPO_DIR" remote get-url origin &>/dev/null; then
    echo "==> Pulling latest config..."
    git -C "$REPO_DIR" pull --ff-only || echo "    (pull skipped/failed; using current checkout)"
    echo ""
fi
# The shared tree must be world-readable (but not writable) for all users.
chmod -R a+rX "$REPO_DIR"

# ── Enumerate target homes: root + real human accounts ─────────
declare -a TARGETS=()
[[ -d /root ]] && TARGETS+=("root:/root")
while IFS=: read -r user _ uid _ _ home shell; do
    [[ "$uid" =~ ^[0-9]+$ ]] || continue
    (( uid >= 1000 && uid < 60000 )) || continue
    [[ -d "$home" ]] || continue
    case "$shell" in */nologin|*/false|"") continue ;; esac
    TARGETS+=("$user:$home")
done < /etc/passwd

echo "==> Deploying to ${#TARGETS[@]} home(s):"
for entry in "${TARGETS[@]}"; do
    user="${entry%%:*}"
    home="${entry#*:}"
    echo "  • $user ($home)"
    bash "$DEPLOY" "$home"
done
echo ""

# ── Seed /etc/skel for future users (symlink tier only) ────────
echo "==> Seeding /etc/skel for future users..."
bash "$DEPLOY" /etc/skel --skel
echo ""

# ── Install the login hook (self-provision + self-heal) ────────
echo "==> Installing login hook at $HOOK_DST"
cat > "$HOOK_DST" <<'HOOK'
# Provision the shared Claude config on login (installed by claude-config).
# Cheap: only redeploys when the repo revision differs from what was last
# deployed into this user's ~/.claude/.deployed-rev.
CC_REPO="/opt/claude-config"
if [ -d "$CC_REPO" ] && [ -n "${HOME:-}" ] && [ -d "$HOME" ] && command -v bash >/dev/null 2>&1; then
    if command -v git >/dev/null 2>&1; then
        _cc_rev="$(git -C "$CC_REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
    else
        _cc_rev="unknown"
    fi
    if [ "$(cat "$HOME/.claude/.deployed-rev" 2>/dev/null || echo none)" != "$_cc_rev" ]; then
        bash "$CC_REPO/deploy-claude-config.sh" "$HOME" >/dev/null 2>&1 || true
    fi
    unset _cc_rev
fi
HOOK
chmod 0644 "$HOOK_DST"
echo ""

echo "==> Done."
echo "    Current users are provisioned now; future users get it on first login."
echo "    To update everyone later: git -C $REPO_DIR pull   (login hook redeploys),"
echo "    or re-run: sudo bash $REPO_DIR/bootstrap.sh"
