#!/usr/bin/env bash
# Tests for statusline setup during clone bootstrap.

# Description: bootstrap creates .claude/settings.json with statusLine config.
test_bootstrap_creates_statusline_settings() {
  setup_test_workspace
  create_workspace 2

  [[ -f "$TEST_WORKSPACE/p1/.claude/settings.json" ]]
  assert_status_ok $? "bootstrap creates .claude/settings.json"

  local content
  content=$(cat "$TEST_WORKSPACE/p1/.claude/settings.json")
  assert_contains "$content" '"statusLine"' "settings.json contains statusLine"
  assert_contains "$content" 'statusline.sh' "settings.json points to statusline.sh"

  teardown_test_workspace
}

# Description: bootstrap adds .claude/settings.json to git's local exclude.
test_bootstrap_excludes_settings_json() {
  setup_test_workspace
  create_workspace 2

  local exclude_content
  exclude_content=$(cat "$TEST_WORKSPACE/p1/.git/info/exclude")
  assert_contains "$exclude_content" ".claude/settings.json" "git exclude contains settings.json"

  teardown_test_workspace
}

# Description: re-running clone setup does not overwrite custom settings.json.
test_statusline_settings_not_overwritten() {
  setup_test_workspace
  create_workspace 2

  # Write custom content to settings.json
  echo '{"custom": true}' > "$TEST_WORKSPACE/p1/.claude/settings.json"

  # Re-run setup
  source "$PWORK_INSTALL_DIR/lib/clone-setup.sh"
  _pwork_setup_clone "p1" "$TEST_WORKSPACE/p1" "$TEST_WORKSPACE"

  local content
  content=$(cat "$TEST_WORKSPACE/p1/.claude/settings.json")
  assert_contains "$content" '"custom"' "settings.json not overwritten on re-run"

  teardown_test_workspace
}

# Description: statusline.sh has execute permission so Claude Code can run it.
test_statusline_script_is_executable() {
  # -x tests if the file has execute permission.
  [[ -x "$PWORK_INSTALL_DIR/lib/statusline.sh" ]]
  assert_status_ok $? "statusline.sh is executable"
}
