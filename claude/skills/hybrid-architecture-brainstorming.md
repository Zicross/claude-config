---
name: hybrid-architecture-brainstorming
description: "Use when deciding between 2+ approaches, or designing architecture, APIs, protocols, data models, state machines, schemas, migrations, auth boundaries, or skills. Use when output will be battle-tested, stress-tested, or production-deployed. Use when a decision is important or hard to reverse. Default brainstorming mode — supersedes superpowers:brainstorming when any trigger applies. Applies even when the answer seems obvious, the task seems small, or you already started designing. NOT for typos, one-line fixes, renames, mechanical changes with one correct answer, or factual questions the user asked directly."
---

# Hybrid Architecture Brainstorming

## The Iron Law

**If ANY trigger below applies, you run all three phases. No exceptions that you author yourself.**

The only exceptions are:
1. The user issues an explicit, verbatim-like override ("just do X", "skip the brainstorm", "don't run the skill", "answer directly"). Silence, tone, or inference is NOT override.
2. The task verbatim-matches the Non-Trigger Whitelist.

**If you find yourself constructing a novel reason the skill should not apply, that is itself the trigger.** Stop. Run the skill. The rationalization you are authoring is exactly the anchoring pressure this skill exists to resist. The thought is the trigger.

## Letter vs Spirit

The spirit: **eliminate single-agent anchoring on decisions that will be lived with.**

Violating the letter IS violating the spirit. There is no "I followed the spirit but not the letter" defense. The letter is the spirit's enforcement mechanism. If the letter feels wrong in a specific case, the correct action is to run the skill and then write a follow-up note on why it felt wrong — not to skip it.

## Mandatory Triggers

Run this skill when ANY of these hold:

- [ ] Deciding between 2+ approaches, designs, libraries, protocols, or strategies
- [ ] Designing or substantially modifying: architecture, a system, an API, a protocol, a data model, a schema, a state machine, a migration, an auth/security boundary, a concurrency model, an evaluation framework, a threat model, a skill, a methodology doc
- [ ] Output will be battle-tested, stress-tested, production-deployed, or reviewed by procurement/security
- [ ] Decision is important or hard to reverse (schema changes, public APIs, committed interfaces, file formats, persisted data layout)
- [ ] A plan or spec is being written that downstream agents will execute
- [ ] Writing a new skill or substantially revising an existing one
- [ ] User has asked for a **recommendation** between alternatives: "how should I…" / "what's the best way to…" / "design X" / "figure out Y" (factual questions like "what are the tradeoffs between A and B" without asking for a recommendation are NOT in scope — answer directly)

**If ANY box is checked, run the skill. You do not get to weigh these against each other.**

## Non-Trigger Whitelist (Verbatim Match Required)

Skip the skill ONLY if the task verbatim-matches one of:

- Fixing a typo
- A one-line bug fix with one obviously correct answer (off-by-one, missing `await`, wrong variable name)
- A rename (variable, function, file) with no semantic change
- A mechanical refactor with a single correct transformation (extract constant, inline variable)
- A question the user has explicitly asked you to answer directly
- A task where the user has explicitly scoped out the skill

If the task is "like" one of these but not verbatim, it is **not** whitelisted. Run the skill.

## The Three Phases

### Phase 1 — User-Intent Alignment

**Precedence declaration (read this first):** When this skill's triggers apply, **this skill supersedes `superpowers:brainstorming`**. `superpowers:brainstorming` has a terminal rule ("The ONLY skill you invoke after brainstorming is writing-plans") and a HARD-GATE ("Do NOT invoke any implementation skill until design approved"). This skill subsumes and extends that flow — it does not violate it; it defers its terminal hand-off and adds Phases 2 and 3 between brainstorming's step 8 and its step 9.

**Execution pattern:** Invoke `superpowers:brainstorming` and follow its checklist **only through step 8** ("User reviews written spec"). When you reach brainstorming's step 9 ("Transition to implementation — invoke writing-plans"), **STOP**. Do not invoke `writing-plans`. Return control to this skill and proceed to Phase 2. Step 9 is **deferred**, not cancelled — it runs after Phase 3's user-approval gate.

Phase 1 pins down **requirements, constraints, threat model, success criteria, non-goals, open questions, AND the chosen lean triple for Phase 2** — NOT a chosen architecture.

**Constraint vs chosen-architecture distinction (critical):** Users often specify what look like architecture choices during Phase 1 ("must use Postgres," "must integrate with existing X," "no external dependencies"). These are **constraints**, not chosen architectures — record them in the requirements doc and they bound the Phase 2 solution space. A chosen architecture would be "the design should be event-sourced with CQRS" — a structural decision about HOW the system works internally. When in doubt, ask the user: "Is that a hard constraint the agents must work within, or one of several ways this could be designed?" Constraints → Phase 1. Architectural choices → Phase 2.

**Critical — state this to the user at Phase 1 start, verbatim or close:**

> "I'll pin down requirements with you here using the brainstorming flow. I will not lock the architecture yet — three parallel agents will each propose one independently in Phase 2, and I'll synthesize and critique in Phase 3."

**Why this steering matters:** `superpowers:brainstorming` step 4 proposes 2-3 approaches with a recommendation. If a user selects an architecture during Phase 1, Phase 2 collapses back to anchoring — the user is biased toward the Phase 1 choice and will reject the synthesis. The 2-3 approaches in Phase 1 are for **surfacing constraints the user had not articulated**, not for deciding the architecture.

**Worktree note:** `writing-plans` expects a dedicated worktree created by `brainstorming`. Since this skill follows brainstorming's flow through step 8, worktree creation happens normally. If brainstorming skips worktree creation on this machine, create one manually before Phase 3's hand-off (or note its absence — not blocking).

**Exit criterion:** the user explicitly confirms the requirements doc captures intent. Not "sounds good" — an actual affirmation at brainstorming's step 8.

**"Just go" handling:** "Just go" is one of the verbatim-like override phrases (see User Override Protocol below). It skips the ENTIRE skill, not just Phase 1. There is no path to "skip Phase 1 but keep Phases 2–3" — Phase 1 is the input to Phase 2; skipping it collapses the flow. If the user says "just go," ask once for clarification: "Override the brainstorming skill and answer directly, or run it?" If they confirm override, skip the skill and answer directly. If they meant "proceed with the skill efficiently," run Phase 1 normally — speed is not a concession on completeness.

**Phase 1 artifact (hand-off to Phase 2):** the spec file written by `superpowers:brainstorming`, at the path conventions that skill establishes (project-overridden if applicable), with an appended section containing exactly: `## Architecture decision\n\nDeferred to Phase 2 (hybrid-architecture-brainstorming).`

### Phase 2 — Three Parallel Independent Agents with Different Leans

Apply the pattern from `superpowers:dispatching-parallel-agents` (focused scope per agent, self-contained context, explicit output shape, parallel dispatch in one message). Note: that skill's triggers are debugging-focused ("3+ test files failing"); this usage extends its pattern to design-proposal dispatch. The pattern is general; the trigger list is narrower than the pattern's applicability.

Dispatch exactly **three** agents **in parallel** (one message, multiple tool calls). Each agent receives:

1. **The Phase 1 spec file path AND the full spec contents pasted in the brief** (path alone may not work if agents run in isolated contexts without filesystem access to this spec; paste to guarantee they have it, cite the path so synthesis references canonical location).
2. **A distinct lean** from the catalogue below. Leans must be orthogonal, not variants.
3. **Independence constraint, verbatim in the brief:** "You will not see the other agents' proposals. Do not hedge toward an imagined consensus. Commit to your lean." (State this even if the dispatcher guarantees it — defense in depth.)
4. **Fixed output contract** (this is the Phase 2 → Phase 3 contract): markdown with these exact sections: `Lean`, `Design`, `Why this satisfies each requirement`, `Tradeoffs accepted`, `Failure modes`, `What I deliberately rejected`.

**Lean catalogue** (pick three orthogonal ones appropriate to the decision):

- **Simplicity** — smallest thing that could possibly work; YAGNI maximalist
- **Defensive** — assume adversarial callers, hostile environment, byzantine inputs
- **Decoupling** — lowest coupling, most orthogonal components, easiest to replace parts
- **Testability** — easiest to test and verify in CI
- **Migration-safety** — minimizes risk to existing data or callers
- **Composition** — maximal reuse of existing skills / modules / patterns in the codebase
- **Performance** — fastest on the expected hot path
- **Rationalization-proofness** — (for skill design) hardest to skip under pressure
- **Extensibility** — (for protocols) cleanest forward-compat surface

Common strong triples: trust-root module → Simplicity ∥ Defensive ∥ Migration-safety. API for other code → Decoupling ∥ Testability ∥ Composition. New skill → Simplicity ∥ Rationalization-proofness ∥ Composition.

The lean triple is chosen in Phase 1 and recorded in the spec, so it cannot retroactively be picked to favor a pre-formed opinion.

**Parallel, not sequential.** Dispatch all three in one tool-call block. "Running one first to check" is sequential anchoring. If you catch yourself splitting dispatch, re-dispatch in parallel.

**Agents do not see each other's work.** Period. Not a summary, not a headline, not a frontmatter peek. Independence is the mechanism.

**If proposals return near-identical — triage, do NOT add a fourth agent:**

1. Read each proposal's `What I deliberately rejected`. If all three rejected the same alternatives for the same reasons → the space is genuinely narrow. Accept convergence, document it ("no meaningful alternative found"), proceed to Phase 3 with the one design.
2. If rejections differ but final designs converged → leans were too weak. Re-dispatch with sharper lean differentials (e.g., pair Simplicity with Defensive, not Simplicity with Composition).
3. Never invent a fourth agent to break ties. Convergence is a signal, not a problem to route around.

**If one or more agents fail (error, timeout, unusable output):** re-dispatch ONLY the failed agent(s) in parallel with the survivors still in context (the survivors' completed proposals do NOT get shown to the re-dispatched agents — independence constraint still holds). Do NOT proceed to Phase 3 with fewer than three proposals; three is the minimum for triangulation. If the same agent slot fails twice, substitute the lean with a different orthogonal one from the catalogue rather than retrying indefinitely.

### Phase 3 — Synthesis + Unbounded Self-Critique

1. Read all three proposals.
2. Write **one hybrid design** that takes the strongest elements from each, with a **synthesis rationale** that names which element came from which proposal and justifies why the hybrid beats any individual proposal.
3. Invoke `self-critique`. Follow that skill exactly — unbounded rounds, no round cap, continue until a full critique pass finds zero CRITICAL and zero IMPORTANT issues. Use tools (grep, Read, Bash) during critique, not pure reasoning, per `feedback_self_critique_tools.md`.

**If self-critique invalidates the synthesis — three-tier routing:**

- **Invalid borrowed element only** → swap the element with the corresponding one from another proposal, re-critique. Stay in Phase 3.
- **Invalid synthesis strategy** (the three designs do not actually compose — their assumptions conflict) → return to Phase 2 with the flaw documented as an additional constraint in the agent briefs. Phase 1 requirements still stand.
- **Invalid requirements** (Phase 3 surfaces a requirement gap Phase 1 missed) → return to Phase 1 with the user. Rare but legitimate.

**Phase 3 artifact (hand-off to `writing-plans`):** the Phase 1 spec file, with three appended sections:

- `## Architecture decision` — the synthesized design (drop-in replacement for the "Deferred" placeholder).
- `## Synthesis rationale` — element provenance (which proposal each element came from, why it beat alternatives).
- `## Critique log` — rounds run, issues found per round, fixes applied, and final round showing zero CRITICAL/IMPORTANT issues.

## Phase 3.5 — User-Approval Gate (MANDATORY)

Before invoking `writing-plans`, present the final synthesized design + critique log to the user and obtain explicit approval. This re-inserts the step `superpowers:brainstorming` step 8 would have run on an un-critiqued single design — applied now to the rigorously-produced synthesis.

> "Phase 3 complete. Final design + synthesis rationale + critique log are in `<spec-path>`. Please review and approve before I invoke `writing-plans`."

Wait for explicit approval (not "sounds good" alone — affirmation that the spec is ready for planning). If the user requests changes, apply them, re-run `self-critique` on the changed sections, then re-request approval.

**Why this gate exists:** Brainstorming's HARD-GATE ("Do NOT invoke any implementation skill until design approved") is load-bearing. By deferring brainstorming's step 9, this skill also defers the design-approval gate that step 9 depends on. This phase re-inserts it explicitly so the HARD-GATE is honored.

## Terminal Hand-off to `writing-plans`

Only after Phase 3.5 approval, invoke `superpowers:writing-plans`. It consumes the final spec exactly as if `superpowers:brainstorming` had run to completion — the file shape is a superset. No changes needed to `writing-plans`.

## Red Flags — Stop Immediately If You Notice Yourself Thinking

- "This case is different"
- "The answer is obvious"
- "I already have a good design in my head"
- "Three agents is overkill for this"
- "I'll just brainstorm with the user — that's basically Phase 2"
- "I'll run the agents sequentially to save context / tokens / time"
- "Two agents is enough; the third adds nothing"
- "I'll skip Phase 3 — Phase 2 agents already critiqued things"
- "I already started designing; running the skill now wastes that work"
- "The user wants a quick answer; the skill would frustrate them"
- "This is a small spec; the skill was meant for bigger decisions"
- "I'll run the skill later if the first attempt doesn't work"
- "I'll describe what the skill would do instead of running it"
- "I'll run the skill mentally / simulate it in my reasoning"
- "The user will review my output, so I don't need three agents"
- "I've already invoked superpowers:brainstorming, so I'm covered"

**Every item here is a rationalization this skill has seen before.** Thinking it confirms the skill's premise. **The thought is the trigger.** Run the flow.

## Rationalization Rebuttal Table

| Verbatim rationalization | Reality | Required action |
|---|---|---|
| "The answer is obvious." | Obvious answers survive three agents trivially; you lose nothing by checking. Non-obvious answers masquerading as obvious are exactly what the skill catches. | Run the flow. |
| "I already have a good design." | Your design is the anchor. Pre-formed designs bias single-agent brainstorming and must not enter Phase 2. | Do not reveal your design. Run Phase 1 with user, dispatch Phase 2 blind. |
| "Overkill for this task." | Size is not in the trigger list. Authoring a size threshold is authoring a novel exemption — itself a trigger. | Run the flow. |
| "I'll skip Phase 2 and brainstorm with the user." | User + you is one perspective refracted. Three independent agents is three perspectives. Not substitutable. | Run Phase 2 in parallel. |
| "I'll run the agents sequentially." | Sequential agents leak context through your framing of the next brief. Independence is the mechanism. | Dispatch all three in one tool-call block. |
| "Three designs will be hard to merge." | Hard merges signal real divergence. That difficulty IS the value. Easy merges mean the skill added little this time. | Do the hard merge in Phase 3. |
| "Skip Phase 3 — Phase 2 already had reviewers." | Phase 2 agents critiqued their own proposals. The synthesis is a new artifact with new failure modes and no reviewer. | Run self-critique unbounded. |
| "This case is different." | Every pressured case feels different. "Different" is the pressure signal, not an exemption. | Run the flow. |
| "The skill was for bigger decisions." | No size threshold in triggers. Authoring one now is a novel exemption — itself a trigger. | Run the flow. |
| "User wants a quick answer." | User agreed to the skill. Override is verbatim, not inferred. Inferring puts words in their mouth. | Run the flow unless the user has issued verbatim override. |
| "I already know the best approach." | Identical to "I have a good design." The confidence IS the anchor. | Run Phase 2 blind. |
| "Running this for a small spec wastes time." | Bad small specs amortize into rework that exceeds skill cost. | Run the flow. |
| "I'll run Phase 2 and Phase 3, skip Phase 1 — user already told me what they want." | Without the Phase 1 artifact, three agents get three interpretations of the user's words, not three designs for the same problem. | Write the spec, get explicit confirmation. |
| "Three agents agreed; self-critique is redundant." | Agreement is not correctness. Three agents can share a blind spot. Self-critique is the test for shared blind spots. | Run self-critique. |
| "I'll describe what I would do if I ran the skill." | Describing is not running. The mechanism is independent dispatch; description reproduces single-agent anchoring with extra steps. | Actually dispatch. |
| "The user is watching and will be annoyed." | User built this skill because bad designs annoyed them more. Revealed preference beats inferred preference. | Run the flow. |
| "I started designing already; stopping wastes that work." | Sunk cost. The started design is exactly the anchor the skill breaks. Discarding is the skill working as intended. | Discard. Run Phase 1. |
| "I'll cap self-critique at N rounds." | `self-critique` is explicitly unbounded. Capping violates a skill that has its own rationalization rebuttal on this exact point. | Run self-critique unbounded. |
| "Self-critique already approved the synthesis, skip Phase 3.5." | `self-critique` is technical review. Phase 3.5 is user approval. Different checks, different failure modes. Brainstorming's HARD-GATE demands user approval, not agent approval. | Run Phase 3.5. |
| "The user will review it during writing-plans anyway, skip Phase 3.5." | `writing-plans` consumes the spec as approved input; it does not re-approve design decisions. Approval must happen BEFORE writing-plans, per brainstorming's HARD-GATE. | Run Phase 3.5. |
| "The design is so good I don't need formal approval for Phase 3.5." | Confidence in the design is the same anchor the skill exists to break. High confidence post-Phase-3 is not evidence of correctness — the user's review is. | Run Phase 3.5. |

The mechanism across all of these: **the rationalization is evidence the skill is needed, not evidence it can be skipped.** This cognitive reversal is the skill's core move.

## Loophole Closures

- **"Partial skill" is not a thing.** All three phases or you did not run the skill. Phase 1 + Phase 3 with a solo Phase 2 is skipping.
- **"Mental dispatch" is not a thing.** Simulating three agents in your reasoning is single-agent brainstorming wearing a costume. Actually dispatch.
- **"Recursion exemption"** ("this skill is itself a decision between approaches, so it's recursive, so I'll skip it") — no. The skill is the designated default decision procedure, not a decision between procedures. Invoking it is not a decision-between-approaches.
- **"I'll run it for the next decision instead."** Each trigger is independent. Deferring is skipping.
- **"User review substitutes for Phase 2."** Review catches errors in one design; Phase 2 generates the design space. Not substitutable.
- **"I'll run two agents because the third lean is dominated."** Dominated leans are the most informative — they confirm dominance or reveal it was wrong. Two agents can collude on a shared blind spot.
- **"I already invoked superpowers:brainstorming, so Phase 1 is over and Phases 2–3 are optional."** No. This skill's Phase 1 USES `superpowers:brainstorming` with a scope carve-out. Invoking the parent skill outside of this skill's flow is not Phase 1.

## User Override Protocol

User override always wins. Override must be **explicit and verbatim-like**:

- "Just do X" / "just write it" / "skip the brainstorm" / "don't run the skill" / "I don't need three agents for this" / "answer directly"

Override is **not**:

- User speaking in a hurried tone
- User asking a question in a way that suggests they want an answer
- User not mentioning the skill
- Your inference that the user would not want the skill

When the decision is the **user's**, not yours:

- User asks for your **recommendation** between alternatives → skill applies (your recommendation is the non-trivial decision).
- User has **already decided** and is asking you to implement ("we're using Postgres, add it") → skill does NOT apply.
- User asks a **factual question** ("what are the tradeoffs between A and B?") without seeking a recommendation → skill does NOT apply; answer directly.

When uncertain: **ask**. "This triggers hybrid-architecture-brainstorming (three parallel agents + synthesis). Run it, or do you want a direct answer?" One sentence is cheap; wrong-skill invocation is not.

## Post-Run Artifact

After a successful run, the spec file (and, where applicable, the conversation) must contain:

1. The Phase 1 requirements doc (explicitly approved by the user — verbatim affirmation, not "sounds good")
2. The full text of the three Phase 2 proposals, or links/paths to the files containing them (summaries are not sufficient — provenance in the synthesis must be auditable against full proposals)
3. The Phase 3 synthesis with element-by-element provenance
4. The self-critique log (rounds, issues found per round, fixes applied, final zero-CRITICAL/IMPORTANT confirmation)
5. Record of Phase 3.5 user approval (the user's explicit affirmation that the final design is ready for `writing-plans`)

If any is missing, the skill was not run, regardless of what the conversation says about it.

## Composition Map

| Skill | Relationship | Notes |
|---|---|---|
| `superpowers:brainstorming` | **INVOKE** inside Phase 1 with scope carve-out (defer its step 9 hand-off). | Triggers overlap — this skill wins when any trigger above applies; parent skill handles everything else. Announce which skill is driving. |
| `superpowers:dispatching-parallel-agents` | **INVOKE** to implement Phase 2. Rely on its "Agent Prompt Structure." | Never re-implement its prompt templating in this skill. |
| `self-critique` | **INVOKE** unbounded inside Phase 3. | Follow its rules exactly, including "do not cap rounds." The "use tools not reasoning" guidance lives in the user's `feedback_self_critique_tools.md` memory (project-specific) — the same principle applies here: run grep/Read/Bash during critique rather than deliberating in isolation. |
| `superpowers:writing-plans` | **HAND OFF TO** at terminal. | Consumes final spec as if `brainstorming` had run to completion. No modification needed. |
| `superpowers:writing-skills` | **REFERENCE** (authoring-time). | Used to write this skill; not invoked at runtime. |
| `superpowers:executing-plans` / `superpowers:subagent-driven-development` | **STAY OUT OF THE WAY.** | Consume plans produced downstream of this skill; no runtime coupling. |

## Failure Modes (Honest)

- **Lean drift.** I pick the three leans. If I pick three near-identical axes, Phase 2 produces three near-identical proposals and the skill adds little. Mitigation: lean catalogue + strong-triple examples; still a judgment call.
- **Phase 1 bloat.** No cap on requirements-doc length. Under time pressure a disciplined agent might over-invest in Phase 1 and rush Phases 2–3. Not currently closed.
- **Self-critique depends on `self-critique`.** If that skill is weak on the machine, Phase 3 collapses to one pass. Mitigation: explicit expectation of unbounded rounds in the skill body; a capped future `self-critique` would violate this skill's expectations visibly.
- **Parallel-dispatch regression.** If `superpowers:dispatching-parallel-agents` ever defaults to showing earlier outputs to later agents, independence breaks. Mitigation: the "do not see each other's work" constraint is in each agent brief, defense-in-depth.
- **Over-invocation fatigue.** If triggers fire too often, the user resents the skill and Claude starts rationalizing outs. The Non-Trigger Whitelist is the pressure valve — it must stay tight but real. Honest risk, no perfect fix.
- **Phase 1 architecture lock-in via parent skill.** `superpowers:brainstorming` step 4 proposes 2-3 approaches with a recommendation. If a user locks one during Phase 1, Phase 2 is anchored. Mitigation: the explicit steering script at Phase 1 start; still depends on me running Phase 1 correctly.
- **Jurisdictional seam with `superpowers:brainstorming`.** Both match "design a new feature." If the dispatcher picks the parent skill, step 9 transitions straight to `writing-plans` and this skill never runs. Mitigation: the stronger-signal triggers in this skill's description (2+ approaches, architecture, protocols); still the weakest seam.

## Cost Awareness

Three parallel agents + unbounded self-critique costs more than single-agent brainstorming. Intentional — the cost buys independent solution-space exploration no single agent can produce. If budget is a real constraint, the lever is for the **user** to explicitly narrow the Mandatory Triggers (e.g., by amending this skill). Claude does NOT self-author a size threshold — that is the exact "overkill for this task" rationalization that the rebuttal table forbids. User authorization > self-authorization. Within a triggered run, the flow is not negotiable.
