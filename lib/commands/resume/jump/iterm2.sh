#!/usr/bin/env bash
# iTerm2 window-focus via AppleScript. Precise: iTerm2 exposes the `tty`
# property on each session, so we can match exactly the tab+session
# running our PID.
#
# Returns 0 only when we located AND selected the matching session.
# Anything else (no match, AppleScript error) returns non-zero so the
# caller can print a more honest "couldn't pinpoint" hint.

_pwork_jump_focus_iterm2() {
  local tty="$1"
  [[ -z "$tty" ]] && return 1
  local result
  # osascript - reads the script from stdin and forwards extra args as
  # argv; this avoids string-interpolation injection into the AppleScript
  # body if the tty path ever contained meta characters.
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
