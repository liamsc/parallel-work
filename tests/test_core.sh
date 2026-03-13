#!/usr/bin/env bash
# Tests for core workspace functions: _pwork_root, _pwork_clones, _pwork_conf.

# Description: _pwork_root returns the workspace root when called from a clone directory.
test_pwork_root_from_clone_dir() {
  setup_test_workspace
  create_workspace 2

  local result
  result=$(cd "$TEST_WORKSPACE/p1" && _pwork_root)
  assert_eq "$TEST_WORKSPACE" "$result" "_pwork_root from clone dir"

  teardown_test_workspace
}

# Description: _pwork_root walks up to the workspace root from a deeply nested subdirectory.
test_pwork_root_from_nested_subdir() {
  setup_test_workspace
  create_workspace 2

  mkdir -p "$TEST_WORKSPACE/p1/some/deep/subdir"
  local result
  result=$(cd "$TEST_WORKSPACE/p1/some/deep/subdir" && _pwork_root)
  assert_eq "$TEST_WORKSPACE" "$result" "_pwork_root from nested subdir"

  teardown_test_workspace
}

# Description: _pwork_root fails with an error when called outside any workspace.
test_pwork_root_outside_workspace() {
  setup_test_workspace

  local output status
  output=$(_pwork_root 2>&1)
  status=$?
  assert_status_fail "$status" "_pwork_root should fail outside workspace"
  assert_contains "$output" "not inside a parallel-work workspace" "_pwork_root error message"

  teardown_test_workspace
}

# Description: _pwork_root works when called directly from the workspace root.
test_pwork_root_from_workspace_root() {
  setup_test_workspace
  create_workspace 2

  local result
  result=$(cd "$TEST_WORKSPACE" && _pwork_root)
  assert_eq "$TEST_WORKSPACE" "$result" "_pwork_root from workspace root"

  teardown_test_workspace
}

# Description: _pwork_clones lists clone names in ascending numeric order.
test_pwork_clones_lists_in_order() {
  setup_test_workspace
  create_workspace 3

  local result
  result=$(cd "$TEST_WORKSPACE/p1" && _pwork_clones)
  assert_eq "p1
p2
p3" "$result" "_pwork_clones lists in numeric order"

  teardown_test_workspace
}

# Description: _pwork_clones skips missing clone numbers (e.g. p2 removed).
test_pwork_clones_handles_gaps() {
  setup_test_workspace
  create_workspace 3

  # Remove p2 to create a gap
  rm -rf "$TEST_WORKSPACE/p2"

  local result
  result=$(cd "$TEST_WORKSPACE/p1" && _pwork_clones)
  assert_eq "p1
p3" "$result" "_pwork_clones handles gaps"

  teardown_test_workspace
}

# Description: _pwork_clones sorts p10 after p3 (numeric, not lexicographic).
test_pwork_clones_numeric_sort() {
  setup_test_workspace
  create_workspace 3

  # Add p10 — should sort after p3, not between p1 and p2
  git clone "$TEST_ORIGIN" "$TEST_WORKSPACE/p10" >/dev/null 2>&1

  local result
  result=$(cd "$TEST_WORKSPACE/p1" && _pwork_clones)
  assert_contains "$result" "p10" "_pwork_clones includes p10"
  # p10 should be last
  local last
  last=$(cd "$TEST_WORKSPACE/p1" && _pwork_clones | tail -1)
  assert_eq "p10" "$last" "_pwork_clones sorts p10 after p3"

  teardown_test_workspace
}

# Description: _pwork_conf sources pwork.conf and sets PWORK_* and _PWORK_ROOT.
test_pwork_conf_sets_variables() {
  setup_test_workspace
  create_workspace 2

  (
    cd "$TEST_WORKSPACE/p1"
    _pwork_conf
    assert_eq "$TEST_ORIGIN" "$PWORK_REPO_URL" "_pwork_conf sets PWORK_REPO_URL"
    assert_eq "main" "$PWORK_DEFAULT_BRANCH" "_pwork_conf sets PWORK_DEFAULT_BRANCH"
    assert_eq "test/repo" "$PWORK_REPO_SLUG" "_pwork_conf sets PWORK_REPO_SLUG"
    assert_eq "$TEST_WORKSPACE" "$_PWORK_ROOT" "_pwork_conf sets _PWORK_ROOT"
  )

  teardown_test_workspace
}
