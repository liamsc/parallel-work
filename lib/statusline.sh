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
CYN='\033[36m'
GRN='\033[32m'
YLW='\033[33m'
RED='\033[31m'
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

# ── Line 1: clone | repo | branch | git state | context ───
LINE="${CYN}${CLONE:-?}${RST}"
# -n tests if the string is non-empty.
[[ -n "$SLUG" ]] && LINE="$LINE ${DIM}|${RST} $SLUG"
[[ -n "$BRANCH" ]] && LINE="$LINE ${DIM}|${RST} $BRANCH"
# -gt 0 means "greater than zero"
[[ "$STAGED" -gt 0 ]] && LINE="$LINE ${GRN}+${STAGED}${RST}"
[[ "$MODIFIED" -gt 0 ]] && LINE="$LINE ${YLW}~${MODIFIED}${RST}"

# Context percentage — color shifts at 60% (yellow warning) and 80% (red).
CTX_COLOR="$DIM"
if [[ "$PCT" -ge 80 ]]; then
  CTX_COLOR="$RED"
elif [[ "$PCT" -ge 60 ]]; then
  CTX_COLOR="$YLW"
fi
LINE="$LINE ${DIM}|${RST} ${CTX_COLOR}${PCT}% ctx${RST}"

# -e enables interpretation of escape sequences (ANSI colors).
echo -e "$LINE"

# ── Line 2: current task from CLAUDE.local.md (if set) ─────
TASK_FILE="$DIR/.claude/CLAUDE.local.md"
if [[ -f "$TASK_FILE" ]]; then
  # Extract first non-empty line between "## Current Task" and the next "##" heading.
  # sed -n '/start/,/end/{...}' prints lines between two patterns.
  TASK=$(sed -n '/^## Current Task$/,/^##/{/^## Current Task$/d;/^##/d;p;}' "$TASK_FILE" \
    | head -1 | xargs)
  if [[ -n "$TASK" && "$TASK" != "_unassigned_" ]]; then
    echo -e "${DIM}Task: ${TASK}${RST}"
  fi
fi
