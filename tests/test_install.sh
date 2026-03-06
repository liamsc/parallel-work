#!/usr/bin/env bash
# Tests for install.sh.

# Description: install.sh appends the PWORK_INSTALL_DIR export and source line to .zshrc.
test_install_adds_source_line() {
  setup_test_workspace

  local fake_home="$TEST_TMPDIR/fakehome"
  mkdir -p "$fake_home"
  touch "$fake_home/.zshrc"

  HOME="$fake_home" SHELL="/bin/zsh" "$SCRIPT_DIR/install.sh" >/dev/null 2>&1

  local rc_content
  rc_content=$(cat "$fake_home/.zshrc")
  assert_contains "$rc_content" "PWORK_INSTALL_DIR" "install adds PWORK_INSTALL_DIR"
  assert_contains "$rc_content" "shell-helpers.sh" "install adds source line"

  teardown_test_workspace
}

# Description: running install.sh twice only adds the source line once.
test_install_is_idempotent() {
  setup_test_workspace

  local fake_home="$TEST_TMPDIR/fakehome"
  mkdir -p "$fake_home"
  touch "$fake_home/.zshrc"

  HOME="$fake_home" SHELL="/bin/zsh" "$SCRIPT_DIR/install.sh" >/dev/null 2>&1
  HOME="$fake_home" SHELL="/bin/zsh" "$SCRIPT_DIR/install.sh" >/dev/null 2>&1

  local source_count
  source_count=$(grep -c "shell-helpers.sh" "$fake_home/.zshrc")
  assert_eq "1" "$source_count" "install is idempotent (only one source line after two runs)"

  teardown_test_workspace
}

# Description: install.sh does not error when git is available.
test_install_checks_git() {
  setup_test_workspace

  # install.sh requires git — since we have git, it should succeed
  local fake_home="$TEST_TMPDIR/fakehome"
  mkdir -p "$fake_home"
  touch "$fake_home/.zshrc"

  local output
  output=$(HOME="$fake_home" SHELL="/bin/zsh" "$SCRIPT_DIR/install.sh" 2>&1)
  assert_not_contains "$output" "Error: git is required" "install does not error when git exists"

  teardown_test_workspace
}
