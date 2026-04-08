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

# Description: statusline output fits within a narrow terminal by dropping
# low-priority segments (repo slug) instead of overflowing.
test_statusline_fits_narrow_terminal() {
  setup_test_workspace
  create_workspace 1

  # Run the statusline script with a narrow terminal (50 cols).
  # COLUMNS tells tput cols what width to report.
  local output
  output=$(echo '{"workspace":{"current_dir":"'"$TEST_WORKSPACE/p1"'"},"context_window":{"used_percentage":25}}' \
    | COLUMNS=50 "$PWORK_INSTALL_DIR/lib/statusline.sh" 2>&1)

  # Strip ANSI codes and check that no line exceeds terminal width.
  local max_line_len=0
  while IFS= read -r line; do
    local plain
    plain=$(echo "$line" | sed $'s/\033\\[[0-9;]*m//g')
    local len=${#plain}
    (( len > max_line_len )) && max_line_len=$len
  done <<< "$output"

  [[ "$max_line_len" -le 50 ]]
  assert_status_ok $? "statusline fits within 50 columns (actual: $max_line_len)"

  # Repo slug should be dropped at this width.
  local plain_output
  plain_output=$(echo "$output" | sed $'s/\033\\[[0-9;]*m//g')
  assert_not_contains "$plain_output" "repo:" "repo segment dropped at narrow width"

  teardown_test_workspace
}

# Description: statusline truncates a long branch name with "…" when the full
# name would overflow the terminal, rather than dropping the segment entirely.
test_statusline_truncates_long_branch() {
  setup_test_workspace
  create_workspace 1

  # Create a long branch name in the test clone.
  (cd "$TEST_WORKSPACE/p1" && git checkout -b feat/very-long-branch-name-that-should-be-truncated) >/dev/null 2>&1

  # 70 cols: enough for clone + truncated branch + ctx, but not the full branch.
  local output
  output=$(echo '{"workspace":{"current_dir":"'"$TEST_WORKSPACE/p1"'"},"context_window":{"used_percentage":25}}' \
    | COLUMNS=70 "$PWORK_INSTALL_DIR/lib/statusline.sh" 2>&1)

  local plain_output
  plain_output=$(echo "$output" | sed $'s/\033\\[[0-9;]*m//g')

  # Branch should be present but truncated with "…".
  assert_contains "$plain_output" "branch:" "branch segment is present"
  assert_contains "$plain_output" "…" "branch name is truncated with ellipsis"
  assert_not_contains "$plain_output" "should-be-truncated" "full branch name is not shown"

  # Output should still fit.
  local max_line_len=0
  while IFS= read -r line; do
    local plain
    plain=$(echo "$line" | sed $'s/\033\\[[0-9;]*m//g')
    local len=${#plain}
    (( len > max_line_len )) && max_line_len=$len
  done <<< "$output"

  [[ "$max_line_len" -le 70 ]]
  assert_status_ok $? "statusline fits within 70 columns (actual: $max_line_len)"

  teardown_test_workspace
}
