---
name: development-hygiene
description: "MANDATORY after completing any code change: new module, feature, bug fix, or refactor. Also MANDATORY at session end. Enforces cleanup, commit discipline, documentation, and verification. Failure to run this skill is what causes the repo to accumulate uncommitted files, stale docs, and lost context."
---

# Development Hygiene Checklist

Run this COMPLETELY. Do not skip sections. Output a brief summary of what you checked and what you fixed.

## Step 1: Uncommitted file audit

```bash
git status --short
```

If there are ANY uncommitted changes:
- Group them by purpose (feature code, tests, docs, config, debug artifacts)
- Commit each group with a descriptive conventional commit message
- If a file is a scratch/debug artifact, either delete it or add to .gitignore
- **NEVER leave uncommitted changes at session end**

Report: "X files committed in Y commits" or "Working tree already clean"

## Step 2: Debug cruft scan

Scan ALL files you touched this session:

```bash
# Rust debug prints
grep -rn "println!\|dbg!\|eprintln!" <changed-files> | grep -v "#\[cfg(test)\]" | grep -v "// intentional"

# Python debug prints  
grep -rn "print(" <changed-python-files> | grep -v "file=sys.stderr" | grep -v "flush=True" | grep -v '"""'

# Hardcoded secrets
grep -rn "fw_\|tgp_\|hf_\|Bearer \|password.*=" <changed-files> | grep -v ".env" | grep -v "memory/"
```

Fix anything found. Report: "Removed X debug prints" or "Clean"

## Step 3: Test verification

```bash
cargo test -p forensic-orchestrator 2>&1 | grep "^test result"
```

If any test fails, fix it before proceeding. Report the test count.

## Step 4: CLAUDE.md sync

Check if ANY of these changed this session:
- New Rust module added → update "Orchestrator Modules" section
- New crate added → update "Crates" section  
- Test count changed → update count
- New commands or workflows → update "Commands" section
- New credentials or env vars → update "Credentials" section

If nothing architectural changed, skip this step.

## Step 5: Memory update

Check if ANY of these are new this session:
- Deployment IDs, endpoint URLs, model names
- Credentials (record the ENV VAR NAME, never the value)
- Infrastructure state changes (what's deployed, what's broken)
- Design decisions that affect future sessions
- Blockers or pending work

Write/update memory files as needed.

## Step 6: Report

Output a single summary block:

```
[HYGIENE CHECK]
Files committed: X in Y commits (or "already clean")
Debug cruft: removed N items (or "clean")
Tests: NNN passed, 0 failed
CLAUDE.md: updated (or "no changes needed")
Memory: updated X files (or "no updates needed")
```
