#!/usr/bin/env bash
# Tests for pw command: workspace listing, jumping, and registry management.

test_pw_no_registry_shows_error() {
  setup_test_workspace
  _PWORK_REGISTRY="$TEST_TMPDIR/no-such-file"

  local output status
  output=$(pw 2>&1)
  status=$?
  assert_status_fail "$status" "pw with no registry should fail"
  assert_contains "$output" "No workspaces registered" "pw shows error message"

  teardown_test_workspace
}

test_pw_lists_registered_workspace() {
  setup_test_workspace
  create_workspace 3
  _PWORK_REGISTRY="$TEST_TMPDIR/workspaces"

  _pwork_register "$TEST_WORKSPACE"

  local output
  # Pipe empty input so the interactive prompt doesn't block
  output=$(echo "" | pw)
  assert_contains "$output" "repo" "pw shows project name"
  assert_contains "$output" "$TEST_WORKSPACE" "pw shows workspace path"
  assert_contains "$output" "3" "pw shows clone count"

  teardown_test_workspace
}

test_pw_n_changes_to_workspace_root() {
  setup_test_workspace
  create_workspace 2
  _PWORK_REGISTRY="$TEST_TMPDIR/workspaces"

  _pwork_register "$TEST_WORKSPACE"

  (
    cd /tmp
    pw 1
    assert_eq "$TEST_WORKSPACE" "$PWD" "pw 1 changes to workspace root"
  )

  teardown_test_workspace
}

test_pw_n_invalid_number_fails() {
  setup_test_workspace
  create_workspace 2
  _PWORK_REGISTRY="$TEST_TMPDIR/workspaces"

  _pwork_register "$TEST_WORKSPACE"

  local output status
  output=$(pw 99 2>&1)
  status=$?
  assert_status_fail "$status" "pw 99 should fail"
  assert_contains "$output" "invalid workspace number" "pw 99 error message"

  teardown_test_workspace
}

test_pw_prunes_stale_entries() {
  setup_test_workspace
  create_workspace 2
  _PWORK_REGISTRY="$TEST_TMPDIR/workspaces"

  # Register a real workspace and a stale (nonexistent) one
  echo "/tmp/nonexistent-workspace" > "$_PWORK_REGISTRY"
  _pwork_register "$TEST_WORKSPACE"

  local output
  output=$(echo "" | pw)
  assert_not_contains "$output" "nonexistent-workspace" "stale entry not shown"
  assert_contains "$output" "$TEST_WORKSPACE" "valid entry still shown"

  # Registry file should no longer contain the stale entry
  local registry_contents
  registry_contents=$(cat "$_PWORK_REGISTRY")
  assert_not_contains "$registry_contents" "nonexistent-workspace" "stale entry pruned from file"

  teardown_test_workspace
}

test_pw_add_registers_workspace() {
  setup_test_workspace
  create_workspace 2
  _PWORK_REGISTRY="$TEST_TMPDIR/workspaces"

  local output status
  output=$(pw --add "$TEST_WORKSPACE" 2>&1)
  status=$?
  assert_status_ok "$status" "pw --add should succeed"
  assert_contains "$output" "Registered" "pw --add confirms registration"

  output=$(echo "" | pw)
  assert_contains "$output" "$TEST_WORKSPACE" "registered workspace appears in list"

  teardown_test_workspace
}

test_pw_add_rejects_non_workspace() {
  setup_test_workspace
  _PWORK_REGISTRY="$TEST_TMPDIR/workspaces"

  local output status
  output=$(pw --add /tmp 2>&1)
  status=$?
  assert_status_fail "$status" "pw --add /tmp should fail"
  assert_contains "$output" "not a parallel-work workspace" "pw --add rejects non-workspace"

  teardown_test_workspace
}

test_pw_register_is_idempotent() {
  setup_test_workspace
  create_workspace 2
  _PWORK_REGISTRY="$TEST_TMPDIR/workspaces"

  _pwork_register "$TEST_WORKSPACE"
  _pwork_register "$TEST_WORKSPACE"
  _pwork_register "$TEST_WORKSPACE"

  local count
  count=$(grep -c "$TEST_WORKSPACE" "$_PWORK_REGISTRY")
  assert_eq "1" "$count" "workspace registered only once"

  teardown_test_workspace
}

test_pw_interactive_selection_jumps_to_workspace() {
  setup_test_workspace
  create_workspace 2
  _PWORK_REGISTRY="$TEST_TMPDIR/workspaces"

  _pwork_register "$TEST_WORKSPACE"

  # Pipe "1" as interactive input — pw should cd to the first workspace
  (
    cd /tmp
    echo "1" | pw
    assert_eq "$TEST_WORKSPACE" "$PWD" "pw interactive selection jumps to workspace"
  )

  teardown_test_workspace
}

test_pw_interactive_empty_input_stays_put() {
  setup_test_workspace
  create_workspace 2
  _PWORK_REGISTRY="$TEST_TMPDIR/workspaces"

  _pwork_register "$TEST_WORKSPACE"

  local status
  # Empty input (just enter) — pw should succeed and not change directory
  (
    cd /tmp
    echo "" | pw
    status=$?
    assert_status_ok "$status" "pw with empty input should succeed"
    assert_eq "/private/tmp" "$PWD" "pw with empty input stays put"
  )

  teardown_test_workspace
}

test_pw_interactive_invalid_input_fails() {
  setup_test_workspace
  create_workspace 2
  _PWORK_REGISTRY="$TEST_TMPDIR/workspaces"

  _pwork_register "$TEST_WORKSPACE"

  local output status
  output=$(echo "99" | pw 2>&1)
  status=$?
  assert_status_fail "$status" "pw with invalid choice should fail"
  assert_contains "$output" "Invalid choice" "pw shows invalid choice error"

  teardown_test_workspace
}

# ── Multi-workspace tests ─────────────────────────────────────

# Create a second workspace alongside the first for multi-workspace tests.
# Call after setup_test_workspace + create_workspace. Sets TEST_WORKSPACE_2.
_setup_second_workspace() {
  TEST_ORIGIN_2="$TEST_TMPDIR/origin2.git"
  git init --bare -b main "$TEST_ORIGIN_2" >/dev/null 2>&1
  local seed="$TEST_TMPDIR/seed2"
  git clone "$TEST_ORIGIN_2" "$seed" >/dev/null 2>&1
  (
    cd "$seed"
    git config user.email "test@test.com"
    git config user.name "Test"
    git commit --allow-empty -m "init" >/dev/null 2>&1
    git push >/dev/null 2>&1
  )
  rm -rf "$seed"

  TEST_WORKSPACE_2="$TEST_TMPDIR/workspace2"
  mkdir -p "$TEST_WORKSPACE_2/.parallel-work"
  cat > "$TEST_WORKSPACE_2/.parallel-work/pwork.conf" <<EOF
PWORK_REPO_URL="$TEST_ORIGIN_2"
PWORK_REPO_SLUG="test/repo2"
PWORK_CLONE_COUNT=2
PWORK_DEFAULT_BRANCH="main"
PWORK_SYNC_CMD=""
PWORK_SHARED_FILES=()
EOF

  local saved_root="$WORKSPACE_ROOT"
  source "$TEST_WORKSPACE_2/.parallel-work/pwork.conf"
  WORKSPACE_ROOT="$TEST_WORKSPACE_2"
  source "$PWORK_INSTALL_DIR/lib/bootstrap.sh"
  bootstrap_workspace >/dev/null 2>&1
  WORKSPACE_ROOT="$saved_root"
}

test_pw_lists_two_workspaces() {
  setup_test_workspace
  create_workspace 2
  _PWORK_REGISTRY="$TEST_TMPDIR/workspaces"
  _setup_second_workspace

  _pwork_register "$TEST_WORKSPACE"
  _pwork_register "$TEST_WORKSPACE_2"

  local output
  output=$(echo "" | pw)
  assert_contains "$output" "$TEST_WORKSPACE" "first workspace appears in list"
  assert_contains "$output" "$TEST_WORKSPACE_2" "second workspace appears in list"

  teardown_test_workspace
}

test_pw_n_jumps_to_first_of_two_workspaces() {
  setup_test_workspace
  create_workspace 2
  _PWORK_REGISTRY="$TEST_TMPDIR/workspaces"
  _setup_second_workspace

  _pwork_register "$TEST_WORKSPACE"
  _pwork_register "$TEST_WORKSPACE_2"

  (
    cd /tmp
    pw 1
    assert_eq "$TEST_WORKSPACE" "$PWD" "pw 1 jumps to first workspace"
  )

  teardown_test_workspace
}

test_pw_n_jumps_to_second_of_two_workspaces() {
  setup_test_workspace
  create_workspace 2
  _PWORK_REGISTRY="$TEST_TMPDIR/workspaces"
  _setup_second_workspace

  _pwork_register "$TEST_WORKSPACE"
  _pwork_register "$TEST_WORKSPACE_2"

  (
    cd /tmp
    pw 2
    assert_eq "$TEST_WORKSPACE_2" "$PWD" "pw 2 jumps to second workspace"
  )

  teardown_test_workspace
}

test_pw_interactive_selects_second_of_two_workspaces() {
  setup_test_workspace
  create_workspace 2
  _PWORK_REGISTRY="$TEST_TMPDIR/workspaces"
  _setup_second_workspace

  _pwork_register "$TEST_WORKSPACE"
  _pwork_register "$TEST_WORKSPACE_2"

  (
    cd /tmp
    echo "2" | pw
    assert_eq "$TEST_WORKSPACE_2" "$PWD" "interactive selection 2 jumps to second workspace"
  )

  teardown_test_workspace
}

test_pw_invalid_number_with_two_workspaces() {
  setup_test_workspace
  create_workspace 2
  _PWORK_REGISTRY="$TEST_TMPDIR/workspaces"
  _setup_second_workspace

  _pwork_register "$TEST_WORKSPACE"
  _pwork_register "$TEST_WORKSPACE_2"

  local output status
  output=$(pw 3 2>&1)
  status=$?
  assert_status_fail "$status" "pw 3 should fail with only 2 workspaces"
  assert_contains "$output" "invalid workspace number" "pw 3 shows error"

  teardown_test_workspace
}

test_pw_list_workspaces_returns_both_paths() {
  setup_test_workspace
  create_workspace 2
  _PWORK_REGISTRY="$TEST_TMPDIR/workspaces"
  _setup_second_workspace

  _pwork_register "$TEST_WORKSPACE"
  _pwork_register "$TEST_WORKSPACE_2"

  local output line_count
  output=$(_pwork_list_workspaces)
  # wc -l counts lines; tr -d ' ' strips whitespace padding
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  assert_eq "2" "$line_count" "_pwork_list_workspaces returns exactly 2 lines"
  assert_contains "$output" "$TEST_WORKSPACE" "first workspace in list output"
  assert_contains "$output" "$TEST_WORKSPACE_2" "second workspace in list output"

  teardown_test_workspace
}

test_pw_registry_intact_after_listing_two_workspaces() {
  setup_test_workspace
  create_workspace 2
  _PWORK_REGISTRY="$TEST_TMPDIR/workspaces"
  _setup_second_workspace

  _pwork_register "$TEST_WORKSPACE"
  _pwork_register "$TEST_WORKSPACE_2"

  # Call pw twice — registry should remain intact after pruning/rewrite
  echo "" | pw >/dev/null 2>&1
  echo "" | pw >/dev/null 2>&1

  local reg_count
  # grep -c counts matching lines
  reg_count=$(grep -c '.' "$_PWORK_REGISTRY")
  assert_eq "2" "$reg_count" "registry still has 2 entries after repeated pw calls"

  teardown_test_workspace
}

test_pw_shows_correct_clone_counts_for_two_workspaces() {
  setup_test_workspace
  create_workspace 3
  _PWORK_REGISTRY="$TEST_TMPDIR/workspaces"
  _setup_second_workspace

  _pwork_register "$TEST_WORKSPACE"
  _pwork_register "$TEST_WORKSPACE_2"

  local output
  output=$(echo "" | pw)

  # First workspace has 3 clones, second has 2 (set in _setup_second_workspace)
  # Extract the line for each workspace and check its clone count
  local line1 line2
  line1=$(echo "$output" | grep "$TEST_WORKSPACE" | grep -v "$TEST_WORKSPACE_2")
  line2=$(echo "$output" | grep "$TEST_WORKSPACE_2")
  assert_contains "$line1" "3" "first workspace shows 3 clones"
  assert_contains "$line2" "2" "second workspace shows 2 clones"

  teardown_test_workspace
}

test_pw_shows_distinct_names_for_two_workspaces() {
  setup_test_workspace
  create_workspace 2
  _PWORK_REGISTRY="$TEST_TMPDIR/workspaces"
  _setup_second_workspace

  _pwork_register "$TEST_WORKSPACE"
  _pwork_register "$TEST_WORKSPACE_2"

  local output
  output=$(echo "" | pw)
  assert_contains "$output" "repo" "first workspace name (repo) appears"
  assert_contains "$output" "repo2" "second workspace name (repo2) appears"

  teardown_test_workspace
}

test_pw_listing_survives_errexit() {
  # command -v checks if zsh is available; skip on systems without it (e.g. Ubuntu CI)
  if ! command -v zsh &>/dev/null; then return 0; fi

  setup_test_workspace
  create_workspace 2
  _PWORK_REGISTRY="$TEST_TMPDIR/workspaces"
  _setup_second_workspace

  _pwork_register "$TEST_WORKSPACE"
  _pwork_register "$TEST_WORKSPACE_2"

  # pw must work when zsh's errreturn is active in the caller.
  # Bug: (( i++ )) when i=0 evaluates to 0 (arithmetic false), returning
  # exit code 1. Bash's set -e ignores this, but zsh's errreturn aborts
  # the function — so pw prints the header but no workspace rows.
  # || return 1 needed because test runner uses set +e, so assertion
  # failures don't stop the function — teardown would mask the failure.
  local output status
  output=$(zsh -c "
    setopt errreturn
    export PWORK_INSTALL_DIR='$PWORK_INSTALL_DIR'
    source '$PWORK_INSTALL_DIR/lib/shell-helpers.sh'
    _PWORK_REGISTRY='$_PWORK_REGISTRY'
    echo '' | pw
  " 2>&1)
  status=$?
  assert_status_ok "$status" "pw listing should succeed under zsh errreturn" || { teardown_test_workspace; return 1; }
  assert_contains "$output" "$TEST_WORKSPACE" "first workspace visible under zsh errreturn" || { teardown_test_workspace; return 1; }
  assert_contains "$output" "$TEST_WORKSPACE_2" "second workspace visible under zsh errreturn" || { teardown_test_workspace; return 1; }

  teardown_test_workspace
}

test_pw_n_jump_survives_errexit() {
  # command -v checks if zsh is available; skip on systems without it (e.g. Ubuntu CI)
  if ! command -v zsh &>/dev/null; then return 0; fi

  setup_test_workspace
  create_workspace 2
  _PWORK_REGISTRY="$TEST_TMPDIR/workspaces"

  _pwork_register "$TEST_WORKSPACE"

  local output status
  output=$(zsh -c "
    setopt errreturn
    export PWORK_INSTALL_DIR='$PWORK_INSTALL_DIR'
    source '$PWORK_INSTALL_DIR/lib/shell-helpers.sh'
    _PWORK_REGISTRY='$_PWORK_REGISTRY'
    pw 1 2>&1
    echo \"PWD=\$PWD\"
  " 2>&1)
  status=$?
  assert_status_ok "$status" "pw 1 should succeed under zsh errreturn" || { teardown_test_workspace; return 1; }
  assert_contains "$output" "$TEST_WORKSPACE" "pw 1 changes to workspace under zsh errreturn" || { teardown_test_workspace; return 1; }

  teardown_test_workspace
}
