#!/usr/bin/env bash
# Tests for p-status dirty/clean detection.

# Description: p-status reports a fresh clone as "clean".
test_p_status_clean_clone() {
  setup_test_workspace
  create_workspace 1

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && p-status 2>&1)
  assert_contains "$output" "clean" "fresh clone should be clean"

  teardown_test_workspace
}

# Description: p-status reports "dirty" when a tracked file has unstaged changes.
test_p_status_dirty_unstaged_changes() {
  setup_test_workspace
  create_workspace 1

  # Modify a tracked file without staging
  echo "change" >> "$TEST_WORKSPACE/p1/README.md" 2>/dev/null || \
    echo "change" > "$TEST_WORKSPACE/p1/somefile.txt" && \
    (cd "$TEST_WORKSPACE/p1" && git add somefile.txt && git commit -m "add file" >/dev/null 2>&1 && echo "edit" >> somefile.txt)

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && p-status 2>&1)
  assert_contains "$output" "dirty" "unstaged changes should be dirty"

  teardown_test_workspace
}

# Description: p-status reports "dirty" when there are staged but uncommitted changes.
test_p_status_dirty_staged_changes() {
  setup_test_workspace
  create_workspace 1

  # Create and stage a file without committing
  echo "new" > "$TEST_WORKSPACE/p1/staged.txt"
  (cd "$TEST_WORKSPACE/p1" && git add staged.txt)

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && p-status 2>&1)
  assert_contains "$output" "dirty" "staged changes should be dirty"

  teardown_test_workspace
}

# Description: p-status reports "dirty" when there are untracked files.
test_p_status_dirty_untracked_file() {
  setup_test_workspace
  create_workspace 1

  # Create an untracked file (not git-added)
  echo "untracked" > "$TEST_WORKSPACE/p1/newfile.txt"

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && p-status 2>&1)
  assert_contains "$output" "dirty" "untracked file should be dirty"

  teardown_test_workspace
}

# Description: p-status reports "clean" when the only new files match .gitignore.
test_p_status_ignores_gitignored_files() {
  setup_test_workspace
  create_workspace 1

  # Add a .gitignore and commit it, then create an ignored file
  (
    cd "$TEST_WORKSPACE/p1"
    echo "*.log" > .gitignore
    git add .gitignore
    git commit -m "add gitignore" >/dev/null 2>&1
  )
  echo "log data" > "$TEST_WORKSPACE/p1/debug.log"

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && p-status 2>&1)
  assert_contains "$output" "clean" "gitignored file should not make clone dirty"

  teardown_test_workspace
}
