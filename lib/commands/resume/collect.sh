#!/usr/bin/env bash
# Per-clone session aggregation. Calls into claude.sh and cursor.sh; emits
# one TSV (tab-separated values) row per session so the entry point can
# sort+slice across all clones in a single pass.
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
  local encoded_dir session_file mtime session_id title

  # Claude: one .jsonl per session, directly under the encoded dir.
  encoded_dir="$(_pwork_resume_encode_claude "$clone_path")"
  for session_file in "$claude_root/$encoded_dir"/*.jsonl; do
    # Glob guard: when bash finds no matches it leaves the literal pattern
    # in $session_file (zsh has nullglob default-off too). `[[ -f X ]]` is
    # true iff X exists and is a regular file, so this skips the literal
    # pattern and any non-file entries. `|| continue` runs continue when
    # the test fails (i.e. skip this iteration).
    [[ -f "$session_file" ]] || continue
    mtime=$(_pwork_resume_mtime "$session_file")
    # `[[ -z X ]]` is true iff X is the empty string. _pwork_resume_mtime
    # returns "" on stat failure (deleted between glob and stat, perms,
    # etc.), so skip rows we can't sort by time.
    [[ -z "$mtime" ]] && continue
    session_id="$(basename "$session_file" .jsonl)"
    title="$(_pwork_resume_title_claude "$session_file")"
    printf '%s\t%s\t%s\t%s\t%s\n' "$mtime" "$clone_name" "claude" "$session_id" "$title"
  done

  # Cursor: <encoded>/agent-transcripts/<uuid>/<uuid>.jsonl
  encoded_dir="$(_pwork_resume_encode_cursor "$clone_path")"
  for session_file in "$cursor_root/$encoded_dir/agent-transcripts"/*/*.jsonl; do
    # Same two guards as the Claude loop above:
    #   -f → skip unmatched-glob literal + non-files
    #   -z → skip rows whose mtime we couldn't read
    [[ -f "$session_file" ]] || continue
    mtime=$(_pwork_resume_mtime "$session_file")
    [[ -z "$mtime" ]] && continue
    # The agent id is the parent directory name.
    session_id="$(basename "$(dirname "$session_file")")"
    title="$(_pwork_resume_title_cursor "$session_file")"
    printf '%s\t%s\t%s\t%s\t%s\n' "$mtime" "$clone_name" "cursor" "$session_id" "$title"
  done
}
