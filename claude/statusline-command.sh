#!/usr/bin/env bash
# Claude Code status line
# Layout: line1: [grey cwd] |
#         line2: [purple model] [grey ctx bar] | [cyan branch] [5h:XX%] [7d:XX%]
#         line3: [grey 5h resets H:MM (in Xh Ym)]
#
# Rate limits: rate_limits.{five_hour,seven_day}.used_percentage, colored
#   green (<70%), yellow (70-90%), red (>90%). Only present for subscribers
#   after the first API response; segments are silently omitted when absent.
# Reset time: rate_limits.five_hour.resets_at (ISO-8601, nullable) rendered as
#   local wall-clock plus a countdown. Omitted entirely if the field is null.
#
# REMOVED 2026-07-25: the "last prompt H:MM" and "saved:$X.XXXX" segments.
#   - "last prompt" marked the cache (cold) after 300s, but this CLI writes the
#     prompt cache at a ONE HOUR ttl (usage.cache_creation.ephemeral_1h_input_tokens
#     is the populated field; ephemeral_5m is 0). It was calling caches cold ~55
#     minutes early, so the signal was wrong more often than right.
#   - "saved" priced cache reads off a hardcoded rate table that had drifted
#     (it carried opus at $15/$75; the current Opus is $5/$25), and it reported
#     one API call rather than anything cumulative.
#   Both are gone rather than fixed: neither drove a decision, and a number
#   nobody acts on still has to be kept correct.

input=$(cat)

# Use jq for reliable field extraction; fall back gracefully if jq is absent.
if command -v jq >/dev/null 2>&1; then
  cwd=$(echo "$input"      | jq -r '.workspace.current_dir // .cwd // empty')
  model=$(echo "$input"    | jq -r '.model.display_name // empty')
  used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
  ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
  # Rate limit fields — only present for subscribers after first API response.
  five_hr_pct=$(echo "$input"   | jq -r '.rate_limits.five_hour.used_percentage // empty')
  five_hr_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
  seven_day_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
else
  # Fallback: simple grep-based extraction for string fields only.
  extract() { echo "$input" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*:.*"\(.*\)"/\1/'; }
  cwd=$(extract "current_dir")
  model=$(extract "display_name")
  # Numeric fields are unreliable without jq; leave empty so segments are silently omitted.
  used_pct=""; ctx_size=""
  five_hr_pct=""; five_hr_reset=""; seven_day_pct=""
fi

# Shorten cwd: replace home prefix with ~
case "$cwd" in
  "$HOME"/*) cwd="~${cwd#"$HOME"}" ;;
  "$HOME")   cwd="~" ;;
esac

# Git branch
branch=""
full_cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null || echo "$cwd")
if [ -n "$full_cwd" ] && git -C "$full_cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$full_cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null \
           || git -C "$full_cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
fi

# Format token limit (e.g. 200000 -> 200k, 1000000 -> 1M)
limit_label=""
if [ -n "$ctx_size" ] && [ "$ctx_size" -gt 0 ] 2>/dev/null; then
  if [ "$ctx_size" -ge 1000000 ]; then
    limit_label="$(( ctx_size / 1000000 ))M"
  elif [ "$ctx_size" -ge 1000 ]; then
    limit_label="$(( ctx_size / 1000 ))k"
  else
    limit_label="$ctx_size"
  fi
fi

# Build context bar
bar_width=15
if [ -n "$used_pct" ] && [ "$used_pct" -ge 0 ] 2>/dev/null; then
  filled=$(( used_pct * bar_width / 100 ))
  [ "$filled" -gt "$bar_width" ] && filled=$bar_width
  empty=$(( bar_width - filled ))
  bar_fill=$(printf '%*s' "$filled" '' | tr ' ' '=')
  bar_empty=$(printf '%*s' "$empty" '' | tr ' ' '-')
  bar="${used_pct}%[${bar_fill}${bar_empty}]"
else
  bar_empty=$(printf '%*s' "$bar_width" '' | tr ' ' '-')
  bar="[${bar_empty}]"
fi
[ -n "$limit_label" ] && bar="${bar}${limit_label}"

# Clean up state files left by the removed cache/savings segments and the older
# background-timer approach before that. Harmless if already gone.
rm -f "$HOME/.claude/cache_last_write.ts" \
      "$HOME/.claude/cache_countdown.txt" \
      "$HOME/.claude/cache_timer.pid" 2>/dev/null

# ---------------------------------------------------------------------------
# Rate limit segments — five_hour and seven_day used percentages.
# Color: green <70%, yellow 70-90%, red >90%.
# ---------------------------------------------------------------------------
_rl_color() {
  local pct="$1"
  if awk -v p="$pct" 'BEGIN { exit !(p >= 90) }' 2>/dev/null; then
    printf '\033[31m'   # red
  elif awk -v p="$pct" 'BEGIN { exit !(p >= 70) }' 2>/dev/null; then
    printf '\033[33m'   # yellow
  else
    printf '\033[32m'   # green
  fi
}

five_hr_seg=""
seven_day_seg=""

if [ -n "$five_hr_pct" ] && command -v awk >/dev/null 2>&1; then
  pct_int=$(awk -v p="$five_hr_pct" 'BEGIN { printf "%.0f", p }')
  color=$(_rl_color "$five_hr_pct")
  five_hr_seg=" ${color}5h:${pct_int}%"
fi

if [ -n "$seven_day_pct" ] && command -v awk >/dev/null 2>&1; then
  pct_int=$(awk -v p="$seven_day_pct" 'BEGIN { printf "%.0f", p }')
  color=$(_rl_color "$seven_day_pct")
  seven_day_seg=" ${color}7d:${pct_int}%"
fi

# ANSI colors
P="\033[35m"   # purple
D="\033[90m"   # dim grey
C="\033[36m"   # cyan
R="\033[0m"    # reset

# ---------------------------------------------------------------------------
# 5-hour reset line — wall-clock time the window rolls over, plus a countdown.
#
# Rendered whenever rate-limit data is present AT ALL, not only when resets_at
# parses. A line that silently vanishes is indistinguishable from a status line
# that is not running the expected script. If the field is missing the line says
# so; absence of the whole line then means something structural, not a null field.
# ---------------------------------------------------------------------------

# Which clock to render the reset time on. THE BOX IS Etc/UTC, so plain `date`
# printed UTC and read as a bug (2026-07-25). There is no auto-detect available:
# TZ is unset, /etc/localtime is UTC, and sshd's AcceptEnv does not forward TZ
# from the client, so nothing here knows where the operator is. Precedence:
#   CLAUDE_STATUSLINE_TZ  -- explicit override, per user
#   TZ                    -- follows the shell env if it is ever set
#   America/Phoenix       -- the default (and MST year-round: no DST edge cases)
# %Z prints the abbreviation alongside, so a wrong zone is visible rather than
# silently misleading -- which is the failure this replaces.
STATUSLINE_TZ="${CLAUDE_STATUSLINE_TZ:-${TZ:-America/Phoenix}}"

reset_line=""
if [ -n "$five_hr_pct" ]; then
  if [ -n "$five_hr_reset" ]; then
    # resets_at is not always an ISO string. The CLI carries a `Math.round(Number(...))`
    # path for it, so it can arrive as a numeric epoch -- which `date -d` REJECTS
    # outright (`date -d 1753430400` is an error, not a timestamp). Unhandled, that
    # fell through to the raw-value branch and printed something that reads exactly
    # like a UTC code, which is what was reported on 2026-07-25.
    case "$five_hr_reset" in
      *[!0-9]*)                                   # has non-digits -> a date string
        reset_epoch=$(date -d "$five_hr_reset" +%s 2>/dev/null) ;;
      *)                                          # all digits -> epoch s or ms
        if [ "$five_hr_reset" -gt 99999999999 ] 2>/dev/null; then
          reset_epoch=$(( five_hr_reset / 1000 ))
        else
          reset_epoch="$five_hr_reset"
        fi ;;
    esac
    now_epoch=$(date +%s 2>/dev/null)
    if [ -n "$reset_epoch" ] && [ -n "$now_epoch" ]; then
      reset_hhmm=$(TZ="$STATUSLINE_TZ" date -d "@$reset_epoch" '+%-I:%M %p %Z' 2>/dev/null \
                   || TZ="$STATUSLINE_TZ" date -d "@$reset_epoch" '+%I:%M %p %Z')
      remaining=$(( reset_epoch - now_epoch ))
      if [ "$remaining" -gt 0 ]; then
        rh=$(( remaining / 3600 ))
        rmin=$(( (remaining % 3600) / 60 ))
        if [ "$rh" -gt 0 ]; then countdown="${rh}h ${rmin}m"; else countdown="${rmin}m"; fi
        reset_line="\n${D}5h resets ${C}${reset_hhmm}${D} (in ${countdown})${R}"
      else
        # Past the reset instant but the payload has not refreshed yet.
        reset_line="\n${D}5h window resetting${R}"
      fi
    else
      # Present but not a timestamp `date` understands — show it raw rather than
      # dropping it, so the format is visible and fixable.
      reset_line="\n${D}5h resets ${C}${five_hr_reset}${R}"
    fi
  else
    reset_line="\n${D}5h resets: not reported by the CLI${R}"
  fi
fi

# Build segments
left="${D}${cwd}"
mid="${P}${model} ${D}${bar}"

# Branch segment
branch_seg=""
[ -n "$branch" ] && branch_seg=" ${C}${branch}"

# Separator between the branch and the usage percentages. Only when there is
# usage to separate — otherwise line 2 ends on a bare trailing pipe.
usage_sep=""
if [ -n "$five_hr_seg" ] || [ -n "$seven_day_seg" ]; then
  usage_sep=" ${D}|"
fi

output="${left} ${D}|\n${mid} ${D}|${branch_seg}${usage_sep}${five_hr_seg}${seven_day_seg}${R}${reset_line}"
printf '%b' "$output"
