#!/usr/bin/env bash
# Test helpers: assertions and workspace fixtures.

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-assert_eq}"
  if [[ "$expected" == "$actual" ]]; then
    return 0
  else
    echo "  FAIL: $msg" >&2
    echo "    expected: '$expected'" >&2
    echo "    actual:   '$actual'" >&2
    return 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-assert_contains}"
  if [[ "$haystack" == *"$needle"* ]]; then
    return 0
  else
    echo "  FAIL: $msg" >&2
    echo "    expected to contain: '$needle'" >&2
    echo "    actual: '$haystack'" >&2
    return 1
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="${3:-assert_not_contains}"
  if [[ "$haystack" != *"$needle"* ]]; then
    return 0
  else
    echo "  FAIL: $msg" >&2
    echo "    expected NOT to contain: '$needle'" >&2
    echo "    actual: '$haystack'" >&2
    return 1
  fi
}

assert_status_ok() {
  local status="$1" msg="${2:-assert_status_ok}"
  if [[ "$status" -eq 0 ]]; then
    return 0
  else
    echo "  FAIL: $msg (exit status: $status, expected 0)" >&2
    return 1
  fi
}

assert_status_fail() {
  local status="$1" msg="${2:-assert_status_fail}"
  if [[ "$status" -ne 0 ]]; then
    return 0
  else
    echo "  FAIL: $msg (exit status: 0, expected non-zero)" >&2
    return 1
  fi
}

# ── Workspace fixtures ───────────────────────────────────────

setup_test_workspace() {
  TEST_TMPDIR="$(mktemp -d)"
  TEST_ORIGIN="$TEST_TMPDIR/origin.git"

  # Create a bare "origin" repo with one commit
  git init --bare -b main "$TEST_ORIGIN" >/dev/null 2>&1
  local seed="$TEST_TMPDIR/seed"
  git clone "$TEST_ORIGIN" "$seed" >/dev/null 2>&1
  (
    cd "$seed"
    git config user.email "test@test.com"
    git config user.name "Test"
    git commit --allow-empty -m "init" >/dev/null 2>&1
    git push >/dev/null 2>&1
  )
  rm -rf "$seed"

  export PWORK_INSTALL_DIR="$SCRIPT_DIR"
  source "$PWORK_INSTALL_DIR/lib/shell-helpers.sh"

  TEST_WORKSPACE="$TEST_TMPDIR/workspace"
}

teardown_test_workspace() {
  rm -rf "$TEST_TMPDIR"
}

# Create a fully bootstrapped workspace with N clones.
create_workspace() {
  local clone_count="${1:-3}"
  mkdir -p "$TEST_WORKSPACE/.parallel-work"

  cat > "$TEST_WORKSPACE/.parallel-work/pwork.conf" <<EOF
PWORK_REPO_URL="$TEST_ORIGIN"
PWORK_REPO_SLUG="test/repo"
PWORK_CLONE_COUNT=$clone_count
PWORK_DEFAULT_BRANCH="main"
PWORK_SYNC_CMD=""
PWORK_SHARED_FILES=()
EOF

  source "$TEST_WORKSPACE/.parallel-work/pwork.conf"
  WORKSPACE_ROOT="$TEST_WORKSPACE"
  source "$PWORK_INSTALL_DIR/lib/bootstrap.sh"
  bootstrap_workspace >/dev/null 2>&1
}
