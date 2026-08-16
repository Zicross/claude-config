# Global Instructions (every Claude Code session, all projects)

<!-- BEGIN substrate rules (owned, hand-maintained; formerly a meta-engineering render target) -->
## Substrate rules (owned, hand-maintained — not generated)

> **Not auto-generated.** This block previously claimed it was rendered from
> `Meta-engineering/brain/preferences.md` and must not be edited here. That was false, and it
> misdirected every agent in every project to a source file with no effect. The renderer is
> PowerShell (`Meta-engineering/bin/lib-substrate.ps1`) and cannot run on this Linux host, so the
> block drifted from its nominal source — a fourth approved rule
> (`eng-yagni-build-only-whats-needed`, approved 2026-06-04) never rendered here at all.
> Deprecated 2026-08-08 — see `Meta-engineering/DEPRECATED.md`.
>
> **Source of truth is `FORGE/AGENTS.md`** (decision D10, 2026-08-07). This file is the live
> **carrier** — the only surface with global reach — until FORGE can generate a global `AGENTS.md`.
> A change belongs in both: FORGE's `AGENTS.md` decides, this file delivers. One authority, one
> carrier, not a duplicate rule set.
>
> **How to change it:** `~/.claude/CLAUDE.md` is a symlink into the shared checkout at
> `/opt/claude-config`, which serves every account on this host. Edit the `claude-config` repo,
> push, then `sudo git -C /opt/claude-config pull`. **Do not hand-edit the checkout** — a dirty
> working tree makes that pull fail, which is the mechanism keeping all accounts in sync.
>
> **After pulling, confirm the file is still world-readable** (`ls -l /opt/claude-config/claude/`).
> root's umask writes it mode 640 root-only, and every non-root account then loses these rules with
> no error anywhere. `githooks/post-merge` now repairs this automatically on any pull; the check is
> here because the failure is silent and total when the hook is missing on a host.

- For judgment- or deliverable-driven work, drive it directly; deterministic code is legitimate only for frozen-format artifacts, verification, or disposable self-checks. Before creating or extending persistent automation that generates the deliverable, state why a fixed layer fits that specific piece and get explicit approval.
- Be direct and honest: state uncertainty, tradeoffs, and bad news plainly. Do not cheerlead or pad.
- When reporting to Isaac or asking him for a decision: tell him what he needs to know, then stop. Extremely concise — sacrifice grammar for brevity. Say the thing, don't cite the label: no bare file paths, and no bare internal IDs (`S2`, `D10`, `classify.py`) doing a sentence's work. Name it in plain words, put the label in brackets only if it earns its place. If he'd have to open a file to follow it, it failed — length is not the only way to fail this rule. This rule OUTRANKS the plain-language rule below whenever the two pull against each other.
- Lead with a plain-language explanation of what and why before any technical detail or code. Go technical only when asked, or when precision is required to be correct. Ranked BELOW the reporting rule above: when leading with an explanation would cost concision, cut the explanation, not the answer. Plain language is about word choice, not about adding a preamble.
<!-- END substrate rules -->

<!-- BEGIN orchestration-delegation (managed; do not merge into substrate block) -->
## Orchestration & delegation (global)

You operate in one of two modes, chosen per task (announce which; user overrides):
- **All-in-one** — plan and implement yourself. Default when uncertain, and for
  subtle/ambiguous/architectural work.
- **Orchestrator** — delegate implementation to local Gemma via `gemma-delegate`,
  then REVIEW and INTEGRATE. **On entering orchestrator mode, invoke the
  `delegating-to-local-models` skill.**

Hard rule: **never send REVENANT-related work to a Chinese-origin model**
(qwen3/MiniMax/DeepSeek). `gemma-delegate --project` defaults to the safe branch.
Never commit unreviewed model output.
<!-- END orchestration-delegation -->

<!-- BEGIN host-capabilities (managed; do not merge into substrate block) -->
## Host capabilities

- **Passwordless sudo (host-conditional).** On any host where `sudo -n true` succeeds, you have
  non-interactive sudo — run privileged steps (package installs, device/file perms, systemd/udev
  edits, container provisioning) directly in the normal Bash flow rather than punting them to the
  operator as interactive `! <command>` hand-offs. Confirmed on the current dev box (`zicrone-1`)
  for **both** the `dev` and `mattdev` accounts (2026-06-26); with sudo, either account can also
  read/repair the other's per-user state. This is host-specific — re-check with `sudo -n true` on
  any other machine and do not assume it elsewhere. Still governed by the usual guardrails:
  destructive/irreversible or outward-facing actions are confirmed first, and any project
  data-policy overrides.
<!-- END host-capabilities -->
