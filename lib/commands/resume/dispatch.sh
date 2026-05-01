#!/usr/bin/env bash
# Dispatch a selected row — pick "focus existing window" vs "launch new".
# This is the boundary between "the user picked a row" and "something
# actually happens".
#
# Behavior:
#   1. Unless --force-new is set, ask jump/window.sh to focus an existing
#      terminal window for this session. If it succeeds (or politely
#      refuses for an unsupported terminal), we're done — return 0 so
#      the caller doesn't spawn a duplicate.
#   2. Otherwise launch fresh:
#        claude --resume <id> --dangerously-skip-permissions   (in clone cwd)
#        cursor agent --resume <id> --workspace <clone>        (cwd via flag)
#
# p-resume is sourced into the user's shell, so the `cd` in the claude
# branch persists — same pattern as p1/pw.

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
      # Claude Code sets CLAUDECODE in its child shells. If the user
      # invokes p-resume from inside an existing session, launching
      # another claude nests them — surface a one-line note but proceed.
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
