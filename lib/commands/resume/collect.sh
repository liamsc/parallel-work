#!/usr/bin/env bash
# Per-clone session aggregation. Calls into claude.sh and cursor.sh; emits
# one TSV row per session so the entry point can sort+slice across all
# clones in a single pass.
#
# Output format (5 fields, tab-separated):
#   <mtime>\t<clone>\t<tool>\t<session-id>\t<title>
#
# Test-only env:
#   PWORK_CLAUDE_PROJECTS_DIR overrides $HOME/.claude/projects
#   PWORK_CURSOR_PROJECTS_DIR overrides $HOME/.cursor/projects

_pwork_resume_collect_clone() {
  local clone_path="$1" clone_name="$2"
  local claude_root="${PWORK_CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
  local cursor_root="${PWORK_CURSOR_PROJECTS_DIR:-$HOME/.cursor/projects}"
  local enc f mt id title

  # Claude: one .jsonl per session, directly under the encoded dir.
  enc="$(_pwork_resume_encode_claude "$clone_path")"
  for f in "$claude_root/$enc"/*.jsonl; do
    # An unmatched glob expands to its literal pattern — guard with -f.
    [[ -f "$f" ]] || continue
    mt=$(_pwork_resume_mtime "$f")
    [[ -z "$mt" ]] && continue
    id="$(basename "$f" .jsonl)"
    title="$(_pwork_resume_title_claude "$f")"
    printf '%s\t%s\t%s\t%s\t%s\n' "$mt" "$clone_name" "claude" "$id" "$title"
  done

  # Cursor: <encoded>/agent-transcripts/<uuid>/<uuid>.jsonl
  enc="$(_pwork_resume_encode_cursor "$clone_path")"
  for f in "$cursor_root/$enc/agent-transcripts"/*/*.jsonl; do
    [[ -f "$f" ]] || continue
    mt=$(_pwork_resume_mtime "$f")
    [[ -z "$mt" ]] && continue
    # The agent-id is the parent directory name.
    id="$(basename "$(dirname "$f")")"
    title="$(_pwork_resume_title_cursor "$f")"
    printf '%s\t%s\t%s\t%s\t%s\n' "$mt" "$clone_name" "cursor" "$id" "$title"
  done
}
