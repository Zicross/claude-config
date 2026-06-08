---
name: delegating-to-local-models
description: "Use when entering orchestrator mode to delegate implementation work to a local Gemma model running on the laptop. Invoked automatically upon mode entry. Covers the full orchestrator loop (PLAN → IDENTIFY → DELEGATE → REVIEW → INTEGRATE → VERIFY), model routing policy, sensitivity guard (REVENANT work must never reach Chinese-origin models), gemma-delegate invocation patterns, exit-code meanings, and Claude's required response to each outcome."
---

# Delegating to Local Models — Orchestrator Playbook

This skill loads when Claude enters **orchestrator mode**: Claude plans and reviews; a local Gemma model on the laptop drafts implementation. The `gemma-delegate` CLI is the transport layer. Claude owns every gate.

## The orchestrator loop

```
PLAN → IDENTIFY → DELEGATE → REVIEW → INTEGRATE → VERIFY
```

**PLAN.** Decompose the work into well-specified, self-contained tasks. Each task must be completable by a model that cannot ask follow-up questions: include all context, constraints, and acceptance criteria in the task description.

**IDENTIFY.** For each task, determine two things independently:
1. *Sensitivity* — is this REVENANT-related (or non-`generic`)? If yes, Gemma-only (laptop). qwen3 is forbidden regardless of whether the laptop is up.
2. *Tier* — `quality` (12B, default) for anything nontrivial; `fast` (8B) for bulk/mechanical/speed-critical work where minor verbosity cost is acceptable.

These decisions are orthogonal. REVENANT work can and should be delegated — Gemma is local, so sensitive code never touches third-party cloud. Sensitivity controls *which model*; nature of the task (subtle vs. mechanical) controls *whether to delegate at all*.

**DELEGATE.** Call `gemma-delegate` with the resolved flags. Pass task text via `--task` or stdin; embed relevant source files with `--files`. Handle the exit code (see table below) before proceeding.

**REVIEW.** Read every line of the output. Check for correctness, security issues, adherence to the task spec, and completeness. Do not trust output blindly because it came from a local model — the review gate is unchanged from all-in-one mode.

**INTEGRATE.** Claude personally owns architectural pieces, critical paths, and anything that requires judgment. Apply Gemma's draft where it is correct; rewrite or discard where it is not. Claude applies the changes to the codebase — the local model never touches files directly.

**VERIFY.** Run tests, the project's verification gates, and any task-specific checks. The same discipline applies as in all-in-one mode: TDD, planning system rules, commit gates. Delegation changes who drafts; it does not change what the work must pass.

**Invariant: Claude never commits unreviewed model output.**

---

## Model policy

| Tier flag | Model tag | Params | Speed | When to use |
|---|---|---|---|---|
| `--tier quality` (default) | `gemma4:12b` | 12B dense | ~50 tok/s | Default for all delegation; fully GPU-resident; 256K context |
| `--tier fast` | `gemma4` | 8B (E4B) | ~100 tok/s | Bulk/mechanical/speed-critical; accept minor verbosity cost; 128K context |
| `--model gemma4:26b` (manual) | `gemma4:26b` | 26B MoE | ~55 tok/s | **Dormant. Not in any default path.** Evidence shows the 12B matches its quality everywhere and beats it on long context. The 26B cannot fit in 12 GB VRAM (partial CPU offload, 24 s load). Only escalate manually if a future hardware upgrade changes the economics. |

The `qwen3` entry in `MODEL_DEFAULTS` (`qwen3:8b`) exists solely as the **generic-work fallback** when the laptop is unreachable. It is never used for REVENANT or any non-`generic` project — see Sensitivity guard.

---

## Sensitivity guard

**Definition (locked):** anything REVENANT-related is sensitive. Non-`generic` projects are treated as sensitive by default.

**Rule:** sensitive work must NEVER reach a Chinese-origin model: `qwen3`, MiniMax, or DeepSeek (any tag containing those strings).

**Fail-safe default:** `--project` defaults to `revenant`. Omitting the flag treats work as sensitive and causes the script to refuse qwen3 routing with exit code 3. You must pass `--project generic` explicitly to enable the qwen3 fallback path. Forgetting the flag therefore fails safe — it never leaks to a Chinese-origin model.

**Fallback paths when the laptop is unreachable:**
- REVENANT (or any non-`generic`) work: laptop → **Claude does it in-context** (exit code 6). qwen3 is excluded regardless.
- Generic work: laptop → qwen3 (host machine) → if both down, exit code 5 (Claude does it in-context).

---

## Invocation

The CLI is deployed as part of the `skills/` symlink and must be called by its absolute path:

```
~/.claude/skills/delegating-to-local-models/bin/gemma-delegate
```

Configuration (endpoint URLs, model tags, tier defaults) is loaded from `~/.config/gemma-delegate/config.toml` (outside the repo, never committed) or from environment variables (`GEMMA_DELEGATE_LAPTOP`, `GEMMA_DELEGATE_QWEN3`, `GEMMA_DELEGATE_CONFIG`). No network addresses appear in this file or in the repository (§4a of the design spec).

### Common invocation patterns

**Default (REVENANT, quality tier, task via flag):**
```bash
~/.claude/skills/delegating-to-local-models/bin/gemma-delegate \
  --task "Add docstring and type hints to store_blob(); keep behavior identical." \
  --files path/to/store.py
```

**Fast tier for bulk mechanical work:**
```bash
~/.claude/skills/delegating-to-local-models/bin/gemma-delegate \
  --tier fast \
  --task "Rename all occurrences of `foo` to `bar` in the following module." \
  --files path/to/module.py
```

**Generic project (enables qwen3 fallback):**
```bash
~/.claude/skills/delegating-to-local-models/bin/gemma-delegate \
  --project generic \
  --task "Write a Python function that computes Fibonacci numbers iteratively." \
  --tier fast
```

**Task via stdin (for long task descriptions):**
```bash
cat task-description.txt | \
  ~/.claude/skills/delegating-to-local-models/bin/gemma-delegate \
  --files src/foo.py src/bar.py
```

**Long-context task (raise num-ctx and num-predict explicitly):**
```bash
~/.claude/skills/delegating-to-local-models/bin/gemma-delegate \
  --num-ctx 65536 \
  --num-predict 4096 \
  --task "Find and fix the off-by-one bug hidden in the following 60K-token codebase." \
  --files path/to/large_module.py
```

**Inspect full response metadata:**
```bash
~/.claude/skills/delegating-to-local-models/bin/gemma-delegate \
  --raw \
  --task "..." | jq '.eval_count, .eval_duration'
```

---

## All flags

| Flag | Default | Description |
|---|---|---|
| `--task TEXT` | (stdin) | Task text. If omitted, reads from stdin. |
| `--project {revenant,generic}` | `revenant` | Sensitivity context. Default `revenant` is the fail-safe. |
| `--tier {quality,fast}` | `quality` | Model tier. `quality` → `gemma4:12b`; `fast` → `gemma4` (8B). |
| `--model TAG` | (from tier) | Explicit model override; bypasses tier lookup. Use for manual 26B escalation only. |
| `--files [FILE ...]` | (none) | Files to embed in the prompt. Content is checked against `num-ctx` before sending. |
| `--num-ctx INT` | 16384 | Context window size. Ollama default (~4K) silently truncates; always set this explicitly for long-context tasks. Gemma 4 supports 128K–256K. |
| `--num-predict INT` | 2048 | Max output tokens. Set generously for long outputs to avoid truncation. |
| `--system TEXT` | (none) | System prompt override. The script injects per-call; no baked model needed. |
| `--raw` | off | Print the full JSON response (includes token counts, timing, done_reason) instead of just the content. |

---

## Exit codes and required responses

| Code | Meaning | Claude's required response |
|---|---|---|
| **0** | Success. Output on stdout is complete and not truncated. | Review the output, integrate what is correct, verify. |
| **2** | Usage or config error: unknown tier, empty task, or no laptop endpoint configured. | Fix the invocation (check flags) or set up `~/.config/gemma-delegate/config.toml` with a valid `[endpoints].laptop` entry. Do not retry without fixing the root cause. |
| **3** | Refused on sensitivity: non-`generic` project + Chinese-origin model tag. The script hard-refuses; it does not warn. | Do NOT retry with that model. Either use a Gemma tier on the laptop (`--tier quality` or `--tier fast`), or do the work in-context yourself. |
| **4** | Context overflow: estimated prompt tokens + output reserve exceed `num-ctx`. The prompt was not sent. | Raise `--num-ctx` (Gemma 4 supports up to 256K), chunk the task into smaller pieces, or trim `--files`. |
| **5** | All endpoints down: laptop unreachable on a `generic` project AND qwen3 endpoint is also unreachable (or not configured). | No local model is available. Claude does the work in-context. |
| **6** | REVENANT takeover: laptop is unreachable AND the project is sensitive (non-`generic`). qwen3 fallback is forbidden; the script exits immediately with this code. | Claude must do this work in-context. Do NOT fall back to qwen3 or any Chinese-origin model under any circumstance. This is not a degraded path — it is the correct path when the laptop is down on sensitive work. |
| **7** | Truncated output: the model hit `num-predict` before finishing (`done_reason=length`). The partial output is NOT returned — the script exits rather than silently return incomplete output. | Re-run with a larger `--num-predict`. Do not attempt to use partial output. |

**Graceful degradation principle:** exit codes 5 and 6 both mean "no model available; Claude does it." Delegation is an optimization, not a dependency. The methodology never blocks work.

---

## Context and output guardrails

Ollama's default context window is approximately 4K tokens and truncates silently. Always set `--num-ctx` explicitly for any non-trivial task. Gemma 4 12B supports 256K tokens; the 8B supports 128K.

Long outputs truncate if `--num-predict` is too small. The default is 2048 tokens. For tasks that produce substantial code (full classes, long functions, multi-file output), raise it to 4096 or higher. Truncation is detected via `done_reason` and surfaced as exit code 7 rather than returned silently.

The script estimates prompt token count before sending (approximately `len(text) / 3.5` characters per token) and fails with exit code 4 if the prompt plus output reserve would exceed `num-ctx`. This is a pre-flight check — no tokens are consumed on overflow.

Setting `think: false` is unconditional. Thinking burns the token budget before the answer starts and is disabled for all calls.
