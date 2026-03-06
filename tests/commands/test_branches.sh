#!/usr/bin/env bash
# Tests for p-branches command.

# Description: p-branches lists every clone in the workspace.
test_p_branches_shows_all_clones() {
  setup_test_workspace
  create_workspace 3

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && p-branches 2>/dev/null)

  assert_contains "$output" "p1" "p-branches shows p1"
  assert_contains "$output" "p2" "p-branches shows p2"
  assert_contains "$output" "p3" "p-branches shows p3"

  teardown_test_workspace
}

# Description: p-branches displays the current branch name for each clone.
test_p_branches_shows_branch_names() {
  setup_test_workspace
  create_workspace 3

  # Create a feature branch on p2
  (cd "$TEST_WORKSPACE/p2" && git checkout -b feature-x) >/dev/null 2>&1

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && p-branches 2>/dev/null)

  assert_contains "$output" "feature-x" "p-branches shows feature branch name"

  teardown_test_workspace
}

# Description: p-branches shows "available for new work" for clones on the default branch.
test_p_branches_default_branch_status() {
  setup_test_workspace
  create_workspace 3

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && p-branches 2>/dev/null)

  assert_contains "$output" "available for new work" "p-branches shows available status for default branch"

  teardown_test_workspace
}

# Description: p-branches shows "no PR" for feature branches without a pull request.
test_p_branches_no_pr_status() {
  setup_test_workspace
  create_workspace 3

  # Create a feature branch on p2 (no PR exists)
  (cd "$TEST_WORKSPACE/p2" && git checkout -b feature-x) >/dev/null 2>&1

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && p-branches 2>/dev/null)

  assert_contains "$output" "no PR" "p-branches shows no PR for untracked feature branch"

  teardown_test_workspace
}
