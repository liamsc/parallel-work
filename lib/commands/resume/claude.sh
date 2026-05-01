#!/usr/bin/env bash
# Claude Code session helpers — everything that knows about Claude's
# on-disk format. Adding a new tool? Mirror this file.
#   _pwork_resume_encode_claude       — abs path → ~/.claude/projects/<name>
#   _pwork_resume_title_claude        — pull session title out of a jsonl
#   _pwork_jump_live_claude_sessions  — emit one TSV row per live session
#
# Test-only env: PWORK_CLAUDE_SESSIONS_DIR overrides $HOME/.claude/sessions.

# Encode an absolute path the way Claude names its dir under
# ~/.claude/projects: every / . _ becomes a dash; the leading / survives
# as a leading dash. e.g. /Users/me/.foo_bar/p1 → -Users-me--foo-bar-p1
_pwork_resume_encode_claude() {
  # ${var%/} strips a single trailing / if present.
  local p="${1%/}"
  # tr maps each char in the first set to the corresponding char in the second.
  printf '%s' "$p" | tr '/._' '---'
}

# Pull the AI-generated title from a Claude session jsonl; fall back to
# the first user message text. We grep first (stops at first match — fast
# even on huge transcripts) and then parse just that line with jq.
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
      # handle both so we don't print "[object Object]".
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

# Emit one TSV row per LIVE Claude session metadata file:
#   <sessionId>\t<pid>\t<cwd>\t<name>
# `name` is Claude's session slug (also written into the terminal title);
# window-jump uses it later to disambiguate when several Ghostty tabs
# share a cwd. Skips files whose pid is dead so callers don't act on
# stale state.
_pwork_jump_live_claude_sessions() {
  local dir="${PWORK_CLAUDE_SESSIONS_DIR:-$HOME/.claude/sessions}"
  [[ -d "$dir" ]] || return 0
  # nullglob makes an unmatched glob expand to nothing under zsh — bash's
  # default returns the literal pattern, which the -f guard below catches.
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    setopt localoptions nullglob
  fi
  local f sid pid cwd name
  for f in "$dir"/*.json; do
    [[ -f "$f" ]] || continue
    sid=$(jq -r  '.sessionId // ""' "$f" 2>/dev/null)
    pid=$(jq -r  '.pid // ""'       "$f" 2>/dev/null)
    cwd=$(jq -r  '.cwd // ""'       "$f" 2>/dev/null)
    name=$(jq -r '.name // ""'      "$f" 2>/dev/null)
    [[ -z "$sid" || -z "$pid" ]] && continue
    # Liveness probe: signal 0 is a "null" signal — kill performs all the
    # usual permission/existence checks but never actually delivers
    # anything to the target. So `kill -0 <pid>` exits 0 when the pid is
    # alive (and we can signal it) and non-zero when it's gone, which is
    # exactly what we want to filter out stale ~/.claude/sessions/*.json
    # files left behind by crashed/exited Claude processes. 2>/dev/null
    # swallows the "No such process" stderr on the failure path.
    kill -0 "$pid" 2>/dev/null || continue
    printf '%s\t%s\t%s\t%s\n' "$sid" "$pid" "$cwd" "$name"
  done
}
