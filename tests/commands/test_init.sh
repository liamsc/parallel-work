#!/usr/bin/env bash
# Tests for p-init command: clone count validation and slug extraction.

test_bad_clone_count_rejected() {
  setup_test_workspace

  local output status
  output=$(p-init "file:///fake" "$TEST_TMPDIR/ws" --clones 0 2>&1)
  status=$?
  assert_status_fail "$status" "p-init --clones 0 should fail"
  assert_contains "$output" "must be between 1 and 20" "p-init --clones 0 error message"

  teardown_test_workspace
}

test_bad_clone_count_too_high() {
  setup_test_workspace

  local output status
  output=$(p-init "file:///fake" "$TEST_TMPDIR/ws" --clones 99 2>&1)
  status=$?
  assert_status_fail "$status" "p-init --clones 99 should fail"
  assert_contains "$output" "must be between 1 and 20" "p-init --clones 99 error message"

  teardown_test_workspace
}

test_bad_clone_count_non_numeric() {
  setup_test_workspace

  local output status
  output=$(p-init "file:///fake" "$TEST_TMPDIR/ws" --clones abc 2>&1)
  status=$?
  assert_status_fail "$status" "p-init --clones abc should fail"
  assert_contains "$output" "must be between 1 and 20" "p-init --clones abc error message"

  teardown_test_workspace
}

test_slug_github_ssh() {
  setup_test_workspace
  local slug
  slug=$(echo "git@github.com:myorg/myrepo.git" | sed -E 's#^.+[:/]([^/]+/[^/]+?)(\.git)?$#\1#')
  assert_eq "myorg/myrepo" "$slug" "slug from GitHub SSH URL"
  teardown_test_workspace
}

test_slug_github_https() {
  setup_test_workspace
  local slug
  slug=$(echo "https://github.com/myorg/myrepo.git" | sed -E 's#^.+[:/]([^/]+/[^/]+?)(\.git)?$#\1#')
  assert_eq "myorg/myrepo" "$slug" "slug from GitHub HTTPS URL"
  teardown_test_workspace
}

test_slug_gitlab_ssh() {
  setup_test_workspace
  local slug
  slug=$(echo "git@gitlab.com:myorg/myrepo.git" | sed -E 's#^.+[:/]([^/]+/[^/]+?)(\.git)?$#\1#')
  assert_eq "myorg/myrepo" "$slug" "slug from GitLab SSH URL"
  teardown_test_workspace
}

test_slug_no_git_suffix() {
  setup_test_workspace
  local slug
  slug=$(echo "https://github.com/myorg/myrepo" | sed -E 's#^.+[:/]([^/]+/[^/]+?)(\.git)?$#\1#')
  assert_eq "myorg/myrepo" "$slug" "slug from URL without .git suffix"
  teardown_test_workspace
}

test_slug_bitbucket() {
  setup_test_workspace
  local slug
  slug=$(echo "git@bitbucket.org:myorg/myrepo.git" | sed -E 's#^.+[:/]([^/]+/[^/]+?)(\.git)?$#\1#')
  assert_eq "myorg/myrepo" "$slug" "slug from Bitbucket SSH URL"
  teardown_test_workspace
}
