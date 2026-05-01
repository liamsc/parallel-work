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
