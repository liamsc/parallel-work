#!/usr/bin/env bash
# g-resume — global cousin of p-resume. Lists Claude/Cursor sessions
# across every directory on disk, not just clones in the current
# parallel-work workspace. Useful when you remember "I was talking to
# Claude about X yesterday" but forgot which repo.
#
# All real work happens in the resume/ helpers — this file owns arg
# parsing, the global collection call, the post-collect pipeline, and
# dispatch. Mirrors p-resume's structure deliberately so the two
# commands are easy to compare.
#
# CLI:
#   g-resume [N] [--claude|--cursor] [--limit M] [--force-new]
#
# This file does not source helpers — lib/commands.sh loads every
# command file, and lib/commands/resume.sh sources every resume/ helper
# at startup. By the time the user invokes g-resume, all helpers exist.

g-resume() {
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    # ksharrays — zsh arrays start at 0 like bash. nullglob — unmatched
    # globs expand to nothing instead of staying literal. Both match
    # what the helpers expect.
    setopt localoptions ksharrays nullglob
  fi

  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required by g-resume. Install with: brew install jq" >&2
    return 1
  fi

  # ── Argument parsing ──────────────────────────────────────────
  local limit=15 jump="" only_claude=false only_cursor=false force_new=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --claude)    only_claude=true; shift ;;
      --cursor)    only_cursor=true; shift ;;
      --force-new) force_new=true; shift ;;
      --limit)     limit="${2:-}"; shift 2 ;;
      --limit=*)   limit="${1#--limit=}"; shift ;;
      -h|--help)
        cat >&2 <<'EOF'
Usage: g-resume [N] [--claude|--cursor] [--limit M] [--force-new]

  Lists Claude/Cursor sessions across all directories on disk
  regardless of parallel-work workspace.

  N            Jump to row N from the listing (no prompt).
  --claude     Show only Claude sessions (drops the Tool column).
  --cursor     Show only Cursor sessions (drops the Tool column).
  --limit M    Cap rows shown (default 15).
  --force-new  Skip "focus existing window" detection and always launch new.
EOF
        return 0
        ;;
      # [0-9]* — anything starting with a digit, used as a "jump to row" arg.
      [0-9]*)    jump="$1"; shift ;;
      *) echo "Usage: g-resume [N] [--claude|--cursor] [--limit M] [--force-new]" >&2; return 1 ;;
    esac
  done

  if [[ "$only_claude" == true ]] && [[ "$only_cursor" == true ]]; then
    echo "Error: --claude and --cursor are mutually exclusive" >&2
    return 1
  fi
  if ! [[ "$limit" =~ ^[0-9]+$ ]] || [[ "$limit" -lt 1 ]]; then
    echo "Error: --limit must be a positive integer" >&2
    return 1
  fi

  # ── Collect every session on disk ─────────────────────────────
  local raw
  raw=$(_pwork_resume_collect_global)

  # Filter by tool if requested. -F'\t' — tab-separated input fields.
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
  # row_label[] holds the "Where" label (pN, ~/path, or (unknown)).
  # row_cwd[] holds the absolute path dispatch will cd into.
  local -a row_label=() row_tool=() row_id=() row_when=() row_title=() row_cwd=()
  local mt label tool sid title cwd
  while IFS=$'\t' read -r mt label tool sid title cwd; do
    [[ -n "$mt" ]] || continue
    row_label+=("$label")
    row_tool+=("$tool")
    row_id+=("$sid")
    row_when+=("$(_pwork_resume_relative_time "$mt")")
    row_title+=("$title")
    row_cwd+=("$cwd")
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

  # g-resume N — jump straight to row N without rendering or prompting.
  if [[ -n "$jump" ]]; then
    if ! [[ "$jump" =~ ^[0-9]+$ ]] || [[ "$jump" -lt 1 ]] || [[ "$jump" -gt "$row_count" ]]; then
      echo "Error: invalid row '$jump' (have $row_count session(s))" >&2
      return 1
    fi
    local i=$(( jump - 1 ))
    _pwork_resume_exec "${row_tool[$i]}" "${row_id[$i]}" "${row_cwd[$i]}" "$force_new"
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
  _pwork_resume_render "$show_tool" "$_any_live" "$row_count" "Where"

  # ── Prompt + dispatch ─────────────────────────────────────────
  echo ""
  local choice
  printf "Session #: " >&2
  read -r choice

  [[ -z "$choice" ]] && return 0

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt "$row_count" ]]; then
    echo "Invalid choice: $choice" >&2
    return 1
  fi

  local idx=$(( choice - 1 ))
  _pwork_resume_exec "${row_tool[$idx]}" "${row_id[$idx]}" "${row_cwd[$idx]}" "$force_new"
}
