#!/usr/bin/env bash
# Tests for p1–pN quick-cd commands.

test_p_changes_directory() {
  setup_test_workspace
  create_workspace 3

  (
    cd "$TEST_WORKSPACE/p1"
    p2
    assert_eq "$TEST_WORKSPACE/p2" "$PWD" "p2 changes to p2"
  )

  teardown_test_workspace
}

test_p_fails_for_nonexistent() {
  setup_test_workspace
  create_workspace 2

  local output status
  output=$(cd "$TEST_WORKSPACE/p1" && p99 2>&1)
  status=$?
  assert_status_fail "$status" "p99 should fail"
  assert_contains "$output" "does not exist" "p99 error message"

  teardown_test_workspace
}
