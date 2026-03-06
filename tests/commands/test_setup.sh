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

test_p_setup_iterates_clones_under_zsh() {
  # command -v checks if zsh is available; skip on systems without it (e.g. Ubuntu CI)
  if ! command -v zsh &>/dev/null; then return 0; fi

  setup_test_workspace
  create_workspace 3

  # Remove settings.json to verify p-setup recreates them
  rm -f "$TEST_WORKSPACE"/p{1,2,3}/.claude/settings.json

  # Run p-setup under zsh with errreturn — the old `for clone in $clones`
  # pattern treated the entire newline-separated list as one word in zsh,
  # creating a single mangled directory instead of iterating each clone.
  local output status
  output=$(zsh -c "
    setopt errreturn
    export PWORK_INSTALL_DIR='$PWORK_INSTALL_DIR'
    source '$PWORK_INSTALL_DIR/lib/shell-helpers.sh'
    cd '$TEST_WORKSPACE/p1'
    p-setup 2>&1
  " 2>&1)
  status=$?
  assert_status_ok "$status" "p-setup succeeds under zsh errreturn" || { teardown_test_workspace; return 1; }
  assert_contains "$output" "3 clone(s)" "p-setup iterates all clones under zsh" || { teardown_test_workspace; return 1; }

  # Verify each clone got its own settings.json (not a single mangled path)
  [[ -f "$TEST_WORKSPACE/p1/.claude/settings.json" ]]
  assert_status_ok $? "p1 has settings.json after zsh p-setup" || { teardown_test_workspace; return 1; }
  [[ -f "$TEST_WORKSPACE/p2/.claude/settings.json" ]]
  assert_status_ok $? "p2 has settings.json after zsh p-setup" || { teardown_test_workspace; return 1; }
  [[ -f "$TEST_WORKSPACE/p3/.claude/settings.json" ]]
  assert_status_ok $? "p3 has settings.json after zsh p-setup" || { teardown_test_workspace; return 1; }

  teardown_test_workspace
}
