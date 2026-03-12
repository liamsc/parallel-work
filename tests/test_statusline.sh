#!/usr/bin/env bash
# Tests for statusline setup during clone bootstrap.

# Description: bootstrap creates .claude/settings.local.json with statusLine config.
test_bootstrap_creates_statusline_settings() {
  setup_test_workspace
  create_workspace 2

  [[ -f "$TEST_WORKSPACE/p1/.claude/settings.local.json" ]]
  assert_status_ok $? "bootstrap creates .claude/settings.local.json"

  local content
  content=$(cat "$TEST_WORKSPACE/p1/.claude/settings.local.json")
  assert_contains "$content" '"statusLine"' "settings.local.json contains statusLine"
  assert_contains "$content" 'statusline.sh' "settings.local.json points to statusline.sh"

  teardown_test_workspace
}

# Description: bootstrap adds .claude/settings.local.json to git's local exclude.
test_bootstrap_excludes_settings_json() {
  setup_test_workspace
  create_workspace 2

  local exclude_content
  exclude_content=$(cat "$TEST_WORKSPACE/p1/.git/info/exclude")
  assert_contains "$exclude_content" ".claude/settings.local.json" "git exclude contains settings.local.json"

  teardown_test_workspace
}

# Description: re-running clone setup merges statusLine into existing settings
# without removing other keys.
test_statusline_settings_merged_into_existing() {
  # jq is required for the merge path; skip if unavailable.
  # command -v checks if a command exists on the system.
  if ! command -v jq &>/dev/null; then return 0; fi

  setup_test_workspace
  create_workspace 2

  # Write custom content without statusLine
  echo '{"custom": true}' > "$TEST_WORKSPACE/p1/.claude/settings.local.json"

  # Re-run setup — should merge statusLine in
  source "$PWORK_INSTALL_DIR/lib/clone-setup.sh"
  _pwork_setup_clone "p1" "$TEST_WORKSPACE/p1" "$TEST_WORKSPACE"

  local content
  content=$(cat "$TEST_WORKSPACE/p1/.claude/settings.local.json")
  assert_contains "$content" '"custom"' "existing keys preserved after merge"
  assert_contains "$content" '"statusLine"' "statusLine merged into existing file"

  teardown_test_workspace
}

# Description: re-running clone setup does not overwrite an existing statusLine.
test_statusline_settings_not_overwritten() {
  setup_test_workspace
  create_workspace 2

  # Write a file that already has a statusLine — setup should leave it alone.
  echo '{"statusLine": {"type": "command", "command": "/custom/path"}}' \
    > "$TEST_WORKSPACE/p1/.claude/settings.local.json"

  # Re-run setup
  source "$PWORK_INSTALL_DIR/lib/clone-setup.sh"
  _pwork_setup_clone "p1" "$TEST_WORKSPACE/p1" "$TEST_WORKSPACE"

  local content
  content=$(cat "$TEST_WORKSPACE/p1/.claude/settings.local.json")
  assert_contains "$content" '/custom/path' "existing statusLine not overwritten"

  teardown_test_workspace
}

# Description: statusline.sh has execute permission so Claude Code can run it.
test_statusline_script_is_executable() {
  # -x tests if the file has execute permission.
  [[ -x "$PWORK_INSTALL_DIR/lib/statusline.sh" ]]
  assert_status_ok $? "statusline.sh is executable"
}
