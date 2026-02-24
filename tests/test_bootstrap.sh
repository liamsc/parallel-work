#!/usr/bin/env bash
# Tests for bootstrap_workspace and clone failure handling.

test_bootstrap_creates_clones() {
  setup_test_workspace
  create_workspace 3

  [[ -d "$TEST_WORKSPACE/p1" ]] && [[ -d "$TEST_WORKSPACE/p2" ]] && [[ -d "$TEST_WORKSPACE/p3" ]]
  assert_status_ok $? "bootstrap creates 3 clone directories"

  teardown_test_workspace
}

test_bootstrap_clones_are_git_repos() {
  setup_test_workspace
  create_workspace 2

  [[ -d "$TEST_WORKSPACE/p1/.git" ]] && [[ -d "$TEST_WORKSPACE/p2/.git" ]]
  assert_status_ok $? "bootstrap clones are git repos"

  teardown_test_workspace
}

test_bootstrap_creates_claude_local_md() {
  setup_test_workspace
  create_workspace 2

  [[ -f "$TEST_WORKSPACE/p1/.claude/CLAUDE.local.md" ]]
  assert_status_ok $? "bootstrap creates CLAUDE.local.md"

  local content
  content=$(cat "$TEST_WORKSPACE/p1/.claude/CLAUDE.local.md")
  assert_contains "$content" "Clone: p1" "CLAUDE.local.md contains clone name"

  teardown_test_workspace
}

test_bootstrap_adds_git_exclude() {
  setup_test_workspace
  create_workspace 2

  local exclude_content
  exclude_content=$(cat "$TEST_WORKSPACE/p1/.git/info/exclude")
  assert_contains "$exclude_content" "CLAUDE.local.md" "git exclude contains CLAUDE.local.md"

  teardown_test_workspace
}

test_bootstrap_skips_existing() {
  setup_test_workspace
  create_workspace 2

  # Create a marker file in p1
  echo "marker" > "$TEST_WORKSPACE/p1/marker.txt"

  # Run bootstrap again
  source "$TEST_WORKSPACE/.parallel-work/pwork.conf"
  WORKSPACE_ROOT="$TEST_WORKSPACE"
  source "$PWORK_INSTALL_DIR/lib/bootstrap.sh"
  bootstrap_workspace >/dev/null 2>&1

  # Marker should still be there (clone wasn't overwritten)
  [[ -f "$TEST_WORKSPACE/p1/marker.txt" ]]
  assert_status_ok $? "bootstrap skips existing clones"

  teardown_test_workspace
}

test_bootstrap_progress_counters() {
  setup_test_workspace
  mkdir -p "$TEST_WORKSPACE/.parallel-work"

  cat > "$TEST_WORKSPACE/.parallel-work/pwork.conf" <<EOF
PWORK_REPO_URL="$TEST_ORIGIN"
PWORK_REPO_SLUG="test/repo"
PWORK_CLONE_COUNT=3
PWORK_DEFAULT_BRANCH="main"
PWORK_SYNC_CMD=""
PWORK_SHARED_FILES=()
EOF

  source "$TEST_WORKSPACE/.parallel-work/pwork.conf"
  WORKSPACE_ROOT="$TEST_WORKSPACE"
  source "$PWORK_INSTALL_DIR/lib/bootstrap.sh"

  local output
  output=$(bootstrap_workspace 2>&1)
  assert_contains "$output" "[1/3]" "bootstrap shows progress counter [1/3]"
  assert_contains "$output" "[3/3]" "bootstrap shows progress counter [3/3]"

  teardown_test_workspace
}

test_clone_failure_caught_in_bootstrap() {
  setup_test_workspace
  mkdir -p "$TEST_WORKSPACE/.parallel-work"

  cat > "$TEST_WORKSPACE/.parallel-work/pwork.conf" <<EOF
PWORK_REPO_URL="file:///nonexistent/repo.git"
PWORK_REPO_SLUG="test/repo"
PWORK_CLONE_COUNT=1
PWORK_DEFAULT_BRANCH="main"
PWORK_SYNC_CMD=""
PWORK_SHARED_FILES=()
EOF

  source "$TEST_WORKSPACE/.parallel-work/pwork.conf"
  WORKSPACE_ROOT="$TEST_WORKSPACE"
  source "$PWORK_INSTALL_DIR/lib/bootstrap.sh"

  local output status
  output=$(bootstrap_workspace 2>&1)
  status=$?
  assert_status_fail "$status" "bootstrap should fail on bad repo URL"
  assert_contains "$output" "git clone failed" "bootstrap shows clone failure message"

  teardown_test_workspace
}
