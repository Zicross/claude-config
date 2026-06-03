#!/usr/bin/env bash
# Pure-Bash path normalization for sync.sh (replaces the old normalize.js).
# No Node, no Python, no sed — runs on a bare box and preserves bytes exactly.
#
# Usage: normalize.sh <normalize|expand> <file> [claude_home]
#   normalize : replace absolute paths with __CLAUDE_HOME__ / __CLAUDE_HOME_POSIX__
#   expand    : replace placeholders with absolute paths for the target home
#
# The Windows-vs-POSIX behaviour is driven by the SHAPE of claude_home (a leading
# drive letter like "C:") rather than by `uname`: the output format follows the
# target path, not the running OS, which also makes the Windows branch testable
# from Linux by passing a Windows-style home explicitly.
set -euo pipefail

mode="${1:-}"
file="${2:-}"
claude_home="${3:-$HOME/.claude}"

if [[ -z "$mode" || -z "$file" ]]; then
    echo "Usage: normalize.sh <normalize|expand> <file> [claude_home]" >&2
    exit 1
fi
if [[ ! -f "$file" ]]; then
    echo "normalize.sh: no such file: $file" >&2
    exit 1
fi

PH='__CLAUDE_HOME__'

# Is claude_home a Windows path (e.g. C:\Users\isaac\.claude)?
is_win_home=false
drive=""
if [[ "$claude_home" =~ ^([A-Za-z]):(.*) ]]; then
    is_win_home=true
    drive="${BASH_REMATCH[1],,}"          # lowercased drive letter
fi

# POSIX form of the home: C:\Users\isaac\.claude -> /c/Users/isaac/.claude
posix_home="$claude_home"
if $is_win_home; then
    posix_home="/${drive}${claude_home:2}"
    posix_home="${posix_home//\\//}"
fi

# Walk every __CLAUDE_HOME__ occurrence in $2. For each, emit $1 (the placeholder
# replacement) followed by the run of characters up to the next double-quote, with
# path separators in that run rewritten per $3:
#   tofwd  -> "/"   becomes  "\\"   (POSIX -> Windows, JSON-escaped)
#   toback -> "\\"  becomes  "/"    (Windows JSON -> POSIX)
#   none   -> unchanged
# Result is returned in the global _R (avoids $()-stripping of trailing newlines).
rewrite_runs() {
    local repl="$1" in="$2" sep="$3"
    local out="" before rest tail
    while [[ "$in" == *"$PH"* ]]; do
        before="${in%%"$PH"*}"
        in="${in#*"$PH"}"
        rest="${in%%\"*}"                 # up to next double-quote
        tail="${in:${#rest}}"
        case "$sep" in
            tofwd)  rest="${rest//\//\\\\}" ;;   # /  -> \\
            toback) rest="${rest//\\\\//}" ;;    # \\ -> /
        esac
        out+="${before}${repl}${rest}"
        in="$tail"
    done
    out+="$in"
    _R="$out"
}

# Read the file preserving exact bytes, including any trailing newline.
content="$(cat "$file"; printf 'x')"
content="${content%x}"

case "$mode" in
    normalize)
        win_escaped="${claude_home//\\/\\\\}"           # C:\Users -> C:\\Users
        content="${content//"$win_escaped"/$PH}"        # Windows JSON-escaped form
        content="${content//"$claude_home"/$PH}"        # native form
        if [[ "$posix_home" != "$claude_home" ]]; then
            content="${content//"$posix_home"/$PH}"     # POSIX form (distinct on Windows)
        fi
        # On Windows the run after the placeholder still uses \\ separators; make
        # them forward slashes (no-op for POSIX paths, which have none).
        if $is_win_home; then
            rewrite_runs "$PH" "$content" toback
            content="$_R"
        fi
        # Commands run via bash/sh must use the POSIX placeholder so they expand to
        # a POSIX path even on Windows. (Plain substring swap; configs never carry
        # an adversarial "...sh __CLAUDE_HOME__" that isn't really bash/sh.)
        content="${content//bash ${PH}/bash __CLAUDE_HOME_POSIX__}"
        content="${content//sh ${PH}/sh __CLAUDE_HOME_POSIX__}"
        ;;
    expand)
        # The POSIX placeholder always expands to the POSIX home.
        content="${content//__CLAUDE_HOME_POSIX__/$posix_home}"
        if $is_win_home; then
            win_escaped="${claude_home//\\/\\\\}"
            rewrite_runs "$win_escaped" "$content" tofwd
            content="$_R"
        else
            content="${content//$PH/$claude_home}"
        fi
        ;;
    *)
        echo "normalize.sh: unknown mode: $mode" >&2
        exit 1
        ;;
esac

printf '%s' "$content" > "$file"
echo "${mode}: ${file}"
