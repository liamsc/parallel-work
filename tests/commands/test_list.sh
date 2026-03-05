#!/usr/bin/env bash
# Tests for plist command.

test_plist_header_shows_version() {
  setup_test_workspace

  local output expected_ver
  output=$(plist)
  expected_ver=$(tr -d '\n' < "$PWORK_INSTALL_DIR/VERSION")
  assert_contains "$output" "parallel-work ${expected_ver}" "plist header includes version"

  teardown_test_workspace
}

test_plist_includes_all_commands() {
  setup_test_workspace

  local output
  output=$(plist)
  assert_contains "$output" "p-init" "plist includes p-init"
  assert_contains "$output" "p-sync" "plist includes p-sync"
  assert_contains "$output" "p-status" "plist includes p-status"
  assert_contains "$output" "p-branches" "plist includes p-branches"
  assert_contains "$output" "p-new" "plist includes p-new"
  assert_contains "$output" "p-setup" "plist includes p-setup"
  assert_contains "$output" "p-clean" "plist includes p-clean"
  assert_contains "$output" "p-update" "plist includes p-update"
  assert_contains "$output" "p-version" "plist includes p-version"
  assert_contains "$output" "plist" "plist includes plist"
  assert_contains "$output" "yolo" "plist includes yolo"
  assert_contains "$output" "pw" "plist includes pw"

  teardown_test_workspace
}
