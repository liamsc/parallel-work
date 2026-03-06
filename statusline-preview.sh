#!/usr/bin/env bash
# Run this in a separate terminal to preview all statusline scenarios.
# Take a screenshot of the output for the repo README.

BLD='\033[1m'
CYN='\033[1;36m'
GRN='\033[1;32m'
YLW='\033[1;33m'
RED='\033[1;31m'
MAG='\033[1;35m'
DIM='\033[2m'
RST='\033[0m'
SEP=" ${CYN}│${RST} "

# render_box "border_color" "content" ["task"]
render_box() {
  local bc="$1" content="$2" task="${3:-}"

  strip_ansi() { echo -e "$1" | sed $'s/\033\\[[0-9;]*m//g'; }
  local content_plain task_plain
  content_plain=$(strip_ansi "$content")
  task_plain=$(strip_ansi "$task")

  local content_len=${#content_plain} task_len=${#task_plain}
  local box_w
  (( box_w = content_len > task_len ? content_len : task_len ))
  (( box_w += 2 ))

  local hbar
  hbar=$(printf '%0.s─' $(seq 1 "$box_w"))
  local pad1
  pad1=$(printf '%*s' "$(( box_w - content_len - 2 ))" "")

  echo -e "${bc}┌${hbar}┐${RST}"
  echo -e "${bc}│${RST} ${content}${pad1} ${bc}│${RST}"
  if [[ -n "$task" ]]; then
    local pad2
    pad2=$(printf '%*s' "$(( box_w - task_len - 2 ))" "")
    echo -e "${bc}│${RST} ${task}${pad2} ${bc}│${RST}"
  fi
  echo -e "${bc}└${hbar}┘${RST}"
}

echo ""
echo -e "${BLD}parallel-work statusline${RST}"
echo ""

# 1. Clean clone on main, low context, no task
echo -e "${DIM}Clean clone — main branch, no task${RST}"
C="${BLD}clone:${RST}${CYN}p1${RST}${SEP}${BLD}repo:${RST}${MAG}parallel-work${RST}${SEP}${BLD}branch:${RST}${GRN}main${RST}${SEP}${BLD}ctx:${RST}${GRN}8%${RST}"
render_box "$CYN" "$C"
echo ""

# 2. Working clone with staged + modified files, task assigned
echo -e "${DIM}Active work — staged & modified files, with task${RST}"
C="${BLD}clone:${RST}${CYN}p2${RST}${SEP}${BLD}repo:${RST}${MAG}parallel-work${RST}${SEP}${BLD}branch:${RST}${GRN}feat/add-statusline${RST} ${GRN}+3${RST} ${YLW}~2${RST}${SEP}${BLD}ctx:${RST}${GRN}34%${RST}"
T="${BLD}task:${RST}${DIM}implement statusline for pwork clones${RST}"
render_box "$CYN" "$C" "$T"
echo ""

# 3. Only staged changes
echo -e "${DIM}Staged changes only${RST}"
C="${BLD}clone:${RST}${CYN}p3${RST}${SEP}${BLD}repo:${RST}${MAG}my-api${RST}${SEP}${BLD}branch:${RST}${GRN}fix/auth-redirect${RST} ${GRN}+7${RST}${SEP}${BLD}ctx:${RST}${GRN}21%${RST}"
T="${BLD}task:${RST}${DIM}fix OAuth redirect loop on mobile${RST}"
render_box "$CYN" "$C" "$T"
echo ""

# 4. Only modified (unstaged) changes
echo -e "${DIM}Unstaged changes only${RST}"
C="${BLD}clone:${RST}${CYN}p4${RST}${SEP}${BLD}repo:${RST}${MAG}my-api${RST}${SEP}${BLD}branch:${RST}${GRN}refactor/db-layer${RST} ${YLW}~5${RST}${SEP}${BLD}ctx:${RST}${GRN}45%${RST}"
render_box "$CYN" "$C"
echo ""

# 5. Context warning — 75% yellow border
echo -e "${DIM}Context warning — 75%${RST}"
C="${BLD}clone:${RST}${CYN}p2${RST}${SEP}${BLD}repo:${RST}${MAG}parallel-work${RST}${SEP}${BLD}branch:${RST}${GRN}feat/add-statusline${RST} ${GRN}+1${RST}${SEP}${BLD}ctx:${RST}${YLW}75%${RST} ${YLW}!${RST}"
T="${BLD}task:${RST}${DIM}implement statusline for pwork clones${RST}"
render_box "$YLW" "$C" "$T"
echo ""

# 6. Context critical — 92% red border
echo -e "${DIM}Context critical — 92%${RST}"
C="${BLD}clone:${RST}${CYN}p5${RST}${SEP}${BLD}repo:${RST}${MAG}parallel-work${RST}${SEP}${BLD}branch:${RST}${GRN}feat/large-refactor${RST} ${GRN}+12${RST} ${YLW}~4${RST}${SEP}${BLD}ctx:${RST}${RED}92%${RST} ${RED}!!${RST}"
T="${BLD}task:${RST}${DIM}rewrite bootstrap to support monorepos${RST}"
render_box "$RED" "$C" "$T"
echo ""
