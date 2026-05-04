#!/usr/bin/env bash
# Per-PID terminal lookup — given a session's PID, figure out
#   (a) what TTY device it's attached to, and
#   (b) which terminal app is hosting it (so we know which AppleScript
#       module to dispatch to).
#
# These two helpers are the bridge between "we found a live PID" and
# "we're going to talk to a specific terminal app". Pure ps-walking;
# no AppleScript lives here.

# /dev/$(ps -o tty= -p $pid). Returns non-zero if no controlling tty
# (daemon or dead pid).
_pwork_jump_pid_tty() {
  local pid="$1" tty
  # tr -d ' ' strips the leading whitespace ps adds for column padding.
  tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
  # ?? — ps's "no controlling terminal" sentinel.
  [[ -z "$tty" || "$tty" == "??" ]] && return 1
  printf '/dev/%s' "$tty"
}

# Walk the ppid chain from $1 upward looking for a known terminal-app
# process. Echoes one of:
#   iterm2 | ghostty | terminal — known terminal app, AppleScript-focusable
#   detached                    — chain reached launchd (pid 1) without
#                                 finding any terminal; the process has no
#                                 controlling terminal. Common case:
#                                 `cursor-agent` daemonizes itself, so its
#                                 parent becomes launchd and TTY is "??".
#                                 There is nothing to focus — caller should
#                                 just launch fresh.
#   unknown                     — walked through processes we don't know
#                                 (alacritty, kitty, wezterm, …); session
#                                 IS in a terminal window we can't script.
#                                 Caller should warn rather than launch.
_pwork_jump_pid_terminal() {
  local pid="$1" comm
  # Stop at pid 1 (init/launchd) — anything higher means we're still walking.
  while [[ -n "$pid" && "$pid" != "1" && "$pid" != "0" ]]; do
    # xargs trims surrounding whitespace from ps's output.
    comm=$(ps -o comm= -p "$pid" 2>/dev/null | xargs)
    case "$comm" in
      *iTerm2*|*iTerm.app*)               echo "iterm2";   return 0 ;;
      *Ghostty*|*ghostty*)                echo "ghostty";  return 0 ;;
      */Terminal|*Terminal.app*|Terminal) echo "terminal"; return 0 ;;
    esac
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | xargs)
  done
  # If we walked all the way to launchd, the process has no parent terminal
  # at all. Distinguish from the "unknown terminal app" case so the caller
  # can launch fresh instead of telling the user to "switch manually" to a
  # window that doesn't exist.
  if [[ "$pid" == "1" || "$pid" == "0" ]]; then
    echo "detached"
  else
    echo "unknown"
  fi
}
