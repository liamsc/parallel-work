#!/usr/bin/env bash
# Cursor session helpers — everything that knows about Cursor's on-disk
# format and process model. Adding a new tool? Mirror this file.
#   _pwork_resume_encode_cursor    — abs path → ~/.cursor/projects/<name>
#   _pwork_resume_title_cursor     — pull session title out of a jsonl
#   _pwork_jump_live_cursor_pid    — pgrep for an active `cursor agent`

# Encode an absolute path the way Cursor names its dir under
# ~/.cursor/projects: / and _ become dashes, dots are dropped, no leading
# dash. e.g. /Users/me/.foo_bar/p1 → Users-me-foo-bar-p1
_pwork_resume_encode_cursor() {
  local p="${1%/}"
  # ${var#/} strips a single leading / if present.
  p="${p#/}"
  # ${var//pattern} with empty replacement deletes every match of pattern.
  p="${p//./}"
  printf '%s' "$p" | tr '/_' '--'
}

# Cursor stores the first user message as content[0].text. Cursor wraps
# prompts in <user_query>…</user_query> alongside <attached_files> noise —
# when present, extract just the user_query so the title isn't a dump of
# attached file contents.
_pwork_resume_title_cursor() {
  local f="$1" line t="" inside
  line=$(grep -m 1 '"role":"user"' "$f" 2>/dev/null)
  if [[ -n "$line" ]]; then
    t=$(printf '%s' "$line" | jq -r '.message.content[0].text // ""' 2>/dev/null)
  fi
  # Collapse newlines first — sed processes line-by-line, but jq returns
  # the text with real newlines, and the user_query block often spans
  # multiple lines. sed -n suppresses default output; -E enables extended
  # regex; p prints matches.
  inside=$(printf '%s' "$t" | tr '\n' ' ' | sed -nE 's/.*<user_query>[[:space:]]*([^<]+).*/\1/p')
  [[ -n "$inside" ]] && t="$inside"
  _pwork_resume_truncate "$t"
}

# Find a live PID running `cursor agent --resume <session-id>`. Anchors
# the regex tightly to avoid catching unrelated processes whose argv just
# happens to contain the session UUID. Returns the pid (one line) or
# empty if no match.
_pwork_jump_live_cursor_pid() {
  local sid="$1"
  [[ -z "$sid" ]] && return 0
  # pgrep -f matches against the full command line (not just executable).
  # head -1 takes only the first match.
  pgrep -f "cursor.*agent.*--resume.*$sid" 2>/dev/null | head -1
}
