#!/usr/bin/env bash
# Tests for g-resume: cross-disk Claude/Cursor session listing for repos
# both inside and outside any parallel-work workspace.

# ── Local helpers ────────────────────────────────────────────

# Set up a fresh sandbox: redirect Claude/Cursor session storage to
# TEST_TMPDIR so tests don't read or write the user's real ~/.claude or
# ~/.cursor.
_g_resume_setup() {
  export PWORK_CLAUDE_PROJECTS_DIR="$TEST_TMPDIR/.claude-projects"
  export PWORK_CURSOR_PROJECTS_DIR="$TEST_TMPDIR/.cursor-projects"
  mkdir -p "$PWORK_CLAUDE_PROJECTS_DIR" "$PWORK_CURSOR_PROJECTS_DIR"
}

_g_resume_teardown() {
  unset PWORK_CLAUDE_PROJECTS_DIR PWORK_CURSOR_PROJECTS_DIR
}

# Seed a Claude session jsonl at an arbitrary cwd. Writes both an
# ai-title line (so the title doesn't fall back to the user message) and
# a user line carrying the cwd field — that's what
# _pwork_resume_recover_cwd_claude reads back.
_seed_claude_at_cwd() {
  local cwd="$1" sid="$2" title="$3" touch_ts="$4"
  local enc
  enc=$(_pwork_resume_encode_claude "$cwd")
  mkdir -p "$PWORK_CLAUDE_PROJECTS_DIR/$enc"
  local f="$PWORK_CLAUDE_PROJECTS_DIR/$enc/$sid.jsonl"
  {
    printf '{"type":"ai-title","aiTitle":"%s","sessionId":"%s"}\n' "$title" "$sid"
    printf '{"type":"user","cwd":"%s","message":{"role":"user","content":"hi"}}\n' "$cwd"
  } > "$f"
  [[ -n "$touch_ts" ]] && touch -t "$touch_ts" "$f"
}

# Seed a Cursor session at an arbitrary cwd. The transcript embeds an
# absolute path inside content[0].text so cursor-cwd-recovery can find it.
_seed_cursor_at_cwd() {
  local cwd="$1" sid="$2" text="$3" touch_ts="$4"
  local enc
  enc=$(_pwork_resume_encode_cursor "$cwd")
  local d="$PWORK_CURSOR_PROJECTS_DIR/$enc/agent-transcripts/$sid"
  mkdir -p "$d"
  local f="$d/$sid.jsonl"
  # Embed cwd in the text content; cursor-cwd-recovery walks up from the
  # first absolute-path match to the deepest existing directory.
  printf '{"role":"user","message":{"content":[{"type":"text","text":"%s in %s"}]}}\n' \
    "$text" "$cwd" > "$f"
  [[ -n "$touch_ts" ]] && touch -t "$touch_ts" "$f"
}

# Seed a Cursor session whose transcript contains NO absolute path — used
# to verify "(unknown)" handling.
_seed_cursor_pathless() {
  local sid="$1" text="$2" touch_ts="$3"
  # Use a fake encoded dir name that's not derivable from any real cwd.
  local d="$PWORK_CURSOR_PROJECTS_DIR/orphan-$sid/agent-transcripts/$sid"
  mkdir -p "$d"
  local f="$d/$sid.jsonl"
  printf '{"role":"user","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$text" > "$f"
  [[ -n "$touch_ts" ]] && touch -t "$touch_ts" "$f"
}

# ── Tests ────────────────────────────────────────────────────

# Description: Claude cwd recovery pulls the original working directory out of the JSONL.
test_g_resume_recover_cwd_claude_basic() {
  setup_test_workspace
  _g_resume_setup

  _seed_claude_at_cwd "/Users/test/repo-x" "abc-1" "title" "202604281000"
  local enc f recovered
  enc=$(_pwork_resume_encode_claude "/Users/test/repo-x")
  f="$PWORK_CLAUDE_PROJECTS_DIR/$enc/abc-1.jsonl"
  recovered=$(_pwork_resume_recover_cwd_claude "$f")

  assert_eq "/Users/test/repo-x" "$recovered" "Claude cwd recovered"

  _g_resume_teardown
  teardown_test_workspace
}

# Description: Claude cwd recovery returns empty when no cwd field is present.
test_g_resume_recover_cwd_claude_missing() {
  setup_test_workspace
  _g_resume_setup

  local enc f
  enc=$(_pwork_resume_encode_claude "/Users/test/repo-y")
  mkdir -p "$PWORK_CLAUDE_PROJECTS_DIR/$enc"
  f="$PWORK_CLAUDE_PROJECTS_DIR/$enc/no-cwd.jsonl"
  printf '{"type":"permission-mode","permissionMode":"plan"}\n' > "$f"

  local recovered
  recovered=$(_pwork_resume_recover_cwd_claude "$f")
  assert_eq "" "$recovered" "no-cwd jsonl returns empty"

  _g_resume_teardown
  teardown_test_workspace
}

# Description: Cursor cwd recovery walks up from a leaf path to the deepest existing directory.
test_g_resume_recover_cwd_cursor_walks_up_to_existing() {
  setup_test_workspace
  _g_resume_setup

  # Make a real directory the recovery walk should land on.
  local real_dir="$TEST_TMPDIR/cursor-recovery-target"
  mkdir -p "$real_dir"

  # Seed a transcript whose absolute path points to a *non-existent* file
  # under that directory — recovery should walk up to the existing parent.
  local d="$PWORK_CURSOR_PROJECTS_DIR/some-encoded-dir/agent-transcripts/cur-1"
  mkdir -p "$d"
  local f="$d/cur-1.jsonl"
  printf '{"role":"user","message":{"content":[{"type":"text","text":"see %s/missing-file.txt for details"}]}}\n' \
    "$real_dir" > "$f"

  local recovered
  recovered=$(_pwork_resume_recover_cwd_cursor "$f")
  assert_eq "$real_dir" "$recovered" "Cursor recovery walks up to existing dir"

  _g_resume_teardown
  teardown_test_workspace
}

# Description: Cursor cwd recovery refuses paths shallower than HOME (catches foreign-machine refs).
# When a Cursor transcript references a path from a different machine
# (e.g. /Users/test-user/... where that user doesn't exist locally) the
# walk-up lands at /Users — a real directory but useless as a workspace
# identifier. Recovery should reject anything with fewer path components
# than $HOME.
test_g_resume_recover_cwd_cursor_rejects_shallow() {
  setup_test_workspace
  _g_resume_setup

  # /Users itself exists on macOS but is shallower than HOME — recovery
  # should reject. Seed a transcript that references a deeper path under
  # a non-existent user; walk-up will land at /Users.
  local d="$PWORK_CURSOR_PROJECTS_DIR/foreign-machine/agent-transcripts/cur-foreign"
  mkdir -p "$d"
  local f="$d/cur-foreign.jsonl"
  printf '{"role":"user","message":{"content":[{"type":"text","text":"see /Users/test-user/repo/file.txt"}]}}\n' > "$f"

  local recovered
  recovered=$(_pwork_resume_recover_cwd_cursor "$f")
  assert_eq "" "$recovered" "shallow walk-up rejected"

  _g_resume_teardown
  teardown_test_workspace
}

# Description: where_label left-truncates long paths with a leading ellipsis.
test_g_resume_where_label_truncates_long_path() {
  setup_test_workspace
  _g_resume_setup

  # 50-char repo name forces truncation past the 22-char column.
  local long_path="$HOME/repos/very-long-repository-name-that-overflows"
  local label
  label=$(_pwork_resume_where_label "$long_path")

  # Truncated label should start with the ellipsis and fit in the column.
  assert_contains "$label" "…" "truncated label has ellipsis"
  if [[ ${#label} -gt 22 ]]; then
    echo "  FAIL: truncated label too long (${#label} chars): $label" >&2
    _g_resume_teardown
    teardown_test_workspace
    return 1
  fi

  _g_resume_teardown
  teardown_test_workspace
}

# Description: where_label shortens HOME-relative paths to ~/... and absolute paths stay as-is.
test_g_resume_where_label_basic_paths() {
  setup_test_workspace
  _g_resume_setup

  local label
  label=$(_pwork_resume_where_label "")
  assert_eq "(unknown)" "$label" "empty cwd → (unknown)"

  label=$(_pwork_resume_where_label "$HOME/some-repo")
  assert_eq "~/some-repo" "$label" "HOME path → ~/..."

  label=$(_pwork_resume_where_label "/opt/elsewhere")
  assert_eq "/opt/elsewhere" "$label" "non-HOME absolute path stays as-is"

  _g_resume_teardown
  teardown_test_workspace
}

# Description: g-resume lists Claude sessions from any directory on disk, even outside a workspace.
test_g_resume_lists_unregistered_dirs() {
  setup_test_workspace
  _g_resume_setup

  local repo_x="$TEST_TMPDIR/fake-repo-x"
  local repo_y="$TEST_TMPDIR/fake-repo-y"
  mkdir -p "$repo_x" "$repo_y"

  _seed_claude_at_cwd "$repo_x" "sid-x" "session in repo-x" "202604281000"
  _seed_claude_at_cwd "$repo_y" "sid-y" "session in repo-y" "202604281100"

  local output
  # cd into a directory that is NOT inside any parallel-work workspace.
  output=$(cd "$TEST_TMPDIR" && echo "" | g-resume 2>&1)

  assert_contains "$output" "session in repo-x" "repo-x session listed"
  assert_contains "$output" "session in repo-y" "repo-y session listed"

  _g_resume_teardown
  teardown_test_workspace
}

# Description: g-resume's "Where" column shows the actual path (not pN), so it stays unambiguous when multiple workspaces exist.
test_g_resume_where_column_shows_path() {
  setup_test_workspace
  create_workspace 2
  _g_resume_setup

  _seed_claude_at_cwd "$TEST_WORKSPACE/p1" "sid-p1" "session in p1" "202604281200"

  local output
  output=$(cd "$TEST_TMPDIR" && echo "" | g-resume 2>&1)

  assert_contains "$output" "session in p1" "session listed"
  assert_contains "$output" "Where" "label header shows 'Where'"
  # The label may be left-truncated for long paths, but the trailing
  # component "p1" should always be visible — that's what tells you which
  # clone of which workspace this session belongs to.
  assert_contains "$output" "p1" "trailing component visible"

  _g_resume_teardown
  teardown_test_workspace
}

# Description: g-resume shows "(unknown)" when a Cursor session has no recoverable cwd.
test_g_resume_unknown_for_pathless_cursor() {
  setup_test_workspace
  _g_resume_setup

  _seed_cursor_pathless "cur-orphan" "do something useful" "202604281000"

  local output
  output=$(cd "$TEST_TMPDIR" && echo "" | g-resume 2>&1)

  assert_contains "$output" "do something useful" "row visible"
  assert_contains "$output" "(unknown)" "(unknown) label rendered"

  _g_resume_teardown
  teardown_test_workspace
}

# Description: dispatching an (unknown)-cwd row exits non-zero with a clear error.
test_g_resume_unknown_dispatch_errors() {
  setup_test_workspace
  _g_resume_setup

  _seed_cursor_pathless "cur-orphan-2" "no-path session" "202604281000"

  local output status
  output=$(cd "$TEST_TMPDIR" && g-resume 1 2>&1)
  status=$?

  assert_status_fail "$status" "dispatch on (unknown) cwd should fail"
  assert_contains "$output" "no recoverable working directory" "shows clear error"

  _g_resume_teardown
  teardown_test_workspace
}

# Description: g-resume runs from a directory that is not inside any parallel-work workspace.
test_g_resume_works_outside_workspace() {
  setup_test_workspace
  _g_resume_setup

  local repo="$TEST_TMPDIR/lonely-repo"
  mkdir -p "$repo"
  _seed_claude_at_cwd "$repo" "lonely-sid" "outside workspace session" "202604281000"

  local output status
  # cd to a path with no .parallel-work ancestor — proves _pwork_conf is not required.
  output=$(cd "$TEST_TMPDIR" && echo "" | g-resume 2>&1)
  status=$?

  assert_status_ok "$status" "g-resume succeeds outside any workspace"
  assert_contains "$output" "outside workspace session" "session shown"

  _g_resume_teardown
  teardown_test_workspace
}

# Description: --claude flag hides Cursor rows in g-resume.
test_g_resume_claude_filter_hides_cursor() {
  setup_test_workspace
  _g_resume_setup

  local repo="$TEST_TMPDIR/mixed-repo"
  mkdir -p "$repo"
  _seed_claude_at_cwd  "$repo" "claude-sid" "claude one" "202604281200"
  _seed_cursor_at_cwd  "$repo" "cursor-sid" "cursor one" "202604281300"

  local output
  output=$(cd "$TEST_TMPDIR" && echo "" | g-resume --claude 2>&1)

  assert_contains "$output" "claude one" "claude row shown"
  assert_not_contains "$output" "cursor one" "cursor row hidden"

  _g_resume_teardown
  teardown_test_workspace
}

# Description: --limit caps g-resume rows.
test_g_resume_limit_caps_rows() {
  setup_test_workspace
  _g_resume_setup

  local repo="$TEST_TMPDIR/many-repo"
  mkdir -p "$repo"
  _seed_claude_at_cwd "$repo" "id-1" "title-1" "202604281001"
  _seed_claude_at_cwd "$repo" "id-2" "title-2" "202604281002"
  _seed_claude_at_cwd "$repo" "id-3" "title-3" "202604281003"
  _seed_claude_at_cwd "$repo" "id-4" "title-4" "202604281004"
  _seed_claude_at_cwd "$repo" "id-5" "title-5" "202604281005"

  local output
  output=$(cd "$TEST_TMPDIR" && echo "" | g-resume --limit 2 2>&1)

  assert_contains "$output"     "title-5" "newest visible"
  assert_contains "$output"     "title-4" "second visible"
  assert_not_contains "$output" "title-3" "third hidden by limit"
  assert_not_contains "$output" "title-1" "oldest hidden by limit"

  _g_resume_teardown
  teardown_test_workspace
}

# Description: g-resume numeric jump dispatches with the recovered cwd, not a workspace path.
test_g_resume_numeric_jump_uses_recovered_cwd() {
  setup_test_workspace
  _g_resume_setup

  local repo="$TEST_TMPDIR/dispatched-repo"
  mkdir -p "$repo"
  _seed_claude_at_cwd "$repo" "jump-sid" "jump session" "202604281000"

  local stub_log="$TEST_TMPDIR/stub.log"
  (
    cd "$TEST_TMPDIR"
    claude() { printf 'claude cwd=%s args=%s\n' "$PWD" "$*" >> "$stub_log"; }
    g-resume 1 >/dev/null 2>&1
  )

  local logged
  logged=$(cat "$stub_log" 2>/dev/null)

  assert_contains "$logged" "jump-sid" "session id passed"
  assert_contains "$logged" "cwd=$repo" "stub invoked from recovered cwd"

  _g_resume_teardown
  teardown_test_workspace
}

# Description: --claude and --cursor together is a usage error.
test_g_resume_claude_and_cursor_conflict() {
  setup_test_workspace
  _g_resume_setup

  local output status
  output=$(cd "$TEST_TMPDIR" && g-resume --claude --cursor 2>&1)
  status=$?

  assert_status_fail "$status" "combining --claude and --cursor should fail"
  assert_contains "$output" "mutually exclusive" "shows mutually-exclusive error"

  _g_resume_teardown
  teardown_test_workspace
}

# Description: --limit foo (non-numeric) is rejected with a usage error.
test_g_resume_invalid_limit_fails() {
  setup_test_workspace
  _g_resume_setup

  local output status
  output=$(cd "$TEST_TMPDIR" && g-resume --limit foo 2>&1)
  status=$?

  assert_status_fail "$status" "non-numeric --limit should fail"
  assert_contains "$output" "positive integer" "shows usage error for --limit"

  _g_resume_teardown
  teardown_test_workspace
}

# Description: cursor encoded-dir decode reconstructs paths via filesystem listing.
# The decoder walks each segment of the encoded name and looks at the
# actual entries in the current directory — finding the one whose name
# (after re-applying cursor's lossy encoding: drop dots, _→-) matches
# the segment. This handles hidden dirs (.foo) and underscores in one
# step without combinatorial substitution.
test_g_resume_decode_cursor_dir_recovers_real_path() {
  setup_test_workspace
  _g_resume_setup

  # Build a tree with a hidden dir and an underscore'd dir to exercise
  # both encoder lossiness modes in one round trip.
  local fake_home="$TEST_TMPDIR/fakehome"
  mkdir -p "$fake_home/.hidden_dir/sub-name"

  local real_path="$fake_home/.hidden_dir/sub-name"
  local encoded
  encoded=$(_pwork_resume_encode_cursor "$real_path")

  local result
  result=$(HOME="$fake_home" _pwork_resume_decode_cursor_dir "$encoded")
  assert_eq "$real_path" "$result" "decode reconstructs hidden + underscored path" || { _g_resume_teardown; teardown_test_workspace; return 1; }

  _g_resume_teardown
  teardown_test_workspace
}

# Description: cursor encoded-dir decode returns empty when nothing on disk matches.
test_g_resume_decode_cursor_dir_returns_empty_for_bogus() {
  setup_test_workspace
  _g_resume_setup

  local result
  result=$(_pwork_resume_decode_cursor_dir "totally-fake-nothing-real")
  assert_eq "" "$result" "bogus encoded form → empty" || { _g_resume_teardown; teardown_test_workspace; return 1; }

  _g_resume_teardown
  teardown_test_workspace
}

# Description: cursor live-pid workspace extraction pulls the cwd out of cursor-agent's argv.
# When cursor-agent is currently running, its command-line includes
# `--workspace <path>` — that's authoritative. We use it instead of
# falling through to the in-content heuristic, which can return empty
# for early-aborted transcripts.
test_g_resume_cursor_pid_workspace_extracts_path() {
  setup_test_workspace
  _g_resume_setup

  # Stub `ps` to return a fake cursor-agent argv for our test pid.
  ps() {
    case "$*" in
      "-p 999999 -o args=") echo "/usr/local/bin/cursor-agent agent --resume abc-123 --workspace /tmp/some-workspace" ;;
      *) command ps "$@" ;;
    esac
  }

  local result
  result=$(_pwork_resume_cursor_pid_workspace 999999)
  assert_eq "/tmp/some-workspace" "$result" "extracted --workspace value" || { unset -f ps; _g_resume_teardown; teardown_test_workspace; return 1; }

  unset -f ps
  _g_resume_teardown
  teardown_test_workspace
}

# Description: cursor live-pid workspace extraction returns empty when the pid is gone.
test_g_resume_cursor_pid_workspace_empty_for_dead_pid() {
  setup_test_workspace
  _g_resume_setup

  # 99999999 is reliably unallocated on macOS.
  local result
  result=$(_pwork_resume_cursor_pid_workspace 99999999)
  assert_eq "" "$result" "dead pid → empty result" || { _g_resume_teardown; teardown_test_workspace; return 1; }

  _g_resume_teardown
  teardown_test_workspace
}

# Description: cursor encoded-dir decoder runs under zsh without bash-only flags or unset-glob errors.
# Bugs caught:
#   • `read -a` is bash-only; zsh uses `-A` and errors on `-a`.
#   • Unmatched dotfile glob ("$cur"/.*) raises "no matches found"
#     under zsh's default options without `nullglob`.
test_g_resume_decode_cursor_dir_runs_under_zsh() {
  if ! command -v zsh &>/dev/null; then return 0; fi

  setup_test_workspace
  _g_resume_setup

  # Build a fake home with a hidden + underscore'd dir so the decoder
  # has to do its full lossy reverse-encoding.
  local fake_home="$TEST_TMPDIR/zshhome"
  mkdir -p "$fake_home/.hidden_repo/leaf-name"
  local real_path="$fake_home/.hidden_repo/leaf-name"
  local encoded
  encoded=$(_pwork_resume_encode_cursor "$real_path")

  local output
  output=$(zsh -c "
    export HOME='$fake_home'
    export PWORK_INSTALL_DIR='$PWORK_INSTALL_DIR'
    source '$PWORK_INSTALL_DIR/lib/shell-helpers.sh'
    _pwork_resume_decode_cursor_dir '$encoded'
  " 2>&1)

  assert_eq "$real_path" "$output" "decoder runs cleanly under zsh and recovers the path" || { _g_resume_teardown; teardown_test_workspace; return 1; }

  _g_resume_teardown
  teardown_test_workspace
}

# Description: where_label produces clean output under zsh (no typeset-echo leakage).
# Bug: zsh's `local` is `typeset`. Re-declaring a variable that's already
# local in the same function scope makes zsh echo "name=''" to stdout —
# which corrupts the function's return value when captured via $(...).
# This test runs the function under zsh and asserts the output is
# exactly the expected label with no extra lines.
test_g_resume_where_label_clean_under_zsh() {
  if ! command -v zsh &>/dev/null; then return 0; fi

  setup_test_workspace
  _g_resume_setup

  local output
  output=$(zsh -c "
    export HOME='$HOME'
    export PWORK_INSTALL_DIR='$PWORK_INSTALL_DIR'
    source '$PWORK_INSTALL_DIR/lib/shell-helpers.sh'
    _pwork_resume_where_label '$HOME/example-repo'
  " 2>&1)

  assert_eq "~/example-repo" "$output" "where_label returns just ~/path under zsh"

  _g_resume_teardown
  teardown_test_workspace
}

# Description: g-resume with no sessions reports "No sessions found" and exits non-zero.
test_g_resume_empty_when_no_sessions() {
  setup_test_workspace
  _g_resume_setup

  local output status
  output=$(cd "$TEST_TMPDIR" && g-resume 2>&1)
  status=$?

  assert_status_fail "$status" "g-resume with no sessions should fail"
  assert_contains "$output" "No sessions found" "shows empty message"

  _g_resume_teardown
  teardown_test_workspace
}
