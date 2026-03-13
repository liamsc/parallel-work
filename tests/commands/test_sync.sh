#!/usr/bin/env bash
# Tests for p-sync command.

# Description: p-sync pulls new upstream commits into all clones.
test_p_sync_pulls_all_clones() {
  setup_test_workspace
  create_workspace 3

  # Push a new commit to origin from a temporary clone
  local pusher="$TEST_TMPDIR/pusher"
  git clone "$TEST_ORIGIN" "$pusher" >/dev/null 2>&1
  (
    cd "$pusher"
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "new content" > newfile.txt
    git add newfile.txt
    git commit -m "add newfile" >/dev/null 2>&1
    git push >/dev/null 2>&1
  )

  # Sync all clones
  (cd "$TEST_WORKSPACE/p1" && p-sync) >/dev/null 2>&1

  # Each clone should have the new commit
  local log
  for clone in p1 p2 p3; do
    log=$(cd "$TEST_WORKSPACE/$clone" && git log --oneline)
    assert_contains "$log" "add newfile" "p-sync pulled new commit into $clone"
  done

  teardown_test_workspace
}

# Description: p-sync runs PWORK_SYNC_CMD in each clone after pulling.
test_p_sync_runs_sync_cmd() {
  setup_test_workspace
  create_workspace 3

  # Override sync cmd in the config
  echo 'PWORK_SYNC_CMD="touch .synced"' >> "$TEST_WORKSPACE/.parallel-work/pwork.conf"

  (cd "$TEST_WORKSPACE/p1" && p-sync) >/dev/null 2>&1

  for clone in p1 p2 p3; do
    [[ -f "$TEST_WORKSPACE/$clone/.synced" ]] || {
      echo "  FAIL: .synced not found in $clone" >&2
      teardown_test_workspace
      return 1
    }
  done

  teardown_test_workspace
}

# Description: p-sync prints syncing/done progress for each clone.
test_p_sync_reports_output() {
  setup_test_workspace
  create_workspace 3

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && p-sync 2>&1)

  # Each clone should report syncing and done
  for clone in p1 p2 p3; do
    assert_contains "$output" "[$clone] syncing" "p-sync reports syncing for $clone"
    assert_contains "$output" "[$clone] done" "p-sync reports done for $clone"
  done

  teardown_test_workspace
}
