#!/usr/bin/env bash
# Ghostty window-focus via AppleScript. Best-effort: AppleScript was added
# in Ghostty 1.3.0 but doesn't expose the tty — the only per-terminal
# properties are `id`, `name`, and `working directory`. So we disambiguate
# in two passes:
#
#   1. Name match — Claude Code writes the session slug into the terminal
#      title (e.g. "⠂ detect-and-focus-active-session"). When the session
#      metadata's `name` is non-empty AND uniquely matches one terminal,
#      that's the strongest signal.
#   2. Cwd fallback — for sessions without a name, or when name didn't
#      uniquely match, fall back to `working directory` equality.
#
# Returns 0 only when exactly one terminal matched (by name OR cwd). When
# 0 or 2+ match, we still `activate` so the app comes to front, but
# return non-zero so the caller can print a "couldn't pinpoint" hint.

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
    -- Prefer a unique name match (precise). Fall back to a unique cwd
    -- match. Anything else: just activate so the app comes to front.
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
  # Both ok-name and ok-cwd count as "we focused a specific tab".
  [[ "$result" == "ok-name" || "$result" == "ok-cwd" ]]
}
