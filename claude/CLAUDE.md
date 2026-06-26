# Global Instructions (every Claude Code session, all projects)

<!-- BEGIN meta-engineering substrate (managed block; idempotent merge target) -->
## Substrate rules (auto-generated from brain/preferences.md -- do not edit here)
- For judgment- or deliverable-driven work, drive it directly; deterministic code is legitimate only for frozen-format artifacts, verification, or disposable self-checks. Before creating or extending persistent automation that generates the deliverable, state why a fixed layer fits that specific piece and get explicit approval.
- Be direct and honest: state uncertainty, tradeoffs, and bad news plainly. Do not cheerlead or pad.
- Lead with a plain-language explanation of what and why before any technical detail or code. Go technical only when asked, or when precision is required to be correct.
<!-- END meta-engineering substrate -->

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
