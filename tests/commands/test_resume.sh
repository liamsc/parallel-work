#!/usr/bin/env bash
# Tests for p-resume: cross-clone Claude/Cursor session listing and dispatch.

# ── Local helpers ────────────────────────────────────────────

# Override the Claude/Cursor session roots so tests don't read or write the
# user's real ~/.claude or ~/.cursor.
_resume_setup_storage() {
  export PWORK_CLAUDE_PROJECTS_DIR="$TEST_TMPDIR/.claude-projects"
  export PWORK_CURSOR_PROJECTS_DIR="$TEST_TMPDIR/.cursor-projects"
  mkdir -p "$PWORK_CLAUDE_PROJECTS_DIR" "$PWORK_CURSOR_PROJECTS_DIR"
}

_resume_teardown_storage() {
  unset PWORK_CLAUDE_PROJECTS_DIR PWORK_CURSOR_PROJECTS_DIR
}

# Seed a Claude session jsonl under the encoded path with a known ai-title and
# an explicit mtime ("touch -t" format: [[CC]YY]MMDDhhmm[.ss]) so tests can
# assert ordering deterministically.
_seed_claude_session() {
  local clone_path="$1" sid="$2" title="$3" touch_ts="$4"
  local enc
  enc=$(_pwork_resume_encode_claude "$clone_path")
  mkdir -p "$PWORK_CLAUDE_PROJECTS_DIR/$enc"
  local f="$PWORK_CLAUDE_PROJECTS_DIR/$enc/$sid.jsonl"
  printf '{"type":"ai-title","aiTitle":"%s","sessionId":"%s"}\n' "$title" "$sid" > "$f"
  [[ -n "$touch_ts" ]] && touch -t "$touch_ts" "$f"
}

# Seed a Cursor agent transcript at <encoded>/agent-transcripts/<sid>/<sid>.jsonl
# with a single user-message line (the format Cursor actually writes).
_seed_cursor_session() {
  local clone_path="$1" sid="$2" text="$3" touch_ts="$4"
  local enc
  enc=$(_pwork_resume_encode_cursor "$clone_path")
  local d="$PWORK_CURSOR_PROJECTS_DIR/$enc/agent-transcripts/$sid"
  mkdir -p "$d"
  local f="$d/$sid.jsonl"
  printf '{"role":"user","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$text" > "$f"
  [[ -n "$touch_ts" ]] && touch -t "$touch_ts" "$f"
}

# ── Tests ────────────────────────────────────────────────────

# Description: encoding helpers reproduce the exact dir names Claude and Cursor write on disk.
test_p_resume_encoding_matches_known_examples() {
  setup_test_workspace

  local got_claude got_cursor
  got_claude=$(_pwork_resume_encode_claude "/Users/me/.test_repo/proj/p1")
  got_cursor=$(_pwork_resume_encode_cursor "/Users/me/.test_repo/proj/p1")

  assert_eq "-Users-me--test-repo-proj-p1" "$got_claude" "Claude encoding"
  assert_eq "Users-me-test-repo-proj-p1" "$got_cursor" "Cursor encoding"

  teardown_test_workspace
}

# Description: p-resume fails with "No sessions found" when no sessions exist.
test_p_resume_empty_when_no_sessions() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage

  local output status
  output=$(cd "$TEST_WORKSPACE/p1" && p-resume 2>&1)
  status=$?
  assert_status_fail "$status" "p-resume should fail with no sessions"
  assert_contains "$output" "No sessions found" "p-resume shows empty message"

  _resume_teardown_storage
  teardown_test_workspace
}

# Description: a single Claude session shows up in the table with its ai-title.
test_p_resume_lists_claude_session() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage

  _seed_claude_session "$TEST_WORKSPACE/p1" "abc-123" "Add SSH key" "202604281000"

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && echo "" | p-resume 2>&1)

  assert_contains "$output" "Add SSH key" "session title appears"
  assert_contains "$output" "p1" "clone column shows p1"
  assert_contains "$output" "claude" "tool column shows claude"

  _resume_teardown_storage
  teardown_test_workspace
}

# Description: a single Cursor session shows up with its first-user-message text.
test_p_resume_lists_cursor_session() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage

  _seed_cursor_session "$TEST_WORKSPACE/p2" "cursor-uuid-1" "investigate flaky test" "202604281100"

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && echo "" | p-resume 2>&1)

  assert_contains "$output" "investigate flaky test" "cursor title appears"
  assert_contains "$output" "p2" "clone column shows p2"
  assert_contains "$output" "cursor" "tool column shows cursor"

  _resume_teardown_storage
  teardown_test_workspace
}

# Description: rows are ordered newest-first across clones (mtime-based sort).
test_p_resume_orders_newest_first() {
  setup_test_workspace
  create_workspace 3
  _resume_setup_storage

  _seed_claude_session "$TEST_WORKSPACE/p1" "id-old" "Oldest topic"  "202604280900"
  _seed_claude_session "$TEST_WORKSPACE/p2" "id-mid" "Middle topic"  "202604281000"
  _seed_claude_session "$TEST_WORKSPACE/p3" "id-new" "Newest topic"  "202604281100"

  local output pos_new pos_mid pos_old
  output=$(cd "$TEST_WORKSPACE/p1" && echo "" | p-resume 2>&1)
  # grep -n prefixes each match with line number; cut -d: takes that prefix.
  pos_new=$(echo "$output" | grep -n "Newest topic" | head -1 | cut -d: -f1)
  pos_mid=$(echo "$output" | grep -n "Middle topic" | head -1 | cut -d: -f1)
  pos_old=$(echo "$output" | grep -n "Oldest topic" | head -1 | cut -d: -f1)

  if [[ "$pos_new" -lt "$pos_mid" ]] && [[ "$pos_mid" -lt "$pos_old" ]]; then
    :
  else
    echo "  FAIL: rows not sorted newest-first (positions: new=$pos_new mid=$pos_mid old=$pos_old)" >&2
    _resume_teardown_storage
    teardown_test_workspace
    return 1
  fi

  _resume_teardown_storage
  teardown_test_workspace
}

# Description: Claude and Cursor sessions appear together in the default mixed listing.
test_p_resume_mixes_tools() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage

  _seed_claude_session "$TEST_WORKSPACE/p1" "id-claude" "Claude work" "202604281200"
  _seed_cursor_session "$TEST_WORKSPACE/p2" "id-cursor" "Cursor work" "202604281100"

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && echo "" | p-resume 2>&1)

  assert_contains "$output" "Claude work" "claude row visible"
  assert_contains "$output" "Cursor work" "cursor row visible"
  assert_contains "$output" "claude" "tool column has claude"
  assert_contains "$output" "cursor" "tool column has cursor"

  _resume_teardown_storage
  teardown_test_workspace
}

# Description: p-resume p2 filters out rows from other clones.
test_p_resume_filters_to_clone() {
  setup_test_workspace
  create_workspace 3
  _resume_setup_storage

  _seed_claude_session "$TEST_WORKSPACE/p1" "id-1" "p1 only thing" "202604281000"
  _seed_claude_session "$TEST_WORKSPACE/p2" "id-2" "p2 thing"      "202604281100"

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && echo "" | p-resume p2 2>&1)

  assert_contains "$output" "p2 thing" "p2 session shown"
  assert_not_contains "$output" "p1 only thing" "p1 session hidden"

  _resume_teardown_storage
  teardown_test_workspace
}

# Description: --claude flag hides Cursor rows.
test_p_resume_claude_flag_hides_cursor() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage

  _seed_claude_session "$TEST_WORKSPACE/p1" "id-c"   "claude-row" "202604281200"
  _seed_cursor_session "$TEST_WORKSPACE/p2" "id-cur" "cursor-row" "202604281300"

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && echo "" | p-resume --claude 2>&1)

  assert_contains "$output" "claude-row" "claude row shown"
  assert_not_contains "$output" "cursor-row" "cursor row hidden"

  _resume_teardown_storage
  teardown_test_workspace
}

# Description: --cursor flag hides Claude rows.
test_p_resume_cursor_flag_hides_claude() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage

  _seed_claude_session "$TEST_WORKSPACE/p1" "id-c"   "claude-row-2" "202604281200"
  _seed_cursor_session "$TEST_WORKSPACE/p2" "id-cur" "cursor-row-2" "202604281300"

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && echo "" | p-resume --cursor 2>&1)

  assert_contains "$output" "cursor-row-2" "cursor row shown"
  assert_not_contains "$output" "claude-row-2" "claude row hidden"

  _resume_teardown_storage
  teardown_test_workspace
}

# Description: --claude and --cursor together is a usage error.
test_p_resume_claude_and_cursor_conflict() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage

  local output status
  output=$(cd "$TEST_WORKSPACE/p1" && p-resume --claude --cursor 2>&1)
  status=$?

  assert_status_fail "$status" "combining --claude and --cursor should fail"
  assert_contains "$output" "mutually exclusive" "shows mutually-exclusive error"

  _resume_teardown_storage
  teardown_test_workspace
}

# Description: --limit caps the number of rendered rows to the newest M.
test_p_resume_limit_caps_rows() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage

  _seed_claude_session "$TEST_WORKSPACE/p1" "id-1" "title-1" "202604281001"
  _seed_claude_session "$TEST_WORKSPACE/p1" "id-2" "title-2" "202604281002"
  _seed_claude_session "$TEST_WORKSPACE/p1" "id-3" "title-3" "202604281003"
  _seed_claude_session "$TEST_WORKSPACE/p1" "id-4" "title-4" "202604281004"
  _seed_claude_session "$TEST_WORKSPACE/p1" "id-5" "title-5" "202604281005"

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && echo "" | p-resume --limit 3 2>&1)

  assert_contains "$output"     "title-5" "newest title shown"
  assert_contains "$output"     "title-4" "second newest shown"
  assert_contains "$output"     "title-3" "third newest shown"
  assert_not_contains "$output" "title-2" "fourth-newest hidden by limit"
  assert_not_contains "$output" "title-1" "oldest hidden by limit"

  _resume_teardown_storage
  teardown_test_workspace
}

# Description: numeric jump invokes the right tool with the right id from the right cwd.
test_p_resume_numeric_jump_dispatches_correctly() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage

  _seed_claude_session "$TEST_WORKSPACE/p2" "session-xyz" "Some session" "202604281200"

  local stub_log="$TEST_TMPDIR/stub.log"
  # Run inside a subshell so the stub function (and any cd) is scoped to the
  # subshell — no leak into the next test.
  (
    cd "$TEST_WORKSPACE/p1"
    claude() { printf 'claude cwd=%s args=%s\n' "$PWD" "$*" >> "$stub_log"; }
    p-resume 1 >/dev/null 2>&1
  )

  local logged
  logged=$(cat "$stub_log" 2>/dev/null)

  assert_contains "$logged" "session-xyz" "stub recorded the session id"
  assert_contains "$logged" "--dangerously-skip-permissions" "bypass-permissions flag passed"
  assert_contains "$logged" "$TEST_WORKSPACE/p2" "stub invoked from p2's cwd"

  _resume_teardown_storage
  teardown_test_workspace
}

# Description: interactive selection (echo N | p-resume) dispatches the same way as a numeric arg.
test_p_resume_interactive_selection_dispatches() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage

  _seed_claude_session "$TEST_WORKSPACE/p1" "interactive-id" "Interactive session" "202604281300"

  local stub_log="$TEST_TMPDIR/stub.log"
  (
    cd "$TEST_WORKSPACE/p1"
    claude() { printf 'claude args=%s\n' "$*" >> "$stub_log"; }
    echo "1" | p-resume >/dev/null 2>&1
  )

  local logged
  logged=$(cat "$stub_log" 2>/dev/null)

  assert_contains "$logged" "interactive-id" "interactive selection invoked correct session"

  _resume_teardown_storage
  teardown_test_workspace
}

# Description: p-resume N with N out of range fails non-zero.
test_p_resume_invalid_jump_fails() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage

  _seed_claude_session "$TEST_WORKSPACE/p1" "id-1" "the only one" "202604281000"

  local output status
  output=$(cd "$TEST_WORKSPACE/p1" && p-resume 99 2>&1)
  status=$?

  assert_status_fail "$status" "p-resume 99 should fail"
  assert_contains "$output" "invalid row" "shows invalid row error"

  _resume_teardown_storage
  teardown_test_workspace
}

# Description: when no ai-title exists, the title falls back to the first user message.
test_p_resume_falls_back_to_first_user_message() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage

  # Hand-write a Claude jsonl with only a user message — no ai-title line.
  local enc
  enc=$(_pwork_resume_encode_claude "$TEST_WORKSPACE/p1")
  mkdir -p "$PWORK_CLAUDE_PROJECTS_DIR/$enc"
  local f="$PWORK_CLAUDE_PROJECTS_DIR/$enc/no-title-id.jsonl"
  printf '{"type":"user","message":{"role":"user","content":"fallback prompt text"}}\n' > "$f"
  touch -t "202604281000" "$f"

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && echo "" | p-resume 2>&1)

  assert_contains "$output" "fallback prompt text" "first user message used as title"

  _resume_teardown_storage
  teardown_test_workspace
}

# Description: Cursor titles strip the surrounding <attached_files> wrapper and keep just the user_query.
test_p_resume_cursor_extracts_user_query() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage

  local enc
  enc=$(_pwork_resume_encode_cursor "$TEST_WORKSPACE/p1")
  local d="$PWORK_CURSOR_PROJECTS_DIR/$enc/agent-transcripts/agent-uuid"
  mkdir -p "$d"
  local f="$d/agent-uuid.jsonl"
  # Cursor's real format: content[0].text wraps a user_query alongside
  # attached_files context. We want only the user_query in the title.
  printf '%s\n' '{"role":"user","message":{"content":[{"type":"text","text":"<attached_files>\n<code_selection>some code</code_selection>\n</attached_files>\n<user_query>\nactual user prompt here\n</user_query>"}]}}' > "$f"
  touch -t "202604281200" "$f"

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && echo "" | p-resume 2>&1)

  assert_contains "$output" "actual user prompt here" "user_query extracted as title"
  assert_not_contains "$output" "code_selection" "attached_files content stripped"

  _resume_teardown_storage
  teardown_test_workspace
}

# Description: long titles are truncated with an ellipsis so the row stays one line.
test_p_resume_truncates_long_title() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage

  # Build a 100-X title — well over the 60-char cap.
  local long_title
  long_title=$(printf 'X%.0s' {1..100})
  _seed_claude_session "$TEST_WORKSPACE/p1" "long-id" "$long_title" "202604281000"

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && echo "" | p-resume 2>&1)

  assert_contains "$output" "…" "title truncated with ellipsis"

  _resume_teardown_storage
  teardown_test_workspace
}

# Description: empty interactive input (just enter) returns 0 and does not dispatch.
test_p_resume_empty_input_does_nothing() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage

  _seed_claude_session "$TEST_WORKSPACE/p1" "id-1" "thing" "202604281000"

  local stub_log="$TEST_TMPDIR/stub.log"
  local status
  (
    cd "$TEST_WORKSPACE/p1"
    claude() { printf 'claude args=%s\n' "$*" >> "$stub_log"; }
    echo "" | p-resume >/dev/null 2>&1
  )
  status=$?

  assert_status_ok "$status" "empty input returns ok"
  if [[ -s "$stub_log" ]]; then
    echo "  FAIL: claude was invoked despite empty input" >&2
    _resume_teardown_storage
    teardown_test_workspace
    return 1
  fi

  _resume_teardown_storage
  teardown_test_workspace
}

# Description: cursor row dispatches `cursor agent --resume <id> --workspace <clone-path>`.
test_p_resume_cursor_dispatch_uses_workspace_flag() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage

  _seed_cursor_session "$TEST_WORKSPACE/p2" "cur-id-1" "cursor work" "202604281200"

  local stub_log="$TEST_TMPDIR/stub.log"
  (
    cd "$TEST_WORKSPACE/p1"
    cursor() { printf 'cursor args=%s\n' "$*" >> "$stub_log"; }
    p-resume 1 >/dev/null 2>&1
  )

  local logged
  logged=$(cat "$stub_log" 2>/dev/null)

  assert_contains "$logged" "agent" "cursor agent subcommand used"
  assert_contains "$logged" "--resume cur-id-1" "session id passed"
  assert_contains "$logged" "--workspace $TEST_WORKSPACE/p2" "workspace flag set to clone path"

  _resume_teardown_storage
  teardown_test_workspace
}

# Description: p-resume runs cleanly under zsh on empty clones (catches missing nullglob).
# Bug: zsh's default option set errors on an unmatched glob ("no matches found"),
# while bash silently returns the literal pattern. Without `setopt nullglob`,
# scanning a clone with no sessions blows up under zsh.
test_p_resume_zsh_handles_empty_clones() {
  # command -v checks if zsh is available; skip on systems without it (e.g. Ubuntu CI).
  if ! command -v zsh &>/dev/null; then return 0; fi

  setup_test_workspace
  create_workspace 2
  _resume_setup_storage

  # Seed only one clone — the other clone's *.jsonl glob will be empty.
  _seed_claude_session "$TEST_WORKSPACE/p1" "id-1" "the only one" "202604281000"

  local output status
  output=$(zsh -c "
    export PWORK_INSTALL_DIR='$PWORK_INSTALL_DIR'
    export PWORK_CLAUDE_PROJECTS_DIR='$PWORK_CLAUDE_PROJECTS_DIR'
    export PWORK_CURSOR_PROJECTS_DIR='$PWORK_CURSOR_PROJECTS_DIR'
    source '$PWORK_INSTALL_DIR/lib/shell-helpers.sh'
    cd '$TEST_WORKSPACE/p1'
    echo '' | p-resume 2>&1
  " 2>&1)
  status=$?

  assert_status_ok "$status" "p-resume should succeed under zsh with empty clones" || { _resume_teardown_storage; teardown_test_workspace; return 1; }
  assert_contains "$output" "the only one" "session row visible under zsh" || { _resume_teardown_storage; teardown_test_workspace; return 1; }
  assert_not_contains "$output" "no matches found" "no zsh glob errors leaked" || { _resume_teardown_storage; teardown_test_workspace; return 1; }

  _resume_teardown_storage
  teardown_test_workspace
}

# Description: --limit foo (non-numeric) is rejected with a usage error.
test_p_resume_invalid_limit_fails() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage

  local output status
  output=$(cd "$TEST_WORKSPACE/p1" && p-resume --limit foo 2>&1)
  status=$?

  assert_status_fail "$status" "non-numeric --limit should fail"
  assert_contains "$output" "positive integer" "shows usage error for --limit"

  _resume_teardown_storage
  teardown_test_workspace
}
