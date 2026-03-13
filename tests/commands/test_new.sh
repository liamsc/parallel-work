#!/usr/bin/env bash
# Tests for p-new command.

# Description: p-new creates the next sequential clone as a valid git repo.
test_p_new_creates_next_clone() {
  setup_test_workspace
  create_workspace 2

  (cd "$TEST_WORKSPACE/p1" && p-new) >/dev/null 2>&1

  [[ -d "$TEST_WORKSPACE/p3/.git" ]] || {
    echo "  FAIL: p3 was not created as a git repo" >&2
    teardown_test_workspace
    return 1
  }

  teardown_test_workspace
}

# Description: p-new picks the next number after the highest existing clone.
test_p_new_increments_number() {
  setup_test_workspace
  create_workspace 3

  (cd "$TEST_WORKSPACE/p1" && p-new) >/dev/null 2>&1

  [[ -d "$TEST_WORKSPACE/p4" ]] || {
    echo "  FAIL: p4 was not created" >&2
    teardown_test_workspace
    return 1
  }

  teardown_test_workspace
}

# Description: p-new sets up CLAUDE.local.md in the new clone.
test_p_new_creates_claude_local_md() {
  setup_test_workspace
  create_workspace 1

  (cd "$TEST_WORKSPACE/p1" && p-new) >/dev/null 2>&1

  [[ -f "$TEST_WORKSPACE/p2/.claude/CLAUDE.local.md" ]] || {
    echo "  FAIL: CLAUDE.local.md not created in p2" >&2
    teardown_test_workspace
    return 1
  }

  teardown_test_workspace
}

# Description: p-new prints a "pN is ready" message with the clone name.
test_p_new_output_shows_path() {
  setup_test_workspace
  create_workspace 1

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && p-new 2>&1)

  assert_contains "$output" "p2 is ready" "p-new output mentions p2 is ready"

  teardown_test_workspace
}
