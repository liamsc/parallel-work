#!/usr/bin/env bash
# Statusline script for Claude Code — shows clone identity, repo, branch,
# git state, context usage, and current task at a glance.
#
# Claude Code pipes JSON session data to stdin; we extract cwd and context %,
# then combine with pwork metadata for a two-line status bar.
#
# Designed to be installed per-clone via .claude/settings.json.

# -u treats unset variables as errors; pipefail catches failures in pipes.
set -uo pipefail

# Bail out silently if jq isn't installed — statusline is non-critical.
# command -v checks if a command exists without running it.
command -v jq &>/dev/null || exit 0

# Read all of stdin (JSON from Claude Code) into a variable.
input=$(cat)

# jq extracts fields; "// 0" falls back to 0 when the value is null.
DIR=$(echo "$input" | jq -r '.workspace.current_dir')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)

# ── ANSI color codes ────────────────────────────────────────
BLD='\033[1m'
CYN='\033[1;36m'
GRN='\033[1;32m'
YLW='\033[1;33m'
RED='\033[1;31m'
MAG='\033[1;35m'
DIM='\033[2m'
RST='\033[0m'

# ── Derive clone name (e.g. "p3") by walking up from cwd ───
CLONE=""
WORKSPACE_DIR=""
d="$DIR"
# Walk up directory tree until we find a pN directory name.
while [[ "$d" != "/" ]]; do
  base="$(basename "$d")"
  # p[0-9]* matches directory names like p1, p2, p10, etc.
  if [[ "$base" =~ ^p[0-9]+$ ]]; then
    CLONE="$base"
    WORKSPACE_DIR="$(dirname "$d")"
    break
  fi
  d="$(dirname "$d")"
done

# ── Load repo slug from pwork.conf ─────────────────────────
SLUG=""
CONF="$WORKSPACE_DIR/.parallel-work/pwork.conf"
if [[ -n "$WORKSPACE_DIR" && -f "$CONF" ]]; then
  # Extract just the value after the = sign, stripping quotes.
  SLUG=$(grep '^PWORK_REPO_SLUG=' "$CONF" | cut -d= -f2 | tr -d '"')
fi

# ── Git branch + dirty state ───────────────────────────────
BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)
# --numstat lists one line per changed file; wc -l counts them.
STAGED=$(git -C "$DIR" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
MODIFIED=$(git -C "$DIR" diff --numstat 2>/dev/null | wc -l | tr -d ' ')

# ── Build content segments separated by │ ─────────────────
SEP=" ${BOX_COLOR}│${RST} "
CONTENT="${BLD}clone:${RST}${CYN}${CLONE:-?}${RST}"
# -n tests if the string is non-empty.
[[ -n "$SLUG" ]] && CONTENT="${CONTENT}${SEP}${BLD}repo:${RST}${MAG}$SLUG${RST}"

# Branch + dirty state grouped together.
if [[ -n "$BRANCH" ]]; then
  BRANCH_SEG="${BLD}branch:${RST}${GRN}$BRANCH${RST}"
  # -gt 0 means "greater than zero"
  [[ "$STAGED" -gt 0 ]] && BRANCH_SEG="$BRANCH_SEG ${GRN}+${STAGED}${RST}"
  [[ "$MODIFIED" -gt 0 ]] && BRANCH_SEG="$BRANCH_SEG ${YLW}~${MODIFIED}${RST}"
  CONTENT="${CONTENT}${SEP}${BRANCH_SEG}"
fi

# Context percentage — color shifts at 60% (yellow warning) and 80% (red).
CTX_COLOR="$GRN"
CTX_WARN=""
# BOX_COLOR sets the border color — defaults to cyan, shifts to match context urgency.
BOX_COLOR="$CYN"
if [[ "$PCT" -ge 80 ]]; then
  CTX_COLOR="$RED"
  CTX_WARN=" ${RED}!!${RST}"
  BOX_COLOR="$RED"
elif [[ "$PCT" -ge 70 ]]; then
  CTX_COLOR="$YLW"
  CTX_WARN=" ${YLW}!${RST}"
  BOX_COLOR="$YLW"
fi
CONTENT="${CONTENT}${SEP}${BLD}ctx:${RST}${CTX_COLOR}${PCT}%${RST}${CTX_WARN}"

# ── Task line (appended inside the box if set) ────────────
TASK_LINE=""
TASK_FILE="$DIR/.claude/CLAUDE.local.md"
if [[ -f "$TASK_FILE" ]]; then
  # Extract first non-empty line between "## Current Task" and the next "##" heading.
  # sed -n '/start/,/end/{...}' prints lines between two patterns.
  TASK=$(sed -n '/^## Current Task$/,/^##/{/^## Current Task$/d;/^##/d;p;}' "$TASK_FILE" \
    | head -1 | xargs)
  if [[ -n "$TASK" && "$TASK" != "_unassigned_" ]]; then
    TASK_LINE="${BLD}task:${RST}${DIM}${TASK}${RST}"
  fi
fi

# ── Render boxed output ───────────────────────────────────
# Strip ANSI codes to measure visible character width for the box border.
# sed removes all escape sequences (\033[...m); wc -m counts chars.
strip_ansi() { echo -e "$1" | sed $'s/\033\\[[0-9;]*m//g'; }
CONTENT_PLAIN=$(strip_ansi "$CONTENT")
TASK_PLAIN=$(strip_ansi "$TASK_LINE")

# ${#var} gives the string length; pick the longer line for box width.
CONTENT_LEN=${#CONTENT_PLAIN}
TASK_LEN=${#TASK_PLAIN}
# (( )) is arithmetic context
(( BOX_W = CONTENT_LEN > TASK_LEN ? CONTENT_LEN : TASK_LEN ))
# Add 2 for padding (one space each side).
(( BOX_W += 2 ))

# printf '%0.s─' repeats ─ for each number in the sequence, creating a horizontal rule.
HBAR=$(printf '%0.s─' $(seq 1 "$BOX_W"))

# Pad each line to fill the box width with trailing spaces.
# $(( BOX_W - len - 2 )) calculates how many spaces to add after the content.
PAD1=$(printf '%*s' "$(( BOX_W - CONTENT_LEN - 2 ))" "")
echo -e "${BOX_COLOR}┌${HBAR}┐${RST}"
echo -e "${BOX_COLOR}│${RST} ${CONTENT}${PAD1} ${BOX_COLOR}│${RST}"
if [[ -n "$TASK_LINE" ]]; then
  PAD2=$(printf '%*s' "$(( BOX_W - TASK_LEN - 2 ))" "")
  echo -e "${BOX_COLOR}│${RST} ${TASK_LINE}${PAD2} ${BOX_COLOR}│${RST}"
fi
echo -e "${BOX_COLOR}└${HBAR}┘${RST}"
