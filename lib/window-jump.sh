#!/usr/bin/env bash
# Window-jump helpers: detect whether a Claude/Cursor session is currently
# running in a known terminal app, and (when possible) raise + select that
# terminal's tab. p-resume calls these to focus an existing session instead
# of launching a duplicate.
#
# Test-only env overrides:
#   PWORK_CLAUDE_SESSIONS_DIR — overrides $HOME/.claude/sessions

# Emit one record per LIVE Claude session metadata file:
#   <sessionId>\t<pid>\t<cwd>\t<name>
# `name` is the session's slug (Claude writes this into the terminal title,
# prefixed with a status glyph) — we use it later to pick the right tab when
# multiple terminals share a cwd. Skips files whose pid is dead so callers
# don't act on stale state.
_pwork_jump_live_claude_sessions() {
  local dir="${PWORK_CLAUDE_SESSIONS_DIR:-$HOME/.claude/sessions}"
  [[ -d "$dir" ]] || return 0
  # nullglob makes an unmatched glob expand to nothing under zsh — without
  # it, an empty dir would error out. Bash's default returns the literal
  # pattern, which the -f guard below catches anyway.
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    setopt localoptions nullglob
  fi
  local f sid pid cwd name
  for f in "$dir"/*.json; do
    [[ -f "$f" ]] || continue
    # // "" — jq fallback if the field is missing; the [[ -z … ]] guard
    # below then drops the row when the required fields are missing.
    sid=$(jq -r  '.sessionId // ""' "$f" 2>/dev/null)
    pid=$(jq -r  '.pid // ""'       "$f" 2>/dev/null)
    cwd=$(jq -r  '.cwd // ""'       "$f" 2>/dev/null)
    name=$(jq -r '.name // ""'      "$f" 2>/dev/null)
    [[ -z "$sid" || -z "$pid" ]] && continue
    # kill -0 sends signal 0 — fails iff the pid doesn't exist (or we lack
    # permission, which doesn't happen for our own processes).
    kill -0 "$pid" 2>/dev/null || continue
    printf '%s\t%s\t%s\t%s\n' "$sid" "$pid" "$cwd" "$name"
  done
}

# Find a live PID running `cursor agent --resume <session-id>`. Anchors the
# regex tightly to avoid catching unrelated processes whose argv happens to
# contain the session UUID.
_pwork_jump_live_cursor_pid() {
  local sid="$1"
  [[ -z "$sid" ]] && return 0
  # pgrep -f matches against the full command line (not just the executable).
  # head -1 takes only the first match.
  pgrep -f "cursor.*agent.*--resume.*$sid" 2>/dev/null | head -1
}

# /dev/$(ps -o tty= -p $pid). Returns non-zero if no tty (daemon or dead pid).
_pwork_jump_pid_tty() {
  local pid="$1" tty
  # tr -d ' ' strips the leading whitespace ps adds for column padding.
  tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
  # ?? — ps's "no controlling terminal" sentinel.
  [[ -z "$tty" || "$tty" == "??" ]] && return 1
  printf '/dev/%s' "$tty"
}

# Walk the ppid chain from $1 upward looking for a known terminal app
# process. Echoes one of: iterm2 | ghostty | terminal | unknown.
_pwork_jump_pid_terminal() {
  local pid="$1" comm
  # Stop at pid 1 (init/launchd) — anything higher means we're still walking.
  while [[ -n "$pid" && "$pid" != "1" && "$pid" != "0" ]]; do
    # xargs trims surrounding whitespace from ps's output.
    comm=$(ps -o comm= -p "$pid" 2>/dev/null | xargs)
    case "$comm" in
      *iTerm2*|*iTerm.app*)    echo "iterm2";   return 0 ;;
      *Ghostty*|*ghostty*)     echo "ghostty";  return 0 ;;
      */Terminal|*Terminal.app*|Terminal) echo "terminal"; return 0 ;;
    esac
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | xargs)
  done
  echo "unknown"
}

# Focus the iTerm2 session whose tty matches $1. Returns 0 only if the
# AppleScript actually located and selected the matching session.
_pwork_jump_focus_iterm2() {
  local tty="$1"
  [[ -z "$tty" ]] && return 1
  # osascript - reads the script from stdin and forwards extra args as argv;
  # this avoids string-interpolation injection into the AppleScript body.
  local result
  result=$(osascript - "$tty" 2>/dev/null <<'OSASCRIPT'
on run argv
  set targetTTY to item 1 of argv
  tell application "iTerm"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if tty of s is targetTTY then
            tell w to select t
            tell t to select s
            activate
            return "ok"
          end if
        end repeat
      end repeat
    end repeat
    return "no-match"
  end tell
end run
OSASCRIPT
  )
  [[ "$result" == "ok" ]]
}

# Best-effort focus for Ghostty: AppleScript (added in 1.3.0) doesn't expose
# the tty — the only per-terminal properties are `id`, `name`, and
# `working directory`. So we disambiguate two ways:
#
#   1. Name match: Claude Code writes the session slug into the terminal
#      title (prefixed with a status glyph like "⠂"). When the session
#      metadata's `name` is non-empty, we look for a terminal whose `name`
#      property contains that slug — strong, claude-specific signal.
#   2. Cwd fallback: when the session has no name, or no terminal matches
#      the name, we match by `working directory`.
#
# Returns 0 only when exactly one terminal matched (by name OR cwd) and we
# focused it. When 0 or 2+ match we activate the app so it comes to front
# and return non-zero so the caller prints a more honest "couldn't pinpoint"
# hint.
_pwork_jump_focus_ghostty() {
  local cwd="$1" name="${2:-}"
  [[ -z "$cwd" ]] && return 1
  local result
  result=$(osascript - "$cwd" "$name" 2>/dev/null <<'OSASCRIPT'
on run argv
  set targetCwd to item 1 of argv
  set targetName to ""
  if (count of argv) is greater than or equal to 2 then
    set targetName to item 2 of argv
  end if
  tell application "Ghostty"
    set nameMatch to missing value
    set nameCount to 0
    set cwdMatch to missing value
    set cwdCount to 0
    repeat with w in windows
      repeat with t in tabs of w
        repeat with term in terminals of t
          set termName to ""
          try
            set termName to (name of term) as text
          end try
          set termCwd to ""
          try
            set termCwd to (working directory of term) as text
          end try
          if targetName is not "" and termName contains targetName then
            set nameCount to nameCount + 1
            if nameCount is 1 then set nameMatch to term
          end if
          if termCwd is targetCwd then
            set cwdCount to cwdCount + 1
            if cwdCount is 1 then set cwdMatch to term
          end if
        end repeat
      end repeat
    end repeat
    -- Prefer a unique name match (precise). Fall back to a unique cwd match.
    -- Anything else: just activate so the app at least comes to front.
    if nameCount is 1 then
      tell nameMatch to focus
      return "ok-name"
    else if cwdCount is 1 then
      tell cwdMatch to focus
      return "ok-cwd"
    else
      activate
      if (cwdCount + nameCount) is 0 then
        return "no-match"
      else
        return "multi-match"
      end if
    end if
  end tell
end run
OSASCRIPT
  )
  # Both ok-name and ok-cwd count as success.
  [[ "$result" == "ok-name" || "$result" == "ok-cwd" ]]
}

# Top-level: try to focus the window currently hosting <session-id>.
# Args: <session-id> <tool: claude|cursor> <session-cwd>
# Returns 0 if the situation is "handled" — caller should NOT launch new.
# Returns non-zero if the session isn't open anywhere — caller may launch.
# Prints a single status line to stderr so the user understands what happened.
_pwork_jump_window() {
  local sid="$1" tool="$2" sess_cwd="$3"
  [[ -z "$sid" ]] && return 1

  # Step 1: find the live PID for this session, by tool. For Claude we also
  # read the session "name" out of the metadata — Ghostty uses it to pick
  # the right tab when several share a cwd.
  local pid="" name=""
  case "$tool" in
    claude)
      local row
      row=$(_pwork_jump_live_claude_sessions \
              | awk -F'\t' -v s="$sid" '$1==s {print; exit}')
      [[ -n "$row" ]] || return 1
      # cut -f<N> — split on tabs and pull the Nth field (1-indexed).
      pid=$(printf  '%s' "$row" | cut -f2)
      name=$(printf '%s' "$row" | cut -f4)
      ;;
    cursor)
      pid=$(_pwork_jump_live_cursor_pid "$sid")
      [[ -n "$pid" ]] || return 1
      ;;
    *)
      return 1
      ;;
  esac

  # Step 2: figure out which terminal app is hosting that PID.
  local terminal
  terminal=$(_pwork_jump_pid_terminal "$pid")

  # Step 3: dispatch to the per-terminal focus function. In every "open"
  # branch we return 0 so the caller doesn't launch a duplicate — even when
  # the terminal isn't fully scriptable (the user is told to switch manually).
  case "$terminal" in
    iterm2)
      local tty
      if ! tty=$(_pwork_jump_pid_tty "$pid"); then
        echo "Session is open but its tty couldn't be resolved." >&2
        return 0
      fi
      if _pwork_jump_focus_iterm2 "$tty"; then
        echo "Focused existing iTerm2 tab." >&2
      else
        echo "Session is open in iTerm2, but the matching tab couldn't be located." >&2
      fi
      return 0
      ;;
    ghostty)
      if _pwork_jump_focus_ghostty "$sess_cwd" "$name"; then
        echo "Focused existing Ghostty tab." >&2
      else
        echo "Session is open in Ghostty; brought app to front (couldn't pinpoint tab)." >&2
      fi
      return 0
      ;;
    terminal|unknown)
      echo "Session is running in $terminal, which doesn't support auto-focus — switch manually." >&2
      return 0
      ;;
  esac
  return 1
}
