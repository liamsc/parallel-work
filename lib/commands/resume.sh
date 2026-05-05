#!/usr/bin/env bash
# p-resume: cross-clone Claude/Cursor session picker with focus-existing-
# window dispatch. This file is the public entry point; everything else
# lives under resume/ and resume/jump/ as small, focused modules:
#
#   resume/format.sh         — generic formatters (truncate, mtime, ago)
#   resume/claude.sh         — Claude encode + title + cwd recovery + live
#   resume/cursor.sh         — Cursor encode + title + cwd recovery + live
#   resume/where.sh          — cwd → "Where" label (used by g-resume)
#   resume/collect.sh        — per-clone aggregation (used by p-resume)
#   resume/collect_global.sh — global aggregation (used by g-resume)
#   resume/render.sh         — colored table renderer
#   resume/dispatch.sh       — _pwork_resume_exec (jump-vs-launch)
#   resume/jump/terminal.sh  — pid → tty + ppid → terminal-app
#   resume/jump/iterm2.sh    — iTerm2 AppleScript focus (tty-precise)
#   resume/jump/ghostty.sh   — Ghostty AppleScript focus (name+cwd)
#   resume/jump/window.sh    — _pwork_jump_window orchestrator

# BASH_SOURCE works in bash; %x prompt expansion works in zsh.
_PWORK_RESUME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")/resume" && pwd)"

# Order matters: format → claude/cursor (use format) → jump (uses claude/
# cursor live-discovery + per-app focus) → collect/render/dispatch → entry.
source "$_PWORK_RESUME_DIR/format.sh"
source "$_PWORK_RESUME_DIR/claude.sh"
source "$_PWORK_RESUME_DIR/cursor.sh"
source "$_PWORK_RESUME_DIR/jump/terminal.sh"
source "$_PWORK_RESUME_DIR/jump/iterm2.sh"
source "$_PWORK_RESUME_DIR/jump/ghostty.sh"
source "$_PWORK_RESUME_DIR/jump/cursor_app.sh"
source "$_PWORK_RESUME_DIR/jump/window.sh"
# where.sh depends on _pwork_list_workspaces (from core.sh, already loaded
# by shell-helpers.sh before commands.sh) — must be sourced before
# collect_global.sh which calls _pwork_resume_where_label per row.
source "$_PWORK_RESUME_DIR/where.sh"
source "$_PWORK_RESUME_DIR/collect.sh"
source "$_PWORK_RESUME_DIR/collect_global.sh"
source "$_PWORK_RESUME_DIR/render.sh"
source "$_PWORK_RESUME_DIR/dispatch.sh"

p-resume() {
  # zsh arrays default to 1-indexed; ksharrays makes them 0-indexed like
  # bash so the indexing below is portable across shells. nullglob makes
  # an unmatched glob expand to nothing instead of erroring (zsh default)
  # or returning the literal pattern (bash default) — needed so the
  # for-loops over *.jsonl in collect.sh don't blow up on empty dirs.
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    setopt localoptions ksharrays nullglob
  fi

  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required by p-resume. Install with: brew install jq" >&2
    return 1
  fi

  local root
  _pwork_conf || return 1
  root="$_PWORK_ROOT"

  # ── Argument parsing ──────────────────────────────────────────
  local limit=15 jump="" filter_clone="" only_claude=false only_cursor=false force_new=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --claude)    only_claude=true; shift ;;
      --cursor)    only_cursor=true; shift ;;
      --force-new) force_new=true; shift ;;
      --limit)     limit="${2:-}"; shift 2 ;;
      --limit=*)   limit="${1#--limit=}"; shift ;;
      -h|--help)
        cat >&2 <<'EOF'
Usage: p-resume [N] [pN] [--claude|--cursor] [--limit M] [--force-new]
  N            Jump to row N from the listing (no prompt).
  pN           Filter to clone pN.
  --claude     Show only Claude sessions (drops the Tool column).
  --cursor     Show only Cursor sessions (drops the Tool column).
  --limit M    Cap rows shown (default 15).
  --force-new  Skip "focus existing window" detection and always launch new.
EOF
        return 0
        ;;
      # p[0-9]* — literal "p" followed by a digit and anything after.
      p[0-9]*)   filter_clone="$1"; shift ;;
      # [0-9]* — anything starting with a digit.
      [0-9]*)    jump="$1"; shift ;;
      *) echo "Usage: p-resume [N] [pN] [--claude|--cursor] [--limit M] [--force-new]" >&2; return 1 ;;
    esac
  done

  if [[ "$only_claude" == true ]] && [[ "$only_cursor" == true ]]; then
    echo "Error: --claude and --cursor are mutually exclusive" >&2
    return 1
  fi
  # =~ is regex match; ^[0-9]+$ — one or more digits, nothing else.
  if ! [[ "$limit" =~ ^[0-9]+$ ]] || [[ "$limit" -lt 1 ]]; then
    echo "Error: --limit must be a positive integer" >&2
    return 1
  fi

  # ── Collect sessions across clones ────────────────────────────
  local clones
  if [[ -n "$filter_clone" ]]; then
    if [[ ! -d "$root/$filter_clone" ]]; then
      echo "Error: $root/$filter_clone does not exist" >&2
      return 1
    fi
    clones="$filter_clone"
  else
    clones="$(_pwork_clones)"
  fi

  local clone raw=""
  while IFS= read -r clone; do
    [[ -n "$clone" ]] || continue
    raw+="$(_pwork_resume_collect_clone "$root/$clone" "$clone")"$'\n'
  done <<< "$clones"

  # Filter by tool if requested.
  if [[ "$only_claude" == true ]]; then
    raw=$(printf '%s' "$raw" | awk -F'\t' '$3=="claude"')
  elif [[ "$only_cursor" == true ]]; then
    raw=$(printf '%s' "$raw" | awk -F'\t' '$3=="cursor"')
  fi

  # Drop blanks, sort by mtime desc, cap at limit.
  # -t$'\t' sets tab as field separator; -k1,1rn — numeric reverse on field 1.
  local sorted
  sorted=$(printf '%s' "$raw" | awk 'NF>0' | sort -t$'\t' -k1,1rn | head -n "$limit")

  if [[ -z "$sorted" ]]; then
    echo "No sessions found." >&2
    return 1
  fi

  # ── Build parallel arrays ─────────────────────────────────────
  # row_label[] holds the per-row workspace identifier — "pN" here in
  # clone mode; g-resume populates it with a "Where" label instead.
  local -a row_label=() row_tool=() row_id=() row_when=() row_title=()
  local mt cln tool sid title
  while IFS=$'\t' read -r mt cln tool sid title; do
    [[ -n "$mt" ]] || continue
    row_label+=("$cln")
    row_tool+=("$tool")
    row_id+=("$sid")
    row_when+=("$(_pwork_resume_relative_time "$mt")")
    row_title+=("$title")
  done <<< "$sorted"

  local row_count=${#row_label[@]}

  # ── Live-session detection (skipped under --force-new) ────────
  local live_data=""
  local -a is_open=()
  if [[ "$force_new" != "true" ]]; then
    live_data=$(_pwork_jump_live_claude_sessions)
  fi
  local _i _sid _tool _check
  for (( _i = 0; _i < row_count; _i++ )); do
    _sid="${row_id[$_i]}"
    _tool="${row_tool[$_i]}"
    _check=""
    if [[ "$force_new" == "true" ]]; then
      :
    elif [[ "$_tool" == "claude" && -n "$live_data" ]]; then
      _check=$(printf '%s\n' "$live_data" \
                 | awk -F'\t' -v s="$_sid" '$1==s {print "yes"; exit}')
    elif [[ "$_tool" == "cursor" ]]; then
      [[ -n "$(_pwork_jump_live_cursor_pid "$_sid")" ]] && _check="yes"
    fi
    if [[ "$_check" == "yes" ]]; then
      is_open[$_i]=1
    else
      is_open[$_i]=0
    fi
  done

  # p-resume N — jump straight to row N without rendering or prompting.
  if [[ -n "$jump" ]]; then
    if ! [[ "$jump" =~ ^[0-9]+$ ]] || [[ "$jump" -lt 1 ]] || [[ "$jump" -gt "$row_count" ]]; then
      echo "Error: invalid row '$jump' (have $row_count session(s))" >&2
      return 1
    fi
    local i=$(( jump - 1 ))
    _pwork_resume_exec "${row_tool[$i]}" "${row_id[$i]}" "$root/${row_label[$i]}" "$force_new"
    return $?
  fi

  # ── Render ───────────────────────────────────────────────────
  local show_tool=true
  if [[ "$only_claude" == true ]] || [[ "$only_cursor" == true ]]; then
    show_tool=false
  fi
  local _any_live=0 _i2
  for (( _i2 = 0; _i2 < row_count; _i2++ )); do
    [[ "${is_open[$_i2]}" == "1" ]] && _any_live=1
  done
  # render reads row_when/row_label/row_tool/row_title/is_open from this scope.
  _pwork_resume_render "$show_tool" "$_any_live" "$row_count" "Clone"

  # ── Prompt + dispatch ─────────────────────────────────────────
  echo ""
  local choice
  # Prompt to stderr so it shows even when stdout is captured/redirected.
  printf "Session #: " >&2
  read -r choice

  # Empty (just enter) — user changed their mind, do nothing.
  [[ -z "$choice" ]] && return 0

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt "$row_count" ]]; then
    echo "Invalid choice: $choice" >&2
    return 1
  fi

  local idx=$(( choice - 1 ))
  _pwork_resume_exec "${row_tool[$idx]}" "${row_id[$idx]}" "$root/${row_label[$idx]}" "$force_new"
}
