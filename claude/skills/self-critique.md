---
name: self-critique
description: "Use on designs, architecture, plans, skills, and complex code before presenting to user. NOT needed for trivial edits. Runs UNBOUNDED critique loops until genuinely nothing remains. Do NOT cap at any round count."
---

# Self-Critique Protocol

Run this on the artifact (plan, design, code, skill, config) BEFORE presenting it as complete. This applies globally across all projects.

## Core Rule

**Do NOT set a round limit.** Continue until a round genuinely finds zero issues.

**Why this rule exists:** Isaac identified that I was artificially capping self-critique at 5 rounds, then 10, then 15. Each time the cap was raised, real issues were found that the previous cap missed — shell injection vulnerabilities, CJK input handling bugs, clipboard residue leaks, /proc visibility across users, Chromium flag fingerprinting. The constraint was self-imposed and produced incomplete analysis. Unbounded critique is not optional — it is the only mode that works.

Do not count rounds. Do not set mental limits. Do not optimize for speed during critique — optimize for finding every real problem.

## The Loop

Repeat until the critique round finds ZERO actionable issues:

### Round N:

**1. Attack the artifact from these angles:**

- **Does it actually work?** Not "would it theoretically work" — trace the exact execution path. What breaks? Run it if possible.
- **What's missing?** What inputs, edge cases, or failure modes are unhandled?
- **What's wrong?** Logic errors, incorrect assumptions, stale references, wrong names/paths
- **What's fragile?** What breaks if the environment changes (different OS, different Python version, network down)?
- **What fails silently?** Bare `except: pass`, unchecked return values, swallowed errors
- **What's untested?** Is there a way to verify this works before deploying it?
- **Does it actually get triggered?** For skills/hooks: is there a concrete mechanism that causes this to run, or does it rely on someone remembering?
- **Security?** Shell injection, credential exposure, path traversal, input sanitization

**2. USE TOOLS — DO NOT JUST REASON.**

This is the single most impactful behavior for deep critique. Do not sit in your head and guess. Open the codebase and verify.

- **Grep for every caller.** If you're removing/changing a function, grep the entire repo for every file that imports or calls it. Cross-check each against the spec. Do not assume you know all the callers.
- **Read the actual files.** If the spec says "table X has constraint Y," open the schema file and check. If you're claiming "this method does Z," read the method.
- **Follow dependency chains.** When you find a caller, ask: what does THAT caller depend on? What calls it? Trace outward until you hit a leaf.
- **Count and verify completeness.** After tracing all callers/references, enumerate them: "14 files import from this module — all 14 are accounted for in the spec." If you can't make that statement, you haven't finished.
- **Check non-code files.** Documentation, config files, READMEs, and methodology docs all reference code paths. Grep for function names, file paths, and class names in markdown too.
- **Trace concrete example inputs through the flow.** Don't just ask "are all input types handled?" abstractly — pick 6-8 specific inputs that span the variation space and walk each one through every stage of the pipeline. `[[Note]]`, `[[Note.md]]`, `[[Folder/Note]]`, `[[paper.pdf]]`, `![[image.png]]`, `[[]]`, `[[Unknown]]`. For each: which branch does it hit? What's the output? Does it produce the behavior you actually want? This technique catches bugs that "have I covered all cases?" thinking misses — because the bug isn't a missing case, it's a WRONG transformation on a case you thought was handled. Five of the most serious bugs a recent session caught late (.md suffix handling, attachment-link classification, embed backlink gap, off-by-one path traversal, internal section contradictions) would have been caught much earlier with disciplined example-tracing.
- **Run the code/SQL in a REPL; don't just reason about it.** For any claim about DB, API, or library behavior, write a tiny script (`py -c '...'` or `py << EOF`) that exercises the exact pattern and verify the output. You will be wrong about behavior more often than you expect: a recent session found ATTACH isn't idempotent, `PRAGMA foreign_key_check` returns rows not raises, SQLite accepts NULL for TEXT PRIMARY KEY, `INSERT OR IGNORE` is needed for re-run safety, CSV BOM breaks column lookups, `julianday()` on NULL silently breaks joins — every one of those was wrong in the spec until a REPL test proved it. Cost per test: ~60 seconds. Yield: catches an entire class of bugs that reasoning produces confidently-wrong answers about.
- **Query real data when the spec touches real data.** Migration specs, backfill logic, and schema changes must be validated against the actual production database, not just synthetic fixtures. A spec that looks sound and passes unit tests can match **zero rows** against the real schema because you assumed URL-join where the actual data model is county-based, or because the sets you thought overlapped are disjoint. Run the spec's proposed queries against the live DB during critique, count the matches, and verify the numbers match what you expected. If they don't, the spec is wrong about the data, not the data wrong about the spec.
- **Verify arithmetic and counts literally.** If the spec says "three levels up," count three levels. Don't trust the number because it sounds right. Off-by-ones in path traversal, indexing, and iteration are specification-level bugs that look fine until you do the math. Same for "X exists": if the spec claims "24 such blobs exist," run `SELECT COUNT(*)` and verify. A recent session's "24" was actually 71 because only one pattern variant was counted.

**3. LOOK FOR INTERACTIONS, NOT JUST OMISSIONS.**

Early rounds find obvious problems: missing files, forgotten methods, wrong paths. These are easy. The real issues live in *interactions between components* that the artifact changes:

- **Cross-boundary references.** Does component A reference something in component B that's being moved/deleted? Is that reference enforced (FK, import) or informational (text field, comment)?
- **Constraint cascades.** If you change a CHECK constraint, enum, or type definition, what code writes values that must satisfy that constraint? Will existing data violate the new constraint?
- **Concurrent access.** If two tools/processes access the same resource, does the change create a race condition, locking issue, or write conflict?
- **Import path breakage.** If you move a file, every import path to it breaks. Trace them all. Also consider *transitive* imports — A imports B which imports C; moving C breaks A even though A doesn't directly reference C.
- **State assumptions.** Does code assume "this table exists" or "this field is populated"? After the change, are those assumptions still valid?
- **Column renames break readers silently.** If a column is renamed (even within a refactor), every SELECT, every ORM binding, every UI property access, every test fixture must be updated. Grep for the old name in `.py`, `.ts`, `.tsx`, `.sql`, `.md`, and test files. A renamed column that lingers in one caller produces "no such column" errors at runtime; a renamed column that lingers in a UI type silently drops from responses with no error. Expect to find 6-15 sites per rename across a medium codebase.
- **Code-vs-DB cutover sequencing.** A migration that renames/drops columns breaks every live code path that names them, the instant it commits. If the migration runs before the code-refit PR merges, the coordinator/server is broken until the PR lands. The spec must either: (a) declare code + DB cutover atomic, (b) use backward-compatible SQL aliasing during a transition window, or (c) deploy with the DB in the new shape AND the code ready AND the old process stopped. Leaving this unspecified guarantees an on-call page.

**4. For each issue found:**
- Classify: CRITICAL (breaks functionality or security), IMPORTANT (degrades quality), MINOR (cosmetic)
- Fix CRITICAL and IMPORTANT issues immediately
- Note MINOR issues but don't block on them

**5. After fixing, re-run the critique on the FIXED version.**

The loop ends when a full critique pass finds zero CRITICAL or IMPORTANT issues.

## Premature Convergence — The Real Failure Mode

The original version of this skill focused on "don't cap rounds." But round caps aren't the primary failure. **The primary failure is stopping because it *feels* like you're converging.**

Symptoms of premature convergence:
- "The last few rounds only found minor issues"
- "Severity is decreasing across rounds, so we must be close to done"
- "I'm seeing the same patterns now"
- "I think I've covered all the angles"
- "Rounds feel like they're converging"
- "I've been at this a while and should wrap up"
- "The user hasn't asked for more, so probably good enough"

These feelings are unreliable. Test them:

**Severity-decline is not completeness.** A real-world session ran 10 rounds, found issues diminishing in severity, declared converged — then ran 20 more rounds under external pressure and found FIVE CRITICAL bugs (off-by-one, contradictions between sections, missing behavior for specific input types). Severity-decline means later rounds are using exhausted techniques, not that fewer bugs remain. Switching techniques (concrete tracing, math verification, cross-section consistency) reveals whole new categories of critical issues.

**The "I keep finding smaller things" pattern is technique-exhaustion in disguise.** When rounds N+1, N+2, N+3 all find MINOR issues, your instinct says "I'm converging." The instinct is wrong. What's actually happening: you've exhausted technique A and are scraping its dregs. Switching techniques at that moment typically yields 3-5 new CRITICAL/IMPORTANT finds, not more minor ones. A recent session at round 30 kept finding minor stale-reference fixes via re-reading; switching to concrete-trace (running 8 specific inputs through the CHECK constraint, running the proposed backfill SQL against real data, simulating migration re-run) surfaced six CRITICALs in five rounds, including: the entire backfill strategy matched zero rows against real data; the migration's INSERT would fail on re-run (needs OR IGNORE); a column-rename broke three reader paths not listed in the spec. When severity drops to minor: that's the signal to switch techniques, not the signal to stop.

**Social/completion pressure is a tell, not a signal.** If you feel pressure to declare "done" because it's been many rounds, or because the artifact looks thorough, or because you're worried about seeming indecisive — that pressure is a bug, not evidence. The artifact doesn't get more complete because you're tired of reviewing it.

**Before declaring critique complete, ask yourself:** "Have I actually exhausted the critiques, or do I just think I have?"

If you can't answer with specific evidence — "I grep'd every importer, all 14 are accounted for; I checked every documentation file that references the changed components; I traced every cross-boundary interaction" — then you haven't exhausted them.

**What breaks premature convergence:**
- Switch from reasoning to tool use (grep, read files, check actual state)
- Switch from checking the artifact to checking *everything the artifact touches*
- Switch from "what's wrong with this section" to "what breaks in the rest of the system because of this section"
- Ask: "What would someone who just walked into this codebase notice that I've gone blind to?"

## The Quality Progression

Critique rounds follow a predictable quality progression. If you stop before reaching the later stages, you're leaving real issues on the table.

| Stage | What you find | How |
|-------|--------------|-----|
| **Omissions** (rounds 1-3) | Missing files, forgotten methods, wrong paths, incomplete lists | Reading the spec against itself |
| **Inconsistencies** (rounds 3-6) | Sections that contradict each other, mismatched assumptions | Cross-referencing sections |
| **Interactions** (rounds 5-10) | Cross-database references, constraint cascades, import chain breaks, audit gaps | Grep + file reads + dependency tracing |
| **Environmental** (rounds 8+) | Race conditions, path resolution assumptions, migration safety, backward compat | Simulating execution in different scenarios |
| **Concrete-trace bugs** (rounds 10+, often labeled CRITICAL) | Wrong transformation on a specific input you thought was handled; off-by-one in arithmetic; logic that reads correct but runs wrong | Walking specific example inputs through every stage |
| **Behavioral-model bugs** (rounds 10+, often labeled CRITICAL) | Wrong assumption about how a DB/API/library actually behaves (ATTACH non-idempotent, PRAGMA returns rows, NULL propagation in `julianday`, `INSERT OR IGNORE` semantics, WAL visibility) | REPL execution of the exact pattern; print the results |
| **Real-data bugs** (rounds 10+, often labeled CRITICAL) | Spec's assumed data model doesn't match production; zero-match joins; disjoint sets you assumed overlapped; phantom references | Running proposed queries as `SELECT` against the live DB, counting hits, sanity-checking numbers |
| **Emergent** (rounds 10+) | Issues that only appear when multiple changes combine | Holding the full change set in mind at once |

If your critique only found omissions and inconsistencies, you stopped too early. The interaction and concrete-trace stages are where the CRITICAL bugs live — and they look subtle enough that earlier rounds' scanning-for-gaps techniques don't catch them. **Severity does not monotonically decrease across rounds.** A session that found mostly minor issues in rounds 5-10 went on to find five critical bugs in rounds 20-40 by switching techniques.

## Anti-patterns to catch

- **"This should work"** — prove it. Run it, trace it, test it. If you can't run it, trace the execution path mentally and identify where it would fail.
- **Reasoning about DB, API, or library behavior without running it.** Your mental model of `ATTACH`, `PRAGMA foreign_key_check`, `INSERT OR IGNORE`, JSON decoding, timezone comparison, file locking, async ordering — all of these will be wrong sometimes, and you will be *confidently* wrong. Open a REPL (`py -c`, `py << EOF`, `node -e`, `sqlite3 :memory:`) and execute the exact pattern before trusting your spec. A session that thought it knew SQLite behavior cold still hit: ATTACH-not-idempotent, PRAGMA-returns-rows, TEXT-PK-accepts-NULL, `julianday(NULL)` silently breaking joins, `sqlite_sequence` auto-maintenance behavior. Every surprise was a spec bug.
- **Trusting a number in the spec without measuring.** "24 X exist" is an empirical claim. Run `SELECT COUNT(*)` and compare. A recent spec said "24 pinyin blobs"; the real number was 71 (only one pattern variant had been counted). Off-by-by-counting is as bad as off-by-one.
- **Claiming "matches" without querying.** "The backfill matches this row to that blob by source_url" is a testable claim. Run the proposed `UPDATE` as a `SELECT` against live data and count hits. A naive URL-join spec once passed every synthetic-fixture test and matched **zero** rows against the real DB because the production provenance model was county-based, not URL-based.
- **Placeholder values** — `<changed-files>`, `TODO`, `FIXME` in production code
- **Silent failures** — `except: pass`, `|| true`, `2>/dev/null` hiding real errors
- **Missing enforcement** — a rule with no mechanism to enforce it is a suggestion, not a rule
- **Stale references** — file paths, function names, env vars that don't exist anymore. After major spec refactoring, re-grep the spec for step numbers and internal cross-references that drifted.
- **Untested assumptions** — "the API returns X" without verifying
- **Cargo cult patterns** — copying a pattern without understanding why it works here
- **Artificial round caps** — if you're about to say "after N rounds, stop" — don't. Keep going.
- **Reasoning without tools** — if you've been critiquing for 3+ rounds without opening a file, running a grep, or executing a REPL snippet, you've gone shallow. Use tools.
- **Checking the artifact in isolation** — the artifact changes a system. Critique the system's response to the change, not just the artifact's internal consistency.
- **Declaring done because issues felt like they got smaller** — severity-decline is technique-exhaustion, not completeness. When severity drops, switch techniques instead of stopping. Move to concrete input tracing, REPL verification, real-data queries, cross-section consistency checks, or arithmetic verification.
- **Declaring done because many rounds have passed** — the round number is not evidence. Round 42 is no more complete than round 10 if you're using the same techniques. What matters is technique-coverage, not round-count.

## Beyond self-critique — knowing when to escalate

Self-critique has a ceiling. The author and the reviewer are the same mind, sharing the same blind spots. After ~20 rounds of thorough critique with genuine technique-switching, the marginal value of further self-critique drops sharply — not because the artifact is bug-free, but because you've saturated what one perspective can find.

Signs you've hit the self-critique ceiling:
- The issues you find in a new round are tiny wording improvements, not behavioral gaps.
- You're re-finding issues you already fixed and forgot.
- You're starting to fabricate issues to justify continuing.
- You can answer "what technique haven't I tried?" with "none that I can think of."

At that point, the next completeness test is not another self-critique round — it's an **external check**:

1. **Independent reviewer** — an agent (or human) who didn't author the artifact, with fresh eyes. Prefer differentiated roles over parallel duplicates: one adversarial reviewer, one implementer (tries to build from it and reports what's missing), one user-mindset reviewer (runs it mentally against real inputs). Parallel-identical reviewers share your blind spots and help less than you'd hope.
2. **Implementation stress** — moving to writing-plans / execution. Every question the planner has to ask is a spec gap. Specs that survive contact with implementation are complete; specs that don't, aren't. This is often the strongest completeness test available.
3. **User push** — when the user asks "are you sure?", take it as a real signal, not social friction. They're often right to doubt, and the cost of one more round is much lower than the cost of shipping a critical bug.

The self-critique skill is not infinite. Recognize its limits, then use the appropriate next tool.

## Output format

```
[SELF-CRITIQUE Round N]
Issues found: X critical, Y important, Z minor
- [CRITICAL] description → fix applied
- [IMPORTANT] description → fix applied  
- [MINOR] description (noted, not blocking)

[SELF-CRITIQUE Round N+1]
Issues found: 0 critical, 0 important, 1 minor
- [MINOR] description (noted)

CRITIQUE COMPLETE: N rounds, X total fixes applied
```

## When to stop

Stop only when ALL of these hold:

- Zero CRITICAL and zero IMPORTANT issues in the latest round.
- You've used a diverse set of techniques — not just re-reading. At minimum: grep/file-reads for cross-references, concrete example tracing, **REPL execution of behavioral claims** (for DB/API/library specs), **real-data querying** (for specs that touch existing data), cross-section consistency checks, arithmetic verification. If all your rounds used one or two techniques, technique-exhaustion is masquerading as completeness.
- The last TWO-plus rounds used DIFFERENT productive techniques and still found nothing. One zero-finding round isn't enough; it could be the technique exhausting. Two zero-finding rounds using different techniques confirms saturation.
- You can affirmatively state specific evidence, naming the technique and the artifact: "I traced 8 specific input shapes through every stage of the CHECK constraint — all behave per spec. I grep'd every importer of `foo_module`, all 14 are accounted for in the spec. I ran the backfill SQL as a SELECT against the live DB; 0 matches as expected per §7b's 'zero rows' claim. I verified the arithmetic in three places." If you can't produce that kind of concrete sentence, you haven't finished — you've just gotten tired.
- The last round's technique was one you'd already proven productive — it didn't find issues because none were there, not because you stopped looking.

If the same structural problem keeps resurfacing across many rounds, the artifact needs a redesign — present the structural problems to the user and propose a redesign rather than continuing to patch.

After ~20 rounds with genuine technique-coverage and still no new issues, further self-critique is diminishing returns. At that point **escalate to external review or implementation stress** (see "Beyond self-critique" above) instead of running more rounds.

**Never stop because it "feels" done, because severity decreased, or because many rounds passed.** Stop because you have evidence it's done.

**User push is often right.** If the user asks "are you sure we're done?" after you've declared complete — take it as an investigative signal, not social friction. Return to critique with a technique you haven't used, and expect to find real issues. Sessions that declared "done" and were questioned typically found 2-5 more CRITICALs in the next 5 rounds. The cost of one more round is much lower than the cost of shipping a broken spec. Escalate with new technique first, then if still nothing, escalate to external review.
