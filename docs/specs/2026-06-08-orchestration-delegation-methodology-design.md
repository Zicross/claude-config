---
id: orchestration-delegation-methodology
type: design-spec
title: "Global Orchestration & Delegation Methodology"
date: "2026-06-08"
status: draft
scope: global (claude-config; governs all host work)
---

# Global Orchestration & Delegation Methodology — Design

## 1. Summary

Give the host Claude two explicit operating modes and a clean, safe way to
delegate implementation work to local Gemma 4 models running on the laptop
(`zigg`) over Ollama. The goal is to cut cloud cost and keep sensitive code
local, **without** sacrificing correctness or performance, and **without**
turning Claude into a blind dispatcher — Claude stays the architect/reviewer and
owns every gate the work must pass.

This methodology is **global**: it lives in the `claude-config` repo and governs
all work on the host, not any single project. Project-specific rules (e.g.
REVENANT's planning system) continue to apply on top of it.

## 2. Goals / Non-goals

**Goals**
- Two modes: *orchestrator* (delegate + review) and *all-in-one* (plan + do it myself).
- A clean, tested interface for calling Gemma — not raw curl re-typed each time.
- A model-routing policy grounded in measured evidence, not the handoff doc's claims.
- A trust/sensitivity guard that never sends protected work to Chinese-origin models.
- Guardrails so Ollama defaults (context truncation) and hardware limits (VRAM)
  don't silently degrade output.
- A re-runnable eval harness that both selects the model and guards against regressions.

**Non-goals**
- Replacing Claude's judgment with automation. The script is transport + guardrails only.
- Switching serving stacks (vLLM/llama.cpp). Ollama is correct for a single-GPU,
  single-client host, and remote model management over its API removes the only friction.
- Multi-file agentic editing by the local model (Aider-style). Out of scope; Claude
  applies edits and owns git/verification.

## 3. Background & evidence (why the policy is what it is)

Hardware: laptop `zigg` (RTX 5070 Ti, **12 GB VRAM**), Ollama over Tailscale on
the laptop's tailnet address, port 11434. **Real addresses are NOT recorded in
this repo** (it is public — see §4a); they live in a gitignored local config.
Reachable via the HTTP API only — no shell; models are created/pulled remotely
via `/api/create` and `/api/pull`.

Models served (identities confirmed from each model's own `model_info`):
- `gemma4:latest` = **Gemma 4 E4B** — 8.0 B total params, dense + Per-Layer
  Embeddings ("effective 4B"). 128K context window. Fits 100% on GPU (~8.4 GB).
- `gemma4:12b` = **Gemma 4 12B** dense. 256K context window. Fits 100% on GPU (~8.4 GB).
- `gemma4:26b` = **Gemma 4 26B-A4B MoE** — 25.8 B total, 4 B active, 128 experts
  top-8. 256K window. **Does NOT fit 12 GB** — ~57% GPU / ~43% CPU offload, 24 s load.

The "flexible parameters" property is real Gemma 4 architecture: the E-series uses
Per-Layer Embeddings (total vs. effective), and the 26B is Mixture-of-Experts
(total vs. active-per-token). Not a hallucination.

### Eval evidence (run 2026-06-07/08; harness prototyped, results retained)

Four rounds, ~32 measurements, deterministic hidden-reference scoring:

| Round | Tasks | 8B (E4B) | 12B | 26B |
|---|---|---|---|---|
| Easy (functions) | 6 | 6/6 | 6/6 | 6/6 |
| Medium (LeetCode-medium DP) | 5 | 5/5 | 5/5 | 5/5 |
| Blind-spot (constraint-density, ambiguity, long output) | 28 checks | 26/28 | 28/28 | 28/28 |
| Context-scaling (needle bug-fix to ~79K tokens) | 4 sizes | 5/5 all | 5/5 all | 5/5 all |

Speed (steady-state): 8B ≈ 100 tok/s; 12B ≈ 50 tok/s; 26B ≈ 55 tok/s.
Long-context latency at ~79K prompt tokens: **8B 42 s, 12B 69 s, 26B 179 s**.

(Notes: the 8B's 26/28 reflects 4/6 on the long-output Matrix task *after* raising
`num_predict` — its first run scored 0/6 purely from truncation at a 1500-token cap,
a harness artifact, not a logic error. "~32 measurements" counts the 11 scored tasks
plus the 12 context-scaling cells plus the multi-check blind-spot tasks; it is an
approximate total, not a precise n.)

**Findings that drive the policy:**
1. The 26B showed **no quality advantage in any round**, including long context
   (its best theoretical case), at up to **4× the latency** and with memory
   fragility (HTTP 500 at `num_ctx=8192` on a ~5K-token prompt until raised).
   On this hardware it is **strictly dominated** by the 12B.
2. The 12B **matched the 26B on quality everywhere**, fits fully in VRAM, loads
   in ~3.5 s, and is robust under long context.
3. The 8B is **~2× faster** with near-identical quality — its only stumble was a
   long coherent-output task (Matrix class, 4/6) and a tendency to verbosity that
   risks truncation.
4. Operational lessons baked into the design: long-context tasks need `num_ctx`
   raised; long outputs need `num_predict` raised or they truncate mid-answer.

## 4. Architecture & placement

All artifacts live in `claude-config` and deploy via the existing `sync.sh`/
`deploy-claude-config.sh` flow. **Deployment constraint (verified):** that flow
only symlinks a fixed set — `SYMLINK_ITEMS=(CLAUDE.md statusline-command.sh skills
commands agents)` — and nothing from the repo is placed on `PATH`. So new
top-level dirs (`bin/`) would NOT deploy, and PATH cannot be assumed. **Therefore
all executables are co-located under the skill dir** (`skills/` is already
deployed) and invoked by **absolute path**, not via PATH.

- `claude/CLAUDE.md` — **always-on managed block**: the two modes, per-task
  selection rule, the sensitivity guard, and a pointer to the skill. Kept short.
- `claude/skills/delegating-to-local-models/SKILL.md` — the detailed orchestrator
  loop, model policy, routing/fallback tables, and `gemma-delegate` usage. Invoked
  via the CLAUDE.md instruction when Claude enters orchestrator mode (§5).
- `claude/skills/delegating-to-local-models/bin/gemma-delegate` — the wrapper CLI.
  Deployed automatically with the skill symlink; called by its absolute deployed
  path (`~/.claude/skills/delegating-to-local-models/bin/gemma-delegate`).
- `claude/skills/delegating-to-local-models/bin/gemma-delegate.toml.example` —
  **committed**: placeholder endpoints, model tags, tier defaults.
- **Live config: `~/.config/gemma-delegate/config.toml` (outside any repo) or env
  vars** — the real endpoints, never in the repo tree. See §4a.
- `claude/skills/delegating-to-local-models/eval/` — the Layer-B eval harness.
- `claude/skills/delegating-to-local-models/tests/` — Layer-A plumbing unit tests.

### 4a. Public-repo hygiene (the repo is PUBLIC)

`github.com/Zicross/claude-config` is **public**. Therefore:
- **No network addresses or routing topology in committed files** — no Tailscale
  IPs, host/gateway addresses, MASQUERADE/route details, or ports paired with
  addresses, in docs, the skill, CLAUDE.md, or any tracked config. (Bare machine
  nicknames like `zigg` carry no security value and are fine; addresses are not.)
- Real endpoints live only in `~/.config/gemma-delegate/config.toml` (outside any
  repo) or env vars (`GEMMA_DELEGATE_ENDPOINT` etc.). The committed `.example`
  carries placeholders. Because the skill dir is a symlink into the repo, the live
  config is deliberately kept OUTSIDE it so it can never be committed.
- `.gitignore` still lists `**/gemma-delegate*.toml` (belt-and-suspenders) excluding
  the `.example`.
- The deploy/sync flow must be verified not to copy any live config into the repo.
- **The committed `gemma-delegate` script embeds no local filesystem paths or host
  structure** — all environment-specific values come from the out-of-repo config/env.
- This spec itself is redacted accordingly.

## 5. The two modes

Claude **decides per task and announces the mode + why**; the user can override
with a word at any time.

- **All-in-one (planner)** — status quo. Claude plans *and* implements directly.
  Default for: architectural/subtle work, ambiguous specs needing judgment, fast
  one-offs, or anything where delegation overhead exceeds the benefit.
- **Orchestrator** — Claude plans, decomposes, delegates implementation to Gemma,
  reviews, integrates, verifies. Default for: bulk/routine/mechanical,
  well-specified, parallelizable implementation.

**Mode ≠ sensitivity — keep them orthogonal.** The mode decision is about a task's
*nature* (subtle vs. mechanical), NOT its sensitivity. REVENANT work can and should
be delegated in orchestrator mode — Gemma is *local*, so delegating to it is exactly
the privacy win (sensitive code never touches third-party cloud). Sensitivity only
decides *which model* receives the work (the §8 routing guard), never *whether* to
delegate. A subtle/ambiguous REVENANT task stays all-in-one because it's subtle, not
because it's REVENANT.

**When uncertain which mode applies, default to all-in-one** (Claude does the work
itself) — the safe direction.

**Trigger mechanism (not "remember to"):** the always-on CLAUDE.md block instructs
Claude to invoke the `delegating-to-local-models` skill *upon entering orchestrator
mode*. The skill is the concrete artifact that loads the loop, model policy, and
`gemma-delegate` usage — so the methodology is enforced by an explicit instruction,
not by recall.

## 6. The orchestrator loop

`PLAN → IDENTIFY (sensitivity + tier) → DELEGATE (gemma-delegate) → REVIEW
(correctness/security/quality) → INTEGRATE (Claude owns architectural/critical
parts) → VERIFY (tests)`.

Here "INTEGRATE" means Claude personally owns the architectural/critical pieces and
reviews everything Gemma drafted before it lands.

Invariants:
- **Claude never commits unreviewed Gemma output.**
- Delegation changes *who drafts* the code, not *what gates it passes through*.
  Existing discipline (TDD, the project's planning system, verification gates,
  commit rules) applies unchanged.
- **Graceful degradation:** if the laptop is unreachable or `gemma-delegate` fails,
  orchestrator mode collapses to all-in-one (Claude does it itself). The methodology
  never blocks work — delegation is an optimization, not a dependency.

## 7. Model policy (evidence-locked)

- **Default delegation model = `gemma4:12b`, kept warm** (long `keep_alive`).
  Best quality-per-robustness; fully GPU-resident.
- **Fast-path = `gemma4` (E4B 8B)** — explicit opt-in for bulk/simple/speed-critical
  or long-context-where-speed-matters work. ~2× faster; accept minor quality/verbosity cost.
- **`gemma4:26b` = dormant tag, manual-only.** Not in any default path. **No
  demonstrated advantage exists** — our evidence shows the 12B matches its quality
  *and* beats it on long context (5/5 at 79K tokens, far faster). It is kept only
  because leaving the tag on the laptop is zero-cost, in case a future 24 GB+ GPU
  changes the economics. It is NOT justified by long context — the 12B is better
  there too. (Open question §12: keep vs. drop entirely.)

## 8. Routing & sensitivity guard

**Sensitivity definition (locked): anything REVENANT-related is sensitive.** It
must never go to a Chinese-origin model (`qwen3`, MiniMax, DeepSeek).

**Default for `--project` is `revenant` (fail-safe).** If the flag is omitted, work
is treated as sensitive and qwen3 is refused. `generic` must be passed explicitly.
Forgetting the flag therefore fails *safe*, never leaking to a Chinese-origin model.

**Two distinct concerns — don't conflate them:**
1. **On-laptop tier choice:** `gemma4:12b` (quality default) vs `gemma4` 8B (fast).
   Both live on the same laptop, so they do **not** fail independently — a sleeping
   laptop takes both out at once. 8B is a *speed* alternative, not a reliability one.
2. **Cross-machine fallback (laptop unreachable):**
   - **REVENANT work:** laptop → **cloud Claude (Claude does it itself)**. qwen3 (on
     the host, a different machine) is **excluded** regardless of reachability.
   - **Generic work:** laptop → qwen3 (host) → cloud Claude.

`gemma-delegate` treats the **actual call failure** (connection refused/timeout) as
the fallback trigger; a pre-call connectivity probe is only a latency optimization,
not the guard (the laptop can sleep between probe and call). "Cloud Claude" is not
something the script invokes — on REVENANT fallback the script exits with a distinct
code and Claude takes the work back in-context.

## 9. Context / performance guardrails

- **Always set `num_ctx` explicitly.** Ollama's default (~4K) silently truncates;
  Gemma 4 supports 128K–256K. Raise it generously for long-context tasks.
- **Set `num_predict` generously for long outputs** to avoid mid-answer truncation.
- **VRAM ceiling (12 GB) is the real bottleneck**, not the server. The 26B can't
  fit; the 12B and 8B do. A 24 GB+ GPU is the only thing that would make the 26B
  competitive — recorded as a known upgrade path, not a requirement.
- Use the native `/api/chat` endpoint, **not** the OpenAI-compat `/v1` route — the
  latter cannot control thinking and yields empty answers on thinking models.
- Default `think:false`. (Thinking burns the token budget before the answer.)

## 10. `gemma-delegate` — interface spec

**Responsibility boundary:** transport + guardrails ONLY. It does not decide what
to delegate, does not review output, does not integrate. Those are Claude's
judgment and stay with Claude. (This is why a deterministic script is appropriate
under the substrate rule: it is plumbing and guardrail enforcement, not the
deliverable.)

Behavior:
- Calls native `/api/chat` with `think:false`, `stream:false`, and tier-appropriate
  `num_ctx`/`num_predict`/`temperature`/`keep_alive`.
- Tier selection: `--tier quality|fast` → `gemma4:12b` (default) | `gemma4` (8B).
  `--model <tag>` for explicit override (e.g. manual 26B escalation).
- `--project revenant|generic` drives the sensitivity guard; **defaults to
  `revenant`**. With `revenant`, the script **refuses** to route to qwen3 under any
  circumstance (hard error + distinct exit code, not a warning).
- Reads task from `--task`/arg or stdin; `--files a.py b.py` reads & embeds file
  contents. **Before sending, it estimates prompt tokens vs the effective `num_ctx`
  and fails loudly (not silently truncates) if the embedded files would overflow** —
  prompting Claude to raise `num_ctx`, chunk, or trim.
- Treats the actual `/api/chat` call failure as the fallback trigger; exits with
  distinct codes for: success, laptop-unreachable (generic→try qwen3), and
  laptop-unreachable-on-REVENANT (Claude must take the work back itself). The script
  does NOT and cannot call "cloud Claude" — it signals.
- **Truncation detection:** inspects the response `done_reason`. If `"length"` (the
  model hit `num_predict`), the output is likely incomplete/garbled — the script does
  NOT silently return it; it either retries once with a larger budget or exits with a
  distinct "truncated" code so Claude can react. Setting `num_predict` generously is
  the prevention; this is the detection.
- Output: clean content to stdout by default; `--raw` for full JSON (tokens, timings).
- Config (endpoints, model tags, tier defaults) loaded from the **gitignored**
  `gemma-delegate.toml` or env vars — never hardcoded, never committed (§4a).

CLI sketch (`gemma-delegate` shown as shorthand; actually invoked by its absolute
deployed path, e.g. `~/.claude/skills/delegating-to-local-models/bin/gemma-delegate`,
or via a shell alias the skill documents):
```
gemma-delegate --tier quality --project revenant --files store.py \
  --task "Add a docstring and type hints to store_blob(); keep behavior identical."
```

## 11. Testing strategy

**Layer A — plumbing (does the script work?):** unit tests with the HTTP layer
mocked — arg parsing, payload assembly, tier/`num_ctx` defaults, fallback
selection logic, and the REVENANT→no-qwen3 refusal. Plus one live smoke
(connectivity + a real round-trip) gated behind an env flag.

**Layer B — model quality (is the output good?):** the eval harness prototyped
during design. Tasks paired with **hidden reference tests**; the runner extracts
the model's code, **executes it via subprocess with a timeout in a temp dir**, runs
the model's own generated tests, and scores granularly (partial credit),
distinguishing NO-CODE (instruction/retrieval failure) from wrong code.

**Code-execution risk (stated honestly):** this runs model-generated code with the
harness's privileges — it is NOT a true sandbox. Acceptable because the model is
trusted (local, US-origin) and the tasks are fixed/known, but the harness MUST:
- run as an **unprivileged user** with **no secrets in the environment**;
- apply a hard wall-clock timeout AND **resource limits via `setrlimit`** —
  `RLIMIT_CPU`, `RLIMIT_AS` (memory), `RLIMIT_NPROC` (fork-bomb guard), and
  `RLIMIT_FSIZE` (disk-exhaustion guard);
- **disable network** for the exec where the platform allows (e.g. `unshare -n`).

These caps are cheap and proportionate to a *trusted* source — they stop *accidental*
runaway (infinite alloc, fork loop, huge writes), which a timeout alone does not. A
full container/gVisor sandbox is a noted future step, warranted only if untrusted
models are ever added.

Uses:
1. Evidence-based model selection (done; reproducible).
2. **Regression gate**: re-run when the laptop's model tags or endpoint change; a
   quality drop fails loudly. Catches silent model swaps.

This is legitimate verification automation (deterministic code for verification is
explicitly sanctioned by the substrate rule).

## 12. Open questions

1. **Keep or drop the 26B?** Evidence says it's dominated here. Default decision:
   keep as documented manual-only escalation (cheap to leave a tag on the laptop).
   Revisit if a 24 GB+ GPU appears.
2. **Warming mechanism.** `keep_alive` on each call vs. a tiny periodic preload
   ping to keep the 12B hot. Lean: `keep_alive` is sufficient; add a preload only
   if cold-load latency proves annoying.
3. **qwen3 for generic work** — currently permitted as a fallback. If essentially
   all host work is REVENANT-adjacent in practice, qwen3 may be dead weight; let
   usage decide before investing in its path.

## 13. Implementation sequence (for the plan)

0. **Hygiene first:** add `**/gemma-delegate*.toml` (except `.example`) to
   `.gitignore`; site the live config at `~/.config/gemma-delegate/config.toml`
   (outside the repo); grep the repo for any leaked addresses before the first commit.
1. `skills/.../bin/gemma-delegate` + committed `.toml.example` + Layer A tests (TDD).
   Invoked by absolute deployed path; no PATH/deploy-script changes needed (the
   script rides the existing `skills/` symlink).
2. Productionize the Layer B eval harness from the design-time prototype (with the
   unprivileged/no-secrets/network-off exec hardening from §11).
3. `delegating-to-local-models` skill.
4. `CLAUDE.md`: add a **new, clearly-delimited managed block** (e.g.
   `<!-- BEGIN orchestration-delegation -->` … `<!-- END -->`) that points to the
   skill and carries the mode-selection + sensitivity rules. **Do NOT touch the
   existing `meta-engineering substrate` block** (it is generated externally from
   `brain/preferences.md`; its generator is not in this repo). Verify a `sync.sh`
   round-trip does not reformat or drop the new block before relying on it.
5. **Cleanup:** remove the orphaned `gemma4-coder` model from the laptop (it was
   built on the now-non-default 26B; `gemma-delegate` injects the system prompt
   per-call, so no baked model is needed).
6. Deploy via `sync.sh`; live smoke on the host.

## 14. Review status

- **Self-critique:** 5 rounds, converged (zero critical/important in final pass).
  Critical catches fixed: public-repo topology leak, fail-safe sensitivity default,
  broken deployment assumption (script wouldn't have deployed / nothing on PATH).
- **Independent critique — Gemma 12B (interim):** run via the delegation path itself
  (2026-06-08). Two additive findings folded: `setrlimit` resource caps in Layer B
  (§11), and `done_reason` truncation detection in `gemma-delegate` (§10). Other
  items were already covered or overstated.
- **Independent critique — Codex / GPT-5.4: PENDING (DEBT).** The mandated pass
  (per claude-config process) could not run — the Codex CLI is unavailable in this
  environment (no `codex`/npm). **Run it early in implementation when the CLI is
  available, and fold findings before first deploy.** Gemma is a weaker critic and
  does not satisfy this bar; it reviewed a methodology about itself.
