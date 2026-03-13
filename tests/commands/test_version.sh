#!/usr/bin/env bash
# Tests for p-version command.

# Description: _pwork_version returns the contents of the VERSION file.
test_pwork_version_reads_version_file() {
  setup_test_workspace

  local output
  output=$(_pwork_version)
  local expected
  # $(<file) reads the file into a variable; tr -d '\n' strips the trailing newline
  expected=$(tr -d '\n' < "$PWORK_INSTALL_DIR/VERSION")
  assert_eq "$expected" "$output" "_pwork_version returns VERSION file contents"

  teardown_test_workspace
}

# Description: _pwork_version returns "unknown" when the VERSION file is missing.
test_pwork_version_returns_unknown_when_missing() {
  setup_test_workspace

  local output
  # Point to a directory with no VERSION file
  output=$(PWORK_INSTALL_DIR="/tmp/nonexistent-dir" _pwork_version)
  assert_eq "unknown" "$output" "_pwork_version returns 'unknown' when VERSION file missing"

  teardown_test_workspace
}

# Description: p-version output contains the version number from VERSION.
test_p_version_includes_version_number() {
  setup_test_workspace

  local output
  output=$(p-version)
  local expected_ver
  expected_ver=$(tr -d '\n' < "$PWORK_INSTALL_DIR/VERSION")
  assert_contains "$output" "$expected_ver" "p-version output includes version number"

  teardown_test_workspace
}

# Description: p-version output includes the "parallel-work" prefix.
test_p_version_includes_parallel_work_prefix() {
  setup_test_workspace

  local output
  output=$(p-version)
  assert_contains "$output" "parallel-work" "p-version output starts with parallel-work"

  teardown_test_workspace
}

# Description: p-version output includes the short git SHA of the install dir.
test_p_version_includes_git_sha() {
  setup_test_workspace

  # Only meaningful when PWORK_INSTALL_DIR is a git repo
  # -d tests if the path is a directory
  if [[ -d "$PWORK_INSTALL_DIR/.git" ]]; then
    local output sha
    output=$(p-version)
    # --short gives abbreviated SHA
    sha=$(git -C "$PWORK_INSTALL_DIR" rev-parse --short HEAD 2>/dev/null)
    assert_contains "$output" "$sha" "p-version output includes git SHA"
  fi

  teardown_test_workspace
}
