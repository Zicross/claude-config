# claude-config

Portable Claude Code configuration. On Linux it installs **system-wide for every
user** (current and future) from a single shared checkout; on Windows it falls
back to the original per-machine copy sync.

## Two models

| | Linux (multi-user) | Windows / single-user |
|---|---|---|
| Source of truth | `/opt/claude-config` (one shared checkout) | the cloned repo |
| How users get it | symlinks + a login hook | `sync.sh load` copies into `~/.claude` |
| Update everyone | `git pull` in `/opt` (hook redeploys) | re-run `sync.sh load` |
| Runs as | each user, as themselves | the single user |

The Linux model is the durable one: one checkout, one update point, no per-user
copies to drift.

## How the Linux model works

Each user's `~/.claude/` is assembled from three tiers:

| Tier | Items | Why |
|------|-------|-----|
| **Symlink** → `/opt/claude-config/claude/` | `CLAUDE.md`, `skills/`, `commands/`, `agents/`, `statusline-command.sh` | never written by Claude at runtime; a `git pull` updates every user instantly |
| **Copy + per-user path-expand** | `settings.json`, `plugins/installed_plugins.json`, `plugins/known_marketplaces.json` | Claude rewrites these at runtime and they embed per-user paths, so they are real local files |
| **Regenerated locally by Claude** | `plugins/cache/`, `plugins/marketplaces/`, `plugins/repos/`, `plugins/config.json` | machine-local plugin state; re-fetched, never in the repo |

A login hook (`/etc/profile.d/claude-config.sh`) re-runs the per-user deploy
whenever the repo revision differs from what was last deployed, so existing users
self-heal on update and **new users provision themselves on first login**
(`/etc/skel` seeds the symlinks at account creation).

## Install (Linux, run once as root)

```bash
sudo git clone https://github.com/Zicross/claude-config.git /opt/claude-config
sudo bash /opt/claude-config/bootstrap.sh
```

`bootstrap.sh` deploys to every current user + root, seeds `/etc/skel`, and
installs the login hook. It is idempotent — re-run it any time.

### Restore plugins (per user, once)

Deploying lays down the plugin manifests, but the marketplace repos and plugin
cache are per-user and must be fetched:

```bash
bash /opt/claude-config/restore-plugins.sh
```

This clones the configured marketplaces, installs every plugin from
`installed_plugins.json`, and re-applies the enabled/disabled state from the repo
`settings.json`. Needs network and the `claude` binary on that user's `PATH`. It
is kept out of the login hook on purpose (so a slow network never hangs a login).

## Updating the config

Two directions: **pulling** an update onto a machine, and **authoring** a change
then pushing it.

### Pull the latest onto a machine

```bash
# One command to update this machine AND redeploy to every user:
sudo bash /opt/claude-config/bootstrap.sh

# Or just pull — each user redeploys themselves on next login, because the hook
# notices the new revision:
git -C /opt/claude-config pull
```

`bootstrap.sh` pulls first (pass `--no-pull` to skip), so it is the single command
to bring a machine and everyone on it fully up to date.

**Permissions are self-healing, and they have to be.** root's umask on this host is
`0027`, so a bare `sudo git pull` writes worktree files mode `640 root:root` — and
every non-root account silently loses `claude/CLAUDE.md`, i.e. the global rules stop
loading with no error anywhere. That happened on 2026-08-16. `githooks/post-merge`
now runs `chmod -R a+rX` after any pull or checkout, and `bootstrap.sh` points git at
it via `core.hooksPath`. **A clone made before this landed will not have `core.hooksPath`
set** — run `bootstrap.sh` once on that host, or set it by hand. `core.sharedRepository`
does not solve this; it governs `.git`, not the checkout (tested).

### Author a change and push

```bash
sudoedit /opt/claude-config/claude/CLAUDE.md      # or edit any repo file
git -C /opt/claude-config commit -am "update"     # as the repo owner
git -C /opt/claude-config push
# users redeploy on next login, or force it now:
sudo bash /opt/claude-config/bootstrap.sh
```

Because the symlinked items live in the repo, editing
`/opt/claude-config/claude/CLAUDE.md` (etc.) immediately changes the live config
for everyone whose `~/.claude/CLAUDE.md` points at it. (Pushing still matters so
*other* machines get it.)

### Capturing live settings back to the repo — `sync.sh save`

For the two real per-user files (`settings.json`, plugin manifests), changes made
through Claude's own UI live in a user's `~/.claude/`. To fold them back into the
repo (paths normalized to placeholders), run as that user:

```bash
sudo bash /opt/claude-config/sync.sh save
```

Symlinked items report `[same]` and are skipped — they are already the repo.

## Windows / single-user

```bash
git clone https://github.com/Zicross/claude-config.git
bash claude-config/sync.sh load     # copies + path-expands into ~/.claude
bash claude-config/sync.sh save     # captures ~/.claude back into the repo
```

`load` backs up existing files as `*.bak` before overwriting. Restart Claude Code
afterward.

## What is NEVER synced

- `.credentials.json` (OAuth tokens)
- `settings.local.json` (machine-specific permissions/overrides — the escape
  hatch for a user who needs to diverge from the shared config)
- `history.jsonl`, caches, session data, telemetry, plugin cache, etc.
  (see `.gitignore`)

## Path handling

`settings.json` and the plugin manifests carry absolute paths that differ between
machines and users. `normalize.sh` (pure Bash — no Node, no Python) handles this:

- **normalize** (save): `/home/user/.claude/...` or `C:\Users\...\.claude\...` →
  `__CLAUDE_HOME__/...`
- **expand** (load/deploy): `__CLAUDE_HOME__` → the target user's real `~/.claude`
  with OS-appropriate separators

## Supported environments

- Native Linux (multi-user model)
- WSL (Ubuntu/Debian)
- Git Bash on Windows (copy model)
- macOS (untested)

## Files

| File | Role |
|------|------|
| `bootstrap.sh` | system installer (root): deploy all users + skel + login hook |
| `deploy-claude-config.sh` | deploy the config into one home (used by bootstrap + hook) |
| `restore-plugins.sh` | materialize the plugin cache for the current user |
| `sync.sh` | author changes back to the repo (`save`) / single-user deploy (`load`) |
| `normalize.sh` | pure-Bash path normalization |
| `claude/` | the actual config (CLAUDE.md, skills, commands, settings, plugin manifests) |

## The `claude` binary (separate from the config)

claude-config manages **configuration only**. The `claude` *binary* is handled
independently:

- Each human account runs a **per-user native install** under `~/.local`, with
  `autoUpdates: true` (set in the shared `settings.json`), so every account
  self-updates to the latest release with **no root required** and they all
  converge on the same version.
- A shared fallback at `/usr/local/bin/claude` -> `/opt/claude-bin/<version>`
  gives brand-new accounts a working `claude` instantly (zero network) before
  their native install lands.
- The login hook bootstraps the native install: on login, if
  `~/.local/bin/claude` is missing, it runs `claude install latest` in the
  background (non-blocking -- login never waits on the download).

Bumping the `/opt` fallback is a manual root op and only matters for the
first-login window; native auto-update keeps everyone current after that.
