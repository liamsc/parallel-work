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
