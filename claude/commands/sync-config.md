Sync my Claude Code configuration to the claude-config GitHub repo.

Run the sync script at ~/github/claude-config/sync.sh in save mode. This will:
1. Copy portable config files from ~/.claude/ into the repo
2. Normalize OS-specific paths in plugin JSON files
3. Show a diff of changes
4. Commit and push to GitHub

Run: `bash ~/github/claude-config/sync.sh save`

If the script prompts for confirmation, answer Y to proceed.

After the push completes, report what changed.
