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

**2. For each issue found:**
- Classify: CRITICAL (breaks functionality or security), IMPORTANT (degrades quality), MINOR (cosmetic)
- Fix CRITICAL and IMPORTANT issues immediately
- Note MINOR issues but don't block on them

**3. After fixing, re-run the critique on the FIXED version.**

The loop ends when a full critique pass finds zero CRITICAL or IMPORTANT issues.

## Anti-patterns to catch

- **"This should work"** — prove it. Run it, trace it, test it. If you can't run it, trace the execution path mentally and identify where it would fail.
- **Placeholder values** — `<changed-files>`, `TODO`, `FIXME` in production code
- **Silent failures** — `except: pass`, `|| true`, `2>/dev/null` hiding real errors
- **Missing enforcement** — a rule with no mechanism to enforce it is a suggestion, not a rule
- **Stale references** — file paths, function names, env vars that don't exist anymore
- **Untested assumptions** — "the API returns X" without verifying
- **Cargo cult patterns** — copying a pattern without understanding why it works here
- **Artificial round caps** — if you're about to say "after N rounds, stop" — don't. Keep going.

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

- Zero CRITICAL and zero IMPORTANT issues in the latest round
- Flag when rounds are genuinely exhausted, not when a threshold is reached
- If the same structural problem keeps resurfacing across many rounds, the artifact needs a redesign — present the structural problems to the user and propose a redesign rather than continuing to patch
