#!/usr/bin/env bash
# Cursor.app focus — used when a cursor-agent process is daemonized
# (parent = launchd, no TTY). Cursor.app spawns cursor-agent and shows
# the chat UI in one of its own panels, so the user's "live tab" lives
# in Cursor.app, not in any terminal we can AppleScript-navigate to.
#
# We can't pinpoint the specific session inside Cursor.app — it's an
# Electron app with very limited AppleScript surface — but `activate`
# brings the app forward and the user lands on the panel they were last
# using, which is usually the one they wanted.
#
# Returns 0 only if Cursor.app is currently running AND activate
# succeeded; non-zero lets the caller fall through to launch-new.

_pwork_jump_focus_cursor_app() {
  # pgrep -f against the main app binary — careful not to match
  # `cursor-agent` itself (which contains the substring "cursor"). The
  # full Applications path is unique to the GUI app process.
  if ! pgrep -f 'Applications/Cursor\.app/Contents/MacOS/Cursor' &>/dev/null; then
    return 1
  fi
  osascript -e 'tell application "Cursor" to activate' &>/dev/null
}
