# claude-config

Minimal shared Claude Code configuration for this host.

## What is global

- `claude/CLAUDE.md` — the Claude carrier for FORGE's global behavioral rules.
- `claude/skills/academic-writing/` — the only global skill.
- `claude/settings.json` — auto-update policy, no global plugins/marketplaces, and the status line.
- `claude/statusline-command.sh` — local context/rate-limit display.

Models, effort, TUI mode, and permission mode are deliberately per-user or per-project. No custom
commands, delegation framework, project workflow, investigation method, or document-format skill
belongs in the global layer.

## Linux deployment

`/opt/claude-config` is the shared checkout. Each account receives symlinks for the immutable files
and a merged local `settings.json`. The merge owns only auto-update, status-line, plugin, and custom
marketplace keys; it preserves all other user preferences.

Install or update:

```bash
sudo bash /opt/claude-config/bootstrap.sh
```

A login hook redeploys when the checkout revision changes. Git hooks repair world-readable checkout
permissions after pulls; losing read access silently removes the global rules for non-root users.

Do not edit `~/.claude/CLAUDE.md` or `~/.claude/skills`: they are symlinks. Author changes in a
branch of this repository, merge them, then update `/opt/claude-config`.

## Runtime state is not configuration

Credentials, transcripts, file history, caches, telemetry, plugin caches, and alternate Claude
runtime roots are never synced or deleted by this repository.
