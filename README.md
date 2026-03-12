# claude-config

Portable Claude Code configuration, synced across machines via Git.

## What gets synced

| File | Purpose |
|------|---------|
| `settings.json` | Global preferences (plugins enabled, effort level, etc.) |
| `CLAUDE.md` | Global instructions file |
| `plugins/installed_plugins.json` | Plugin registry (paths are normalized) |
| `plugins/known_marketplaces.json` | Marketplace configuration |

## What is NEVER synced

- `.credentials.json` (OAuth tokens)
- `settings.local.json` (machine-specific permissions)
- `history.jsonl`, caches, session data, telemetry, etc.

## Usage

### First-time setup

```bash
git clone <your-remote-url> ~/github/claude-config
```

### Save current config to repo

```bash
cd ~/github/claude-config
bash sync.sh save
```

Copies portable files from `~/.claude/` into the repo, normalizes OS-specific paths, commits and pushes.

### Load config from repo onto this machine

```bash
cd ~/github/claude-config
bash sync.sh load
```

Pulls latest config from remote, expands path placeholders for the current OS, and deploys into `~/.claude/`. Existing files are backed up as `*.bak` before overwriting.

Restart Claude Code after loading to pick up changes.

### Path handling

Plugin files contain absolute filesystem paths that differ between Windows and Linux. The sync script handles this automatically:

- **On save**: Absolute paths like `C:\Users\...\\.claude\...` or `/home/user/.claude/...` are replaced with `__CLAUDE_HOME__/...`
- **On load**: `__CLAUDE_HOME__` is expanded to the real `~/.claude` path with OS-appropriate separators

### Supported environments

- Git Bash on Windows
- WSL (Ubuntu/Debian)
- Native Linux
- macOS (untested but should work)
