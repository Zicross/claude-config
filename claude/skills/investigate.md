---
name: investigate
description: "Use when starting any investigation session, running probes, browsing the Chinese internet, collecting or verifying intelligence, or when the user says investigate, probe, collect, browse, or verify."
---

# Investigation Session

You have access to the Chinese internet through ephemeral browser containers via `browse.py`. You are the orchestrator — use your judgement to decide what approach fits the task. There is no fixed workflow.

## Browser Commands

```bash
# Session lifecycle
py tools/xremote/browse.py start --session NAME
py tools/xremote/browse.py destroy --session NAME

# Navigation
py tools/xremote/browse.py navigate URL --session NAME

# Content extraction
py tools/xremote/browse.py text --session NAME                    # full page
py tools/xremote/browse.py text --selector "CSS" --session NAME   # specific element
py tools/xremote/browse.py text --limit 5000 --session NAME       # truncated
py tools/xremote/browse.py links --session NAME                   # all links
py tools/xremote/browse.py tables --session NAME                  # all tables

# Interaction
py tools/xremote/browse.py click "CSS selector" --session NAME
py tools/xremote/browse.py type "CSS selector" "text" --session NAME
py tools/xremote/browse.py scroll --to bottom --session NAME

# Utility
py tools/xremote/browse.py js "expression" --session NAME         # arbitrary JS
py tools/xremote/browse.py screenshot --save path.png --session NAME
py tools/xremote/browse.py wait SECONDS --session NAME
```

All commands return JSON: `{"status": "ok", ...}` or `{"status": "error", "error": "..."}`.

Fire 3-5 sessions in parallel (`run_in_background`) with staggered starts for parallel browsing.

## Collection Approaches

Choose the approach that fits the task. These are patterns, not a fixed sequence.

**New intelligence collection:**
Probe chatbots for leads → verify cited sources directly → dork for additional context → use verified data to strengthen follow-up probes → iterate

**Verification only:**
Go directly to the source URL or dork for the document. No chatbot needed. Navigate to the page, read it, screenshot it, done.

**Lead following:**
Start from a known citation (law name, document title, entity). Navigate to the source, extract data, follow links to related documents, branch out.

**Exploratory browsing:**
Browse gov.cn portals, scan WeChat articles, search across engines. No specific target — see what surfaces. Good for discovering new sources and angles.

**Cross-verification:**
Hit the same question across multiple platforms (ERNIE, Tongyi, DeepSeek). Compare answers. Contradictions reveal model biases and training data boundaries.

**Use your judgement.** If you're verifying a known citation, don't waste time probing a chatbot first. If you're exploring a new topic, chatbot probing is a good starting point for leads. If a platform is blocking, switch to a different one or a different approach entirely. Break out of any pattern when the situation calls for it.

## Chatbot Interaction Pattern

```bash
# Navigate to platform
py tools/xremote/browse.py navigate https://chat.baidu.com --session s1
# Wait for UI to load
py tools/xremote/browse.py wait 5 --session s1
# Discover the input element (don't assume selectors — they change)
py tools/xremote/browse.py js "document.querySelector('textarea, [contenteditable], [role=\"textbox\"]')?.tagName" --session s1
# Type and submit
py tools/xremote/browse.py type ".ci-textarea" "你的问题" --session s1
py tools/xremote/browse.py click ".ci-submit-button" --session s1
# Wait for response
py tools/xremote/browse.py wait 30 --session s1
# Read response
py tools/xremote/browse.py text --session s1
```

If selectors fail, use `js` to discover the right ones. The tool doesn't know any platform's UI — you figure it out at browse time.

## Search Engine Dorking

```bash
# Baidu
py tools/xremote/browse.py navigate "https://www.baidu.com/s?wd=site%3Agov.cn+人民武装部+预算" --session s1

# Sogou
py tools/xremote/browse.py navigate "https://www.sogou.com/web?query=预备役+经费" --session s1

# Sogou WeChat (exclusive WeChat article index — indexes government official accounts not on Baidu)
py tools/xremote/browse.py navigate "https://weixin.sogou.com/weixin?type=2&query=国防动员+经费" --session s1
# type=1 searches official accounts by name, type=2 searches article content

# Bing China
py tools/xremote/browse.py navigate "https://cn.bing.com/search?q=人民武装部+预算" --session s1
```

After searching, use `links` to extract result URLs, then `navigate` to the actual source pages.

## Government Portal Patterns

County finance bureaus: `czj.{county}.gov.cn`
City finance bureaus: `czj.{city}.gov.cn`
Look for: 财政预决算, 信息公开, 部门预算 sections
PAD budgets listed under: 人民武装部

## Source Priority

1. Government documents accessed directly via container (HIGHEST)
2. Chinese primary media (PLA Daily 81.cn, Xinhua)
3. Chinese AI chatbot outputs (leads, not evidence)
4. Chinese academic papers (CNKI, Wanfang)
5. Western sources (LOWEST for Chinese specifics)

Chatbot outputs become high-confidence ONLY when the cited source is directly verified.

## Discover New Sources and Techniques

The sources and patterns listed here are not exhaustive. Discover new search engines, dorking patterns, platforms, URL structures, and adversarial techniques during collection. If something works, document it in the self-improvement log for future sessions.

## Evidence Preservation

Screenshot and archive everything. Chinese content gets scrubbed regularly.
```bash
py tools/xremote/browse.py screenshot --save evidence/source-name.png --session s1
```

Read full methodology: `knowledge/attack-library/investigation-methodology.md`
Read full sourcing guide: `knowledge/attack-library/sourcing-and-verification.md`

## Session Close Checklist

Before destroying any browse session, verify:

- [ ] Every source page has full text auto-saved (check session-log.jsonl for text commands)
- [ ] Key source pages have screenshots (`browse.py screenshot --save`)
- [ ] Article images downloaded where relevant (`browse.py images --save`)
- [ ] Verified sources have citation entries in `investigations/{name}/sources/sources.jsonl`
- [ ] Citations include: title, URL, access date, source type, text hash, key data
- [ ] Session summary written to `investigations/{name}/sessions/{session}/summary.md`

The auto-log captures raw commands. The citations and summary require YOUR judgment about what matters.
