#!/usr/bin/env bash
# Tests for p-update command.

# Description: p-update fails when PWORK_INSTALL_DIR is not set.
test_p_update_fails_when_install_dir_unset() {
  local output
  # Run in a subshell with PWORK_INSTALL_DIR explicitly unset
  output=$(unset PWORK_INSTALL_DIR; p-update 2>&1)
  local status=$?

  assert_status_fail "$status" "p-update exits non-zero when PWORK_INSTALL_DIR unset"
  assert_contains "$output" "PWORK_INSTALL_DIR is not set" "p-update error mentions PWORK_INSTALL_DIR"
}

# Description: p-update fails when PWORK_INSTALL_DIR is not a git repository.
test_p_update_fails_when_not_a_git_repo() {
  # Use the standard sandbox so cleanup goes through teardown_test_workspace
  # → _test_rm; no independent mktemp that the safety helper can't validate.
  setup_test_workspace
  local tmpdir="$TEST_TMPDIR/not-a-git-repo"
  mkdir -p "$tmpdir"

  local output
  output=$(PWORK_INSTALL_DIR="$tmpdir" p-update 2>&1)
  local status=$?

  assert_status_fail "$status" "p-update exits non-zero for non-git dir"
  assert_contains "$output" "not a git repo" "p-update error mentions not a git repo"

  teardown_test_workspace
}

# Description: p-update runs git pull and re-sources shell-helpers successfully.
test_p_update_pulls_and_reloads() {
  setup_test_workspace

  # Create a fake "install dir" that is a git repo
  local install_dir="$TEST_TMPDIR/fake-install"
  git clone "$TEST_ORIGIN" "$install_dir" >/dev/null 2>&1
  (
    cd "$install_dir"
    git config user.email "test@test.com"
    git config user.name "Test"
  )

  # Copy install.sh, VERSION, and lib/ into the fake install dir so p-update can run them
  cp "$PWORK_INSTALL_DIR/install.sh" "$install_dir/"
  cp "$PWORK_INSTALL_DIR/VERSION" "$install_dir/"
  cp -R "$PWORK_INSTALL_DIR/lib" "$install_dir/lib"

  local output
  # Override HOME so install.sh writes to a throwaway rc file instead of the real ~/.zshrc
  output=$(HOME="$TEST_TMPDIR" PWORK_INSTALL_DIR="$install_dir" p-update 2>&1)
  local status=$?

  assert_status_ok "$status" "p-update succeeds on a valid git install dir"
  assert_contains "$output" "Updating parallel-work" "p-update prints updating message"
  assert_contains "$output" "Done!" "p-update prints done message"

  _test_rm "$install_dir"
  teardown_test_workspace
}

# Description: p-update refuses to run when the install dir is checked out on a non-main branch.
test_p_update_fails_on_non_main_branch() {
  setup_test_workspace

  # Build a fake install dir like the other tests, but check out a feature
  # branch in it before invoking p-update. We expect a clear error and
  # exit non-zero — not a silent "Done!" with no actual update.
  local install_dir="$TEST_TMPDIR/fake-install"
  git clone "$TEST_ORIGIN" "$install_dir" >/dev/null 2>&1
  (
    cd "$install_dir"
    git config user.email "test@test.com"
    git config user.name "Test"
    git checkout -b fix/some-feature >/dev/null 2>&1
  )
  cp "$PWORK_INSTALL_DIR/install.sh" "$install_dir/"
  cp "$PWORK_INSTALL_DIR/VERSION" "$install_dir/"
  cp -R "$PWORK_INSTALL_DIR/lib" "$install_dir/lib"

  local output status
  output=$(HOME="$TEST_TMPDIR" PWORK_INSTALL_DIR="$install_dir" p-update 2>&1)
  status=$?

  assert_status_fail "$status" "p-update exits non-zero on a non-main branch"
  assert_contains "$output" "fix/some-feature" "error mentions the actual branch name"
  assert_contains "$output" "checkout main" "error tells user how to recover"
  assert_not_contains "$output" "Done!" "p-update doesn't claim success on failure"

  _test_rm "$install_dir"
  teardown_test_workspace
}

# Description: p-update shows "old -> new" version transition when VERSION changes.
test_p_update_shows_version_transition() {
  setup_test_workspace

  # Create a fake "install dir" that is a git repo
  local install_dir="$TEST_TMPDIR/fake-install"
  git clone "$TEST_ORIGIN" "$install_dir" >/dev/null 2>&1
  (
    cd "$install_dir"
    git config user.email "test@test.com"
    git config user.name "Test"
  )

  # Copy install.sh, VERSION, and lib/ into the fake install dir
  cp "$PWORK_INSTALL_DIR/install.sh" "$install_dir/"
  cp "$PWORK_INSTALL_DIR/VERSION" "$install_dir/"
  cp -R "$PWORK_INSTALL_DIR/lib" "$install_dir/lib"

  # Commit everything so git pull works cleanly
  (
    cd "$install_dir"
    git add -A && git commit -m "setup" >/dev/null 2>&1
    git push >/dev/null 2>&1
  )

  # Bump the version in origin so the pull picks it up
  local bump_dir="$TEST_TMPDIR/bump-clone"
  git clone "$TEST_ORIGIN" "$bump_dir" >/dev/null 2>&1
  (
    cd "$bump_dir"
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "0.2.0" > VERSION
    git add VERSION && git commit -m "bump version" >/dev/null 2>&1
    git push >/dev/null 2>&1
  )
  _test_rm "$bump_dir"

  local output
  # Override HOME so install.sh writes to a throwaway rc file instead of the real ~/.zshrc
  output=$(HOME="$TEST_TMPDIR" PWORK_INSTALL_DIR="$install_dir" p-update 2>&1)
  local status=$?

  assert_status_ok "$status" "p-update succeeds with version bump"
  assert_contains "$output" "0.1.0 -> 0.2.0" "p-update shows version transition"

  _test_rm "$install_dir"
  teardown_test_workspace
}
