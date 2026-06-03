Sync my Claude Code configuration to the claude-config GitHub repo.

The shared repo lives at `/opt/claude-config` (root-owned). Authoring changes
back to it is an admin task, so run this as root / with sudo.

In the Linux symlink model most config is edited in the repo directly:
`CLAUDE.md`, `skills/`, `commands/`, and `statusline-command.sh` under
`/opt/claude-config/claude/` are symlinked into every user's `~/.claude/`, so
editing the repo file IS editing the live config. `sync.sh save` therefore only
captures the files that are real per-user copies — `settings.json` and the two
plugin manifests — normalizing their machine-specific paths back to placeholders.

Run: `sudo bash /opt/claude-config/sync.sh save`

This will:
1. Copy settings.json + plugins manifests from ~/.claude/ into the repo
   (symlinked items report `[same]` and are skipped — edit those in the repo)
2. Normalize OS-specific paths in the JSON files
3. Show a diff of changes
4. Commit and push to GitHub

If the script prompts for confirmation, answer Y to proceed.

After pushing, every machine/user picks the change up on next login (the login
hook redeploys when the repo revision changes) or via
`sudo bash /opt/claude-config/bootstrap.sh`.

After the push completes, report what changed.
