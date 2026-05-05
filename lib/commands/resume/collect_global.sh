#!/usr/bin/env bash
# Global session aggregator — enumerates every Claude/Cursor session on
# disk regardless of workspace and emits one TSV (tab-separated values)
# row per session. The companion of collect.sh's _pwork_resume_collect_clone:
# same output shape, different input strategy.
#
# Output format (6 fields, tab-separated):
#   <mtime>\t<where_label>\t<tool>\t<session-id>\t<title>\t<cwd>
#
# Test-only env:
#   PWORK_CLAUDE_PROJECTS_DIR overrides $HOME/.claude/projects
#   PWORK_CURSOR_PROJECTS_DIR overrides $HOME/.cursor/projects

_pwork_resume_collect_global() {
  local claude_root="${PWORK_CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
  local cursor_root="${PWORK_CURSOR_PROJECTS_DIR:-$HOME/.cursor/projects}"
  local encoded_dir session_file mtime session_id title cwd label

  # Live Claude metadata gives us authoritative cwds — useful when the
  # user moved a session mid-run and the JSONL still has the old header.
  # Held as a TSV (tab-separated values) string and looked up per row via
  # awk; portable across bash and zsh without associative arrays.
  local live_data
  live_data=$(_pwork_jump_live_claude_sessions 2>/dev/null)

  # Claude: every dir under projects/ is one workspace path; *.jsonl files
  # directly under it are the sessions.
  if [[ -d "$claude_root" ]]; then
    for encoded_dir in "$claude_root"/*; do
      [[ -d "$encoded_dir" ]] || continue
      for session_file in "$encoded_dir"/*.jsonl; do
        [[ -f "$session_file" ]] || continue
        mtime=$(_pwork_resume_mtime "$session_file")
        [[ -z "$mtime" ]] && continue
        session_id="$(basename "$session_file" .jsonl)"
        title="$(_pwork_resume_title_claude "$session_file")"
        # Prefer live metadata cwd when available — it's authoritative.
        cwd=""
        if [[ -n "$live_data" ]]; then
          cwd=$(printf '%s\n' "$live_data" \
                  | awk -F'\t' -v s="$session_id" '$1==s {print $3; exit}')
        fi
        [[ -z "$cwd" ]] && cwd="$(_pwork_resume_recover_cwd_claude "$session_file")"
        label="$(_pwork_resume_where_label "$cwd")"
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
          "$mtime" "$label" "claude" "$session_id" "$title" "$cwd"
      done
    done
  fi

  # Cursor: <encoded>/agent-transcripts/<uuid>/<uuid>.jsonl
  if [[ -d "$cursor_root" ]]; then
    local live_pid encoded_basename
    for encoded_dir in "$cursor_root"/*; do
      [[ -d "$encoded_dir/agent-transcripts" ]] || continue
      encoded_basename="$(basename "$encoded_dir")"
      for session_file in "$encoded_dir/agent-transcripts"/*/*.jsonl; do
        [[ -f "$session_file" ]] || continue
        mtime=$(_pwork_resume_mtime "$session_file")
        [[ -z "$mtime" ]] && continue
        session_id="$(basename "$(dirname "$session_file")")"
        title="$(_pwork_resume_title_cursor "$session_file")"
        # Recovery order, most → least authoritative:
        #   1. Live cursor-agent's --workspace argv (running process)
        #   2. Greedy decode of the encoded dirname against the filesystem
        #   3. Absolute path appearing in transcript content (heuristic)
        cwd=""
        live_pid=$(_pwork_jump_live_cursor_pid "$session_id")
        if [[ -n "$live_pid" ]]; then
          cwd=$(_pwork_resume_cursor_pid_workspace "$live_pid")
        fi
        [[ -z "$cwd" ]] && cwd="$(_pwork_resume_decode_cursor_dir "$encoded_basename")"
        [[ -z "$cwd" ]] && cwd="$(_pwork_resume_recover_cwd_cursor "$session_file")"
        label="$(_pwork_resume_where_label "$cwd")"
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
          "$mtime" "$label" "cursor" "$session_id" "$title" "$cwd"
      done
    done
  fi
}
