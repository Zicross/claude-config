#!/usr/bin/env bash
# Claude Code status line
# Layout: line1: [grey cwd] |
#         line2: [purple model] [grey ctx bar] | [cyan branch] [last prompt H:MM] [saved:$X.XXXX] [5h:XX%] [7d:XX%]
#
# Cache display: when cache_creation_input_tokens > 0, records the current
# wall-clock time (HH:MM) and epoch to ~/.claude/cache_last_write.ts.
# The statusline shows "last prompt H:MM"; if the cache has expired (>300s)
# it appends "(cold)" so the user knows the cache is stale.
# Stale countdown/pid files from the old timer approach are cleaned up on startup.
#
# Savings: per-call dollar savings from cache reads vs. paying full price.
#   Formula: savings = cache_read_tokens * base_input_rate * 0.90
#   (cache reads cost 10% of base, so each cached token saves 90% of base rate)
# Rate limits: rate_limits.five_hour and rate_limits.seven_day used_percentage,
#   colored green (<70%), yellow (70-90%), red (>90%).
#
# Per-token rates ($/MTok) as of 2026-04:
#   claude-opus-4*    : input $15, output $75
#   claude-sonnet-4*  : input $3,  output $15
#   claude-haiku-4*   : input $1,  output $5
#   (fallback for unknown models: Sonnet rates)

input=$(cat)

# Use jq for reliable field extraction; fall back gracefully if jq is absent.
if command -v jq >/dev/null 2>&1; then
  cwd=$(echo "$input"      | jq -r '.workspace.current_dir // .cwd // empty')
  model=$(echo "$input"    | jq -r '.model.display_name // empty')
  model_id=$(echo "$input" | jq -r '.model.id // empty')
  used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
  ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
  # current_usage fields — from the last API call, not session totals.
  cache_read=$(echo "$input"    | jq -r '.context_window.current_usage.cache_read_input_tokens // empty')
  cache_write=$(echo "$input"   | jq -r '.context_window.current_usage.cache_creation_input_tokens // empty')
  input_tokens=$(echo "$input"  | jq -r '.context_window.current_usage.input_tokens // empty')
  output_tokens=$(echo "$input" | jq -r '.context_window.current_usage.output_tokens // empty')
  # Rate limit fields — only present for subscribers after first API response.
  five_hr_pct=$(echo "$input"  | jq -r '.rate_limits.five_hour.used_percentage // empty')
  seven_day_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
else
  # Fallback: simple grep-based extraction for string fields only.
  extract() { echo "$input" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*:.*"\(.*\)"/\1/'; }
  cwd=$(extract "current_dir")
  model=$(extract "display_name")
  model_id=$(extract "id")
  # Numeric fields are unreliable without jq; leave empty so segments are silently omitted.
  used_pct=""; ctx_size=""; cache_read=""; cache_write=""; input_tokens=""; output_tokens=""
  five_hr_pct=""; seven_day_pct=""
fi

# Resolve user
user=$(whoami 2>/dev/null)

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

# ---------------------------------------------------------------------------
# Per-token rates (micro-dollars per token = $/MTok * 1_000_000 / 1_000_000)
# We work in nano-dollars (1e-9 $) to avoid bash integer truncation on small counts.
# rate_input_nd = base input rate in nano-dollars per token
# ---------------------------------------------------------------------------
# Defaults to Sonnet if model not recognized.
rate_input_nd=3000   # $3/MTok  = 3000 nano-dollars/token  (Sonnet fallback)
case "$model_id" in
  claude-opus-4*)   rate_input_nd=15000 ;;  # $15/MTok
  claude-sonnet-4*) rate_input_nd=3000  ;;  # $3/MTok
  claude-haiku-4*)  rate_input_nd=1000  ;;  # $1/MTok
esac

# Cache display — shows wall-clock time of the last cache write so the user
# can mentally compare against their current clock (5-minute warm window).
# Shows nothing if no API call has happened yet (current_usage is null).

CACHE_TS_FILE="$HOME/.claude/cache_last_write.ts"
CACHE_TTL=300   # Anthropic cache TTL in seconds

# Clean up stale files from the old background-timer approach.
rm -f "$HOME/.claude/cache_countdown.txt" \
      "$HOME/.claude/cache_timer.pid" 2>/dev/null

cache_seg=""
savings_seg=""

# If a new cache write happened this call, record epoch + HH:MM wall-clock time.
if [ -n "$cache_write" ] && [ "$cache_write" -gt 0 ] 2>/dev/null; then
  now_ts=$(date +%s)
  now_hhmm=$(date +%-H:%M 2>/dev/null || date +%H:%M)
  printf '%s\n%s\n' "$now_ts" "$now_hhmm" > "$CACHE_TS_FILE" 2>/dev/null
fi

# Build cache segment from the stored timestamp file.
if [ -f "$CACHE_TS_FILE" ]; then
  last_write=$(sed -n '1p' "$CACHE_TS_FILE" 2>/dev/null)
  last_hhmm=$(sed -n '2p' "$CACHE_TS_FILE" 2>/dev/null)
  now=$(date +%s 2>/dev/null)

  if [ -n "$last_write" ] && [ -n "$last_hhmm" ] && [ -n "$now" ] && \
     [ "$now" -ge "$last_write" ] 2>/dev/null; then
    elapsed=$(( now - last_write ))
    if [ "$elapsed" -gt "$CACHE_TTL" ]; then
      # Stale: show time but mark cold so user knows it expired.
      cache_seg=" \033[90m│ last prompt ${last_hhmm} \033[31m(cold)"
    else
      cache_seg=" \033[90m│ last prompt \033[36m${last_hhmm}"
    fi
  fi
fi

# Savings calculation — based on last API call's cache_read tokens.
if [ -n "$cache_read" ] && [ "$cache_read" -gt 0 ] 2>/dev/null && command -v awk >/dev/null 2>&1; then
  savings_dollars=$(awk -v cr="$cache_read" -v nd="$rate_input_nd" \
    'BEGIN { printf "%.4f", cr * nd * 90 / 100 / 1000000000 }')
  # Only display if non-trivial (savings >= $0.0001)
  nonzero=$(awk -v s="$savings_dollars" 'BEGIN { print (s >= 0.0001) ? "1" : "0" }')
  if [ "$nonzero" = "1" ]; then
    savings_seg=" \033[32msaved:\$${savings_dollars}"
  fi
fi

# ---------------------------------------------------------------------------
# Rate limit segments — five_hour and seven_day used percentages.
# Color: green <70%, yellow 70-90%, red >90%.
# These fields are only present for claude.ai subscribers after the first API
# response; the segment is silently omitted when absent.
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
G="\033[32m"   # green
P="\033[35m"   # purple
D="\033[90m"   # dim grey
C="\033[36m"   # cyan
R="\033[0m"    # reset

# Build segments
left="${D}${cwd}"
mid="${P}${model} ${D}${bar}"

# Branch segment
branch_seg=""
[ -n "$branch" ] && branch_seg=" ${C}${branch}"

output="${left} ${D}|\n${mid} ${D}|${branch_seg}${cache_seg}${savings_seg}${five_hr_seg}${seven_day_seg}${R}"
printf '%b' "$output"
