#!/usr/bin/env bash
# Tests for p-setup — apply statusline/clone config to existing clones.

test_p_setup_creates_settings_json() {
  setup_test_workspace
  create_workspace 2

  # Remove settings.json to simulate pre-existing clones without setup
  rm -f "$TEST_WORKSPACE/p1/.claude/settings.json"
  rm -f "$TEST_WORKSPACE/p2/.claude/settings.json"

  (cd "$TEST_WORKSPACE/p1" && p-setup) >/dev/null 2>&1

  [[ -f "$TEST_WORKSPACE/p1/.claude/settings.json" ]]
  assert_status_ok $? "p-setup creates settings.json on p1"

  [[ -f "$TEST_WORKSPACE/p2/.claude/settings.json" ]]
  assert_status_ok $? "p-setup creates settings.json on p2"

  teardown_test_workspace
}

test_p_setup_creates_claude_local_md() {
  setup_test_workspace
  create_workspace 2

  # Remove CLAUDE.local.md to simulate pre-existing clones
  rm -f "$TEST_WORKSPACE/p1/.claude/CLAUDE.local.md"

  (cd "$TEST_WORKSPACE/p1" && p-setup) >/dev/null 2>&1

  [[ -f "$TEST_WORKSPACE/p1/.claude/CLAUDE.local.md" ]]
  assert_status_ok $? "p-setup creates CLAUDE.local.md"

  local content
  content=$(cat "$TEST_WORKSPACE/p1/.claude/CLAUDE.local.md")
  assert_contains "$content" "Clone: p1" "CLAUDE.local.md contains clone name"

  teardown_test_workspace
}

test_p_setup_preserves_existing_files() {
  setup_test_workspace
  create_workspace 1

  # Write custom content to CLAUDE.local.md
  echo "# Custom content" > "$TEST_WORKSPACE/p1/.claude/CLAUDE.local.md"

  (cd "$TEST_WORKSPACE/p1" && p-setup) >/dev/null 2>&1

  local content
  content=$(cat "$TEST_WORKSPACE/p1/.claude/CLAUDE.local.md")
  assert_contains "$content" "Custom content" "p-setup preserves existing CLAUDE.local.md"

  teardown_test_workspace
}

test_p_setup_shows_clone_count() {
  setup_test_workspace
  create_workspace 3

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && p-setup 2>&1)

  assert_contains "$output" "3 clone(s)" "p-setup shows correct clone count"

  teardown_test_workspace
}

test_p_setup_fails_outside_workspace() {
  local output status
  output=$(cd /tmp && p-setup 2>&1)
  status=$?

  assert_status_fail "$status" "p-setup fails outside a workspace"

  teardown_test_workspace
}
