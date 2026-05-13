#!/usr/bin/env bash
# Tests for the test infrastructure itself — specifically _test_rm, the
# rm -rf wrapper that guards against deleting paths outside the per-test
# sandbox. If these tests start failing, the safety net has a hole.

# Description: _test_rm refuses an empty path argument.
test_test_rm_refuses_empty_path() {
  setup_test_workspace
  local output status
  output=$(_test_rm "" 2>&1)
  status=$?
  assert_status_fail "$status" "_test_rm '' should fail"
  assert_contains "$output" "empty path" "error names the cause"
  teardown_test_workspace
}

# Description: _test_rm refuses when TEST_TMPDIR is unset.
test_test_rm_refuses_when_tmpdir_unset() {
  setup_test_workspace
  # Save the real TEST_TMPDIR, blank it for this assertion, restore so
  # teardown still works.
  local saved="$TEST_TMPDIR"
  local output status
  output=$(TEST_TMPDIR="" _test_rm "/tmp/some-path" 2>&1)
  status=$?
  TEST_TMPDIR="$saved"
  assert_status_fail "$status" "_test_rm should fail without TEST_TMPDIR"
  assert_contains "$output" "TEST_TMPDIR unset" "error names the cause"
  teardown_test_workspace
}

# Description: _test_rm refuses paths that don't live under TEST_TMPDIR.
test_test_rm_refuses_path_outside_sandbox() {
  setup_test_workspace
  local output status
  output=$(_test_rm "/etc/passwd" 2>&1)
  status=$?
  assert_status_fail "$status" "_test_rm /etc/passwd should fail"
  assert_contains "$output" "outside TEST_TMPDIR" "error names the cause"
  # Sanity check: file we tried to delete still exists.
  if [[ ! -f /etc/passwd ]]; then
    echo "  FAIL: /etc/passwd disappeared (would be very bad)" >&2
    teardown_test_workspace
    return 1
  fi
  teardown_test_workspace
}

# Description: _test_rm refuses paths containing '..' (defense against bypass).
test_test_rm_refuses_dotdot_in_path() {
  setup_test_workspace
  local output status
  output=$(_test_rm "$TEST_TMPDIR/../escape" 2>&1)
  status=$?
  assert_status_fail "$status" "_test_rm with .. should fail"
  assert_contains "$output" "'..'" "error names the cause"
  teardown_test_workspace
}

# Description: _test_rm successfully removes a real file inside TEST_TMPDIR.
test_test_rm_removes_path_inside_sandbox() {
  setup_test_workspace
  local target="$TEST_TMPDIR/disposable-file"
  echo "delete me" > "$target"
  [[ -f "$target" ]] || { echo "  FAIL: setup didn't create target" >&2; teardown_test_workspace; return 1; }

  _test_rm "$target"
  if [[ -e "$target" ]]; then
    echo "  FAIL: _test_rm didn't remove $target" >&2
    teardown_test_workspace
    return 1
  fi
  teardown_test_workspace
}

# Description: _test_rm refuses the literal root path '/'.
test_test_rm_refuses_root_path() {
  setup_test_workspace
  local output status
  output=$(_test_rm "/" 2>&1)
  status=$?
  assert_status_fail "$status" "_test_rm / should fail"
  assert_contains "$output" "is '/'" "error names the cause"
  teardown_test_workspace
}

# Description: _test_rm refuses paths that aren't absolute.
test_test_rm_refuses_relative_path() {
  setup_test_workspace
  local output status
  output=$(_test_rm "relative/path" 2>&1)
  status=$?
  assert_status_fail "$status" "_test_rm with relative path should fail"
  assert_contains "$output" "not absolute" "error names the cause"
  teardown_test_workspace
}

# Description: _test_rm refuses if TEST_TMPDIR is suspiciously short (e.g. "/tmp").
test_test_rm_refuses_short_tmpdir() {
  setup_test_workspace
  local output status
  output=$(TEST_TMPDIR="/tmp" _test_rm "/tmp/foo" 2>&1)
  status=$?
  assert_status_fail "$status" "_test_rm with short TEST_TMPDIR should fail"
  assert_contains "$output" "suspiciously short" "error names the cause"
  teardown_test_workspace
}

# Description: _test_rm refuses if TEST_TMPDIR isn't an existing directory.
test_test_rm_refuses_nonexistent_tmpdir() {
  setup_test_workspace
  local output status
  # Long enough to pass the length check, but no such directory exists.
  local fake="/tmp/parallel-work-test-rm-nonexistent-xyz12345"
  output=$(TEST_TMPDIR="$fake" _test_rm "$fake/foo" 2>&1)
  status=$?
  assert_status_fail "$status" "_test_rm with nonexistent TEST_TMPDIR should fail"
  assert_contains "$output" "not a directory" "error names the cause"
  teardown_test_workspace
}

# Description: _test_rm refuses if TEST_TMPDIR points at a real dir we didn't create.
# The "could-be-anything" attack: a user could have TEST_TMPDIR exported in
# their shell rc to ~/important — every shape check (length, absolute,
# exists) passes, but the marker file is missing because setup_test_workspace
# didn't create it. _test_rm refuses.
test_test_rm_refuses_unmarked_tmpdir() {
  setup_test_workspace
  # Build a real, long, existing directory with NO sandbox marker.
  local impostor="$TEST_TMPDIR/impostor-pretending-to-be-a-sandbox"
  mkdir -p "$impostor"
  echo "user data" > "$impostor/important.txt"

  local output status
  output=$(TEST_TMPDIR="$impostor" _test_rm "$impostor/important.txt" 2>&1)
  status=$?

  assert_status_fail "$status" "_test_rm should refuse a TEST_TMPDIR without the marker"
  assert_contains "$output" "no sandbox marker" "error names the cause"
  # Sanity: the impostor file we tried to delete is still there.
  if [[ ! -f "$impostor/important.txt" ]]; then
    echo "  FAIL: file was deleted despite marker check" >&2
    teardown_test_workspace
    return 1
  fi
  teardown_test_workspace
}

# Description: _test_rm refuses if TEST_TMPDIR isn't absolute.
test_test_rm_refuses_relative_tmpdir() {
  setup_test_workspace
  local output status
  output=$(TEST_TMPDIR="relative-tmpdir-name-xyz" _test_rm "relative-tmpdir-name-xyz/foo" 2>&1)
  status=$?
  assert_status_fail "$status" "_test_rm with relative TEST_TMPDIR should fail"
  # The path-not-absolute check fires first; either error is fine but at
  # minimum we must not have proceeded to the rm.
  assert_status_fail "$status" "any refusal counts"
  teardown_test_workspace
}

# Description: _test_rm refuses paths that escape TEST_TMPDIR via a symlink.
# The string-prefix containment check would pass for paths like
# $TEST_TMPDIR/escape/important, but if "escape" is a symlink to /Users/me,
# `rm -rf` would follow it and delete real user data. The canonical-path
# check using realpath blocks this.
#
# Fixture note: this test is the one place where we deliberately reach
# outside TEST_TMPDIR — otherwise we couldn't simulate the escape we're
# defending against. Cleanup uses targeted `unlink` + `rmdir` (no `rm -rf`,
# no recursion), so even if the fixture goes wrong nothing can walk into
# unrelated directories.
test_test_rm_refuses_symlink_escape() {
  setup_test_workspace
  # Build a true outside-the-sandbox dir to act as "user data we'd hate to
  # lose". $TMPDIR (or /tmp) is the parent — the symlink under TEST_TMPDIR
  # will point at it.
  local outside_root="${TMPDIR:-/tmp}"
  local outside="$outside_root/parallel-work-test-symlink-target-$$"
  mkdir -p "$outside"
  echo "user data" > "$outside/important.txt"

  # Sanity: $outside must be outside $TEST_TMPDIR. If a future change to
  # mktemp behavior puts them in the same tree, abort instead of misleading.
  case "$outside" in
    "$TEST_TMPDIR"|"$TEST_TMPDIR"/*)
      echo "  FAIL: fixture error — outside dir is inside TEST_TMPDIR" >&2
      unlink "$outside/important.txt" 2>/dev/null
      rmdir "$outside" 2>/dev/null
      teardown_test_workspace
      return 1 ;;
  esac

  ln -s "$outside" "$TEST_TMPDIR/escape"

  local output status
  # String containment passes ($TEST_TMPDIR/escape/...) but realpath
  # resolves to $outside/important.txt — outside canonical TEST_TMPDIR.
  output=$(_test_rm "$TEST_TMPDIR/escape/important.txt" 2>&1)
  status=$?

  local refusal_failed=0
  [[ "$status" -eq 0 ]] && refusal_failed=1
  local data_lost=0
  [[ ! -f "$outside/important.txt" ]] && data_lost=1

  # Targeted cleanup. unlink + rmdir only — never `rm -rf` outside the
  # sandbox. If the safety check failed and the file is already gone,
  # unlink errors harmlessly.
  unlink "$outside/important.txt" 2>/dev/null
  rmdir "$outside" 2>/dev/null

  if [[ "$refusal_failed" -eq 1 ]]; then
    echo "  FAIL: _test_rm should refuse a path that escapes via symlink (exit status: $status)" >&2
    teardown_test_workspace
    return 1
  fi
  assert_contains "$output" "symlink" "error names the cause"
  if [[ "$data_lost" -eq 1 ]]; then
    echo "  FAIL: file was deleted through the symlink (very bad)" >&2
    teardown_test_workspace
    return 1
  fi
  teardown_test_workspace
}

# Description: _test_rm accepts TEST_TMPDIR itself (used by teardown).
test_test_rm_accepts_tmpdir_root() {
  setup_test_workspace
  local saved="$TEST_TMPDIR"
  # Drop a marker so we can confirm the dir actually got removed.
  echo "marker" > "$TEST_TMPDIR/marker"

  _test_rm "$TEST_TMPDIR"
  if [[ -d "$saved" ]]; then
    echo "  FAIL: _test_rm didn't remove TEST_TMPDIR root" >&2
    return 1
  fi
  # No teardown_test_workspace — we just removed the dir it would clean up.
}

# Description: _test_rm refuses paths containing a newline.
# Defends against shell-quoting bugs that splice extra arguments into "$path".
test_test_rm_refuses_newline_in_path() {
  setup_test_workspace
  local output status
  # $'...' — bash ANSI-C quoting so \n expands to a literal newline.
  output=$(_test_rm "$TEST_TMPDIR/with"$'\n'"newline" 2>&1)
  status=$?
  assert_status_fail "$status" "_test_rm should refuse newline in path"
  assert_contains "$output" "newline" "error names the cause"
  teardown_test_workspace
}

# Description: _test_rm refuses if TEST_TMPDIR equals $HOME.
# $HOME is long enough to slip past the length floor, so the marker check
# and this explicit denylist entry are the only walls left.
test_test_rm_refuses_home_as_tmpdir() {
  setup_test_workspace
  local output status
  # Use the real $HOME — that's the value the denylist actually compares
  # against. The marker check would also refuse (no marker in $HOME), but
  # the denylist fires first and gives a clearer message.
  output=$(TEST_TMPDIR="$HOME" _test_rm "$HOME/some-file" 2>&1)
  status=$?
  assert_status_fail "$status" "_test_rm should refuse TEST_TMPDIR=\$HOME"
  assert_contains "$output" "known-dangerous" "error names the cause"
  teardown_test_workspace
}

# Description: _test_rm refuses if TEST_TMPDIR itself is a symlink.
# Closes a hole where TEST_TMPDIR=/tmp/imposter -> /Users/me would pass the
# marker check (it follows the link) and then rm -rf would delete real user
# files through the link.
test_test_rm_refuses_symlink_tmpdir() {
  setup_test_workspace
  # Real directory that the symlink will point at — placed inside the real
  # sandbox so cleanup is automatic. Drop a marker so the marker check would
  # otherwise pass through the link.
  local real_target="$TEST_TMPDIR/real-target"
  mkdir -p "$real_target"
  : > "$real_target/$_TEST_SANDBOX_MARKER"
  echo "user data" > "$real_target/important.txt"

  # The symlink itself lives alongside the sandbox (under TMPDIR/tmp, not
  # inside the real sandbox we want to protect) so it doesn't get cleaned up
  # by realpath-based comparisons we're not testing here.
  local link_path="$TEST_TMPDIR/symlink-tmpdir"
  ln -s "$real_target" "$link_path"

  local output status
  output=$(TEST_TMPDIR="$link_path" _test_rm "$link_path/important.txt" 2>&1)
  status=$?
  assert_status_fail "$status" "_test_rm should refuse a symlinked TEST_TMPDIR"
  assert_contains "$output" "symlink" "error names the cause"
  # Sanity: the file we tried to delete is still there.
  if [[ ! -f "$real_target/important.txt" ]]; then
    echo "  FAIL: file was deleted through the symlinked TEST_TMPDIR" >&2
    teardown_test_workspace
    return 1
  fi
  teardown_test_workspace
}

# Description: _test_rm normalizes a trailing slash on TEST_TMPDIR.
# Without normalization the prefix check would look for "$TMPDIR//" and
# falsely refuse legitimate paths under the sandbox.
test_test_rm_handles_trailing_slash_in_tmpdir() {
  setup_test_workspace
  local target="$TEST_TMPDIR/disposable"
  echo "delete me" > "$target"

  # Append a trailing slash to TEST_TMPDIR. The target path stays slash-free.
  TEST_TMPDIR="$TEST_TMPDIR/" _test_rm "$target"
  if [[ -e "$target" ]]; then
    echo "  FAIL: _test_rm refused a valid path because of trailing slash" >&2
    teardown_test_workspace
    return 1
  fi
  teardown_test_workspace
}
