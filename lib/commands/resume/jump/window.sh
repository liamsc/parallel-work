#!/usr/bin/env bash
# Top-level orchestrator: try to focus the terminal window currently
# hosting <session-id>. This file glues claude.sh / cursor.sh's live-PID
# discovery to terminal.sh's lookup chain to the per-app focus modules.
#
# Args: <session-id> <tool: claude|cursor> <session-cwd>
#
# Return convention:
#   0 — situation is "handled" (focused, or open elsewhere but unsupported
#       terminal so we deliberately refuse to launch a duplicate). Caller
#       should NOT launch new.
#   non-zero — session isn't open anywhere we can detect; caller may
#       launch fresh.
#
# Always prints exactly one status line to stderr so the user understands
# what just happened.

_pwork_jump_window() {
  local sid="$1" tool="$2" sess_cwd="$3"
  [[ -z "$sid" ]] && return 1

  # Step 1: find the live PID for this session, by tool. For Claude we
  # also lift the session "name" out of the metadata — Ghostty needs it
  # to disambiguate when several tabs share a cwd.
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
  # branch we return 0 so the caller doesn't launch a duplicate — even
  # when the terminal isn't fully scriptable (the user is asked to switch
  # manually instead).
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
      # Real terminal window the user could find on their own; refuse to
      # launch a duplicate that would visibly nest two agents.
      echo "Session is running in $terminal, which doesn't support auto-focus — switch manually." >&2
      return 0
      ;;
    detached)
      # Process has no controlling terminal — cursor-agent daemonizes
      # itself, so this is the common case for live Cursor sessions.
      # There's no window to focus and no duplicate to worry about; let
      # the caller launch fresh so the user can actually resume.
      return 1
      ;;
  esac
  return 1
}
