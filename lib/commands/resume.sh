#!/usr/bin/env bash
# p-resume: list recent Claude Code and Cursor sessions across all clones in
# the current workspace, newest first, with a numeric hotkey to resume one
# with bypass permissions.
#
# Sessions live at:
#   ~/.claude/projects/<encoded-cwd>/<session-id>.jsonl
#   ~/.cursor/projects/<encoded-cwd>/agent-transcripts/<agent-id>/<agent-id>.jsonl
# (encoding rules differ — see helpers below). The PWORK_CLAUDE_PROJECTS_DIR
# and PWORK_CURSOR_PROJECTS_DIR env vars override the roots for testing.

# Encode an absolute path the way Claude names its dir under ~/.claude/projects:
# every / . _ becomes a dash; the leading / survives as a leading dash.
# e.g. /Users/me/.foo_bar/p1 → -Users-me--foo-bar-p1
_pwork_resume_encode_claude() {
  # ${var%/} strips a single trailing / if present.
  local p="${1%/}"
  # tr maps each char in the first set to the corresponding char in the second.
  printf '%s' "$p" | tr '/._' '---'
}

# Encode an absolute path the way Cursor names its dir under ~/.cursor/projects:
# / and _ become dashes, dots are dropped, no leading dash.
# e.g. /Users/me/.foo_bar/p1 → Users-me-foo-bar-p1
_pwork_resume_encode_cursor() {
  local p="${1%/}"
  # ${var#/} strips a single leading / if present.
  p="${p#/}"
  # ${var//pattern} with empty replacement deletes every match of pattern.
  p="${p//./}"
  printf '%s' "$p" | tr '/_' '--'
}

# Squash newlines/tabs to spaces and cap at 60 chars so the row stays one line.
_pwork_resume_truncate() {
  # ${var//pattern/replacement} replaces every occurrence.
  local s="${1//$'\n'/ }"
  s="${s//$'\t'/ }"
  if [[ -z "$s" ]]; then
    printf '%s' "(no title)"
    return
  fi
  # ${#var} is the string length.
  if [[ ${#s} -gt 60 ]]; then
    # ${var:offset:length} is substring extraction.
    s="${s:0:59}…"
  fi
  printf '%s' "$s"
}

# Pull the AI-generated title from a Claude session jsonl; fall back to the
# first user message text. We grep first (stops at first match — fast even on
# huge transcripts) and then parse just that one line with jq.
_pwork_resume_title_claude() {
  local f="$1" line t=""
  # grep -m 1 stops after the first match.
  line=$(grep -m 1 '"type":"ai-title"' "$f" 2>/dev/null)
  if [[ -n "$line" ]]; then
    # // "" — jq fallback if the field is missing or null.
    t=$(printf '%s' "$line" | jq -r '.aiTitle // ""' 2>/dev/null)
  fi
  if [[ -z "$t" ]]; then
    line=$(grep -m 1 '"type":"user"' "$f" 2>/dev/null)
    if [[ -n "$line" ]]; then
      # .message.content can be a string OR an array of typed parts —
      # handle both shapes so we don't print "[object Object]".
      t=$(printf '%s' "$line" | jq -r '
            .message.content
            | if type=="string" then .
              elif type=="array" then (.[0].text // "")
              else "" end
          ' 2>/dev/null)
    fi
  fi
  _pwork_resume_truncate "$t"
}

# Cursor stores the first user message as content[0].text. Cursor wraps prompts
# in <user_query>…</user_query> alongside <attached_files> noise — when present,
# extract just the user_query so the title isn't a dump of file contents.
_pwork_resume_title_cursor() {
  local f="$1" line t="" inside
  line=$(grep -m 1 '"role":"user"' "$f" 2>/dev/null)
  if [[ -n "$line" ]]; then
    t=$(printf '%s' "$line" | jq -r '.message.content[0].text // ""' 2>/dev/null)
  fi
  # Collapse newlines first — sed processes line-by-line, but jq returns the
  # text with real newlines (the JSON \n escapes get interpreted), and the
  # <user_query>…</user_query> contents commonly span multiple lines.
  # sed -n suppresses default output; -E enables extended regex; p prints matches.
  inside=$(printf '%s' "$t" | tr '\n' ' ' | sed -nE 's/.*<user_query>[[:space:]]*([^<]+).*/\1/p')
  [[ -n "$inside" ]] && t="$inside"
  _pwork_resume_truncate "$t"
}

# Format an epoch-seconds delta as "Xs/m/h/d ago". Pure shell math so we don't
# depend on GNU date (macOS ships BSD date).
_pwork_resume_relative_time() {
  local then="$1" now diff
  now=$(date +%s)
  # (( … )) is arithmetic context — no $ needed for variables.
  (( diff = now - then ))
  if   (( diff < 60 ));    then printf '%ds ago'  "$diff"
  elif (( diff < 3600 ));  then printf '%dm ago'  "$((diff / 60))"
  elif (( diff < 86400 )); then printf '%dh ago'  "$((diff / 3600))"
  else                          printf '%dd ago'  "$((diff / 86400))"
  fi
}

# For one clone, emit one tab-separated record per session:
#   <mtime>\t<clone>\t<tool>\t<session-id>\t<title>
# so the caller can sort by mtime once across all clones.
_pwork_resume_collect_clone() {
  local clone_path="$1" clone_name="$2"
  # ${VAR:-default} expands to default if VAR is unset or empty.
  local claude_root="${PWORK_CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
  local cursor_root="${PWORK_CURSOR_PROJECTS_DIR:-$HOME/.cursor/projects}"
  local enc f mt id title

  # Claude: one .jsonl per session, directly under the encoded dir.
  enc="$(_pwork_resume_encode_claude "$clone_path")"
  for f in "$claude_root/$enc"/*.jsonl; do
    # An unmatched glob expands to its literal pattern — guard with -f.
    [[ -f "$f" ]] || continue
    # stat -f %m is the BSD/macOS form of "epoch mtime"; -c %Y is GNU.
    mt=$(stat -f %m "$f" 2>/dev/null) || continue
    id="$(basename "$f" .jsonl)"
    title="$(_pwork_resume_title_claude "$f")"
    printf '%s\t%s\t%s\t%s\t%s\n' "$mt" "$clone_name" "claude" "$id" "$title"
  done

  # Cursor: <encoded>/agent-transcripts/<uuid>/<uuid>.jsonl
  enc="$(_pwork_resume_encode_cursor "$clone_path")"
  for f in "$cursor_root/$enc/agent-transcripts"/*/*.jsonl; do
    [[ -f "$f" ]] || continue
    mt=$(stat -f %m "$f" 2>/dev/null) || continue
    # The agent-id is the parent directory name.
    id="$(basename "$(dirname "$f")")"
    title="$(_pwork_resume_title_cursor "$f")"
    printf '%s\t%s\t%s\t%s\t%s\n' "$mt" "$clone_name" "cursor" "$id" "$title"
  done
}

# Dispatch into claude or cursor with bypass permissions / explicit workspace.
# When force_new is "false" (default), first try to focus an existing terminal
# window already running this session — _pwork_jump_window prints its own
# one-line status and returns 0 if it handled the situation (focus succeeded
# OR session is open elsewhere but unfocusable). Returns non-zero only when
# the session is not currently running, which is when we launch new.
# p-resume is a shell function (sourced into the user's shell), so cd persists.
_pwork_resume_exec() {
  local clone="$1" tool="$2" sid="$3" root="$4" force_new="${5:-false}"

  if [[ "$force_new" != "true" ]]; then
    if _pwork_jump_window "$sid" "$tool" "$root/$clone"; then
      return 0
    fi
  fi

  case "$tool" in
    claude)
      cd "$root/$clone" || return 1
      # Claude Code sets CLAUDECODE in its child shells. If the user invokes
      # p-resume from inside an existing session, launching another claude
      # nests them — surface a one-line note but proceed.
      if [[ -n "${CLAUDECODE:-}" ]]; then
        echo "Note: launching claude inside an existing Claude Code session." >&2
      fi
      echo "Launching claude --resume $sid --dangerously-skip-permissions" >&2
      claude --resume "$sid" --dangerously-skip-permissions
      ;;
    cursor)
      # command -v <name> is the portable "is this on PATH?" check.
      if ! command -v cursor &>/dev/null; then
        echo "Error: 'cursor' is not on PATH." >&2
        echo "  In Cursor: open the command palette and run \"Shell Command: Install 'cursor' command\"." >&2
        return 1
      fi
      echo "Launching cursor agent --resume $sid --workspace $root/$clone" >&2
      cursor agent --resume "$sid" --workspace "$root/$clone"
      ;;
    *)
      echo "Error: unknown tool '$tool'" >&2
      return 1
      ;;
  esac
}

p-resume() {
  # zsh arrays default to 1-indexed; ksharrays makes them 0-indexed like bash
  # so the indexing below is portable across shells. nullglob makes an
  # unmatched glob expand to nothing instead of erroring (zsh default) or
  # returning the literal pattern (bash default) — needed so the for-loops
  # over *.jsonl in _pwork_resume_collect_clone don't blow up on empty dirs.
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

  local limit=15 jump="" filter_clone="" only_claude=false only_cursor=false force_new=false
  # $# is the number of remaining args; -gt 0 means "more args to parse".
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
      # p[0-9]* matches a literal "p" followed by a digit and anything after.
      p[0-9]*)   filter_clone="$1"; shift ;;
      # [0-9]* matches anything starting with a digit.
      [0-9]*)    jump="$1"; shift ;;
      *) echo "Usage: p-resume [N] [pN] [--claude|--cursor] [--limit M] [--force-new]" >&2; return 1 ;;
    esac
  done

  if [[ "$only_claude" == true ]] && [[ "$only_cursor" == true ]]; then
    echo "Error: --claude and --cursor are mutually exclusive" >&2
    return 1
  fi

  # =~ is regex match; ^[0-9]+$ means "one or more digits, nothing else".
  if ! [[ "$limit" =~ ^[0-9]+$ ]] || [[ "$limit" -lt 1 ]]; then
    echo "Error: --limit must be a positive integer" >&2
    return 1
  fi

  # Pick the clone set we'll scan.
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

  # Walk every clone, collecting tab-separated records into one big buffer.
  local clone raw=""
  while IFS= read -r clone; do
    [[ -n "$clone" ]] || continue
    raw+="$(_pwork_resume_collect_clone "$root/$clone" "$clone")"$'\n'
  done <<< "$clones"

  # Filter by tool if asked.
  if [[ "$only_claude" == true ]]; then
    raw=$(printf '%s' "$raw" | awk -F'\t' '$3=="claude"')
  elif [[ "$only_cursor" == true ]]; then
    raw=$(printf '%s' "$raw" | awk -F'\t' '$3=="cursor"')
  fi

  # Drop blank lines, sort by mtime descending, cap at limit.
  # -t$'\t' sets tab as field separator; -k1,1rn — numeric reverse on field 1.
  local sorted
  sorted=$(printf '%s' "$raw" | awk 'NF>0' | sort -t$'\t' -k1,1rn | head -n "$limit")

  if [[ -z "$sorted" ]]; then
    echo "No sessions found." >&2
    return 1
  fi

  # Slot rows into parallel arrays so we can index by 1-based row number.
  local -a row_clone=() row_tool=() row_id=() row_when=() row_title=()
  local mt cln tool sid title
  while IFS=$'\t' read -r mt cln tool sid title; do
    [[ -n "$mt" ]] || continue
    row_clone+=("$cln")
    row_tool+=("$tool")
    row_id+=("$sid")
    row_when+=("$(_pwork_resume_relative_time "$mt")")
    row_title+=("$title")
  done <<< "$sorted"

  local row_count=${#row_clone[@]}

  # Live-session detection. One scan of ~/.claude/sessions/ feeds both the
  # "live" column in the rendered table AND the focus-existing-window
  # dispatch in _pwork_resume_exec. Skip when --force-new is set.
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
      # awk prints "yes" iff $1 (sessionId) matches; otherwise empty.
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
    _pwork_resume_exec "${row_clone[$i]}" "${row_tool[$i]}" "${row_id[$i]}" "$root" "$force_new"
    return $?
  fi

  # Render. Drop the Tool column when filtered to a single tool.
  local show_tool=true
  if [[ "$only_claude" == true ]] || [[ "$only_cursor" == true ]]; then
    show_tool=false
  fi

  # ANSI color codes. -t 1 tests whether stdout is a terminal — when
  # piped/captured (e.g. by tests), we skip codes so output stays plain text.
  local c_claude="" c_cursor="" c_live="" c_reset=""
  if [[ -t 1 ]]; then
    c_claude=$'\033[33m'   # yellow — Claude
    c_cursor=$'\033[36m'   # cyan   — Cursor
    c_live=$'\033[32m'     # green  — "session is live"
    c_reset=$'\033[0m'
  fi

  # Show a hint above the table only when at least one row is live, so the
  # ● glyph isn't mysterious — but the listing isn't cluttered when nothing
  # is open.
  local _any_live=0
  for (( i = 0; i < row_count; i++ )); do
    [[ "${is_open[$i]}" == "1" ]] && _any_live=1
  done
  if [[ "$_any_live" == "1" ]]; then
    printf "%s●%s = currently open in a terminal — selecting one will jump to its window\n\n" \
      "$c_live" "$c_reset"
  fi

  # The leading "L" column is a single character wide. It holds ● (open) or
  # blank (closed). We always render it so the rest of the table aligns.
  if [[ "$show_tool" == true ]]; then
    printf "%s  %-3s  %-10s  %-5s  %-9s  %s\n" " " "#" "When" "Clone" "Tool" "Title"
    printf "%s  %-3s  %-10s  %-5s  %-9s  %s\n" " " "---" "----------" "-----" "---------" "-----"
  else
    printf "%s  %-3s  %-10s  %-5s  %s\n" " " "#" "When" "Clone" "Title"
    printf "%s  %-3s  %-10s  %-5s  %s\n" " " "---" "----------" "-----" "-----"
  fi

  local i n color glyph live_marker
  for (( i = 0; i < row_count; i++ )); do
    n=$(( i + 1 ))
    # Live marker: green ● when the session has a running PID, else a
    # single space so the column width stays constant. Glyph alone (no
    # color) is enough for colorblind readers.
    if [[ "${is_open[$i]}" == "1" ]]; then
      live_marker="${c_live}●${c_reset}"
    else
      live_marker=" "
    fi
    if [[ "$show_tool" == true ]]; then
      # Two redundant visual cues per tool: a leading glyph (works for
      # colorblind readers and on terminals that strip color) and an ANSI
      # color (works on a glance for everyone else).
      case "${row_tool[$i]}" in
        claude) color="$c_claude"; glyph="*" ;;
        cursor) color="$c_cursor"; glyph=">" ;;
        *)      color="";          glyph=" " ;;
      esac
      # %s%-9s%s — color codes wrap the padded "<glyph> <tool>" cell. ANSI
      # codes have zero printed width, so column alignment is preserved.
      printf "%s  %-3s  %-10s  %-5s  %s%-9s%s  %s\n" \
        "$live_marker" "$n" "${row_when[$i]}" "${row_clone[$i]}" \
        "$color" "$glyph ${row_tool[$i]}" "$c_reset" "${row_title[$i]}"
    else
      printf "%s  %-3s  %-10s  %-5s  %s\n" \
        "$live_marker" "$n" "${row_when[$i]}" "${row_clone[$i]}" "${row_title[$i]}"
    fi
  done

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
  _pwork_resume_exec "${row_clone[$idx]}" "${row_tool[$idx]}" "${row_id[$idx]}" "$root" "$force_new"
}
