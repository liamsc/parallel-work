#!/usr/bin/env bash
# Tests for p-clean command.

test_p_clean_requires_gh() {
  setup_test_workspace
  create_workspace 2

  local output status
  # Run in a subshell with gh shadowed to simulate it not being installed
  output=$(
    cd "$TEST_WORKSPACE/p1"
    command() {
      if [[ "$2" == "gh" ]]; then
        return 1
      fi
      builtin command "$@"
    }
    # Also shadow gh directly
    gh() { return 127; }
    export -f gh
    # Override PATH to exclude real gh
    PATH="/usr/bin:/bin"
    p-clean 2>&1
  )
  status=$?

  assert_status_fail "$status" "p-clean should fail without gh"
  assert_contains "$output" "gh CLI required" "p-clean reports gh required"

  teardown_test_workspace
}

test_p_clean_rejects_invalid_clone() {
  setup_test_workspace
  create_workspace 2

  local output status
  output=$(cd "$TEST_WORKSPACE/p1" && p-clean p99 2>&1)
  status=$?

  assert_status_fail "$status" "p-clean p99 should fail"
  assert_contains "$output" "does not exist" "p-clean reports clone does not exist"

  teardown_test_workspace
}

test_p_clean_shows_usage_on_bad_arg() {
  setup_test_workspace
  create_workspace 2

  local output status
  output=$(cd "$TEST_WORKSPACE/p1" && p-clean --invalid 2>&1)
  status=$?

  assert_status_fail "$status" "p-clean --invalid should fail"
  assert_contains "$output" "Usage" "p-clean shows usage on bad arg"

  teardown_test_workspace
}

test_p_clean_skips_default_branch() {
  setup_test_workspace
  create_workspace 2

  local output
  # Mock gh-related functions so we don't need real gh
  output=$(
    cd "$TEST_WORKSPACE/p1"
    # Pretend gh is available
    _pwork_check_gh() { return 0; }
    # Return empty merged/open lists
    _pwork_fetch_pr_branches() {
      local merged_var="$3" open_var="$4"
      eval "$merged_var=''"
      eval "$open_var=''"
    }
    # Shadow command -v gh to return success
    gh() { :; }
    p-clean 2>&1
  )

  assert_contains "$output" "No clones to recycle" "p-clean skips clones on default branch"

  teardown_test_workspace
}
