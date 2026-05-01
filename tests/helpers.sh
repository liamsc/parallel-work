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

# ── Safer rm for tests ───────────────────────────────────────
# Wraps `rm -rf` with guards that refuse to delete anything outside the
# per-test sandbox. Catches the classic footgun where an unset variable
# turns "$TEST_TMPDIR/fake-install" into the literal "/fake-install".
#
# Refuses if:
#   - the path is empty
#   - TEST_TMPDIR is unset
#   - the path contains ".." (defends against symlink/relative-path bypass)
#   - the path isn't TEST_TMPDIR itself or strictly under it
_test_rm() {
  local path="$1"
  if [[ -z "$path" ]]; then
    echo "_test_rm refused: empty path" >&2
    return 1
  fi
  if [[ -z "${TEST_TMPDIR:-}" ]]; then
    echo "_test_rm refused: TEST_TMPDIR unset (path=$path)" >&2
    return 1
  fi
  case "$path" in
    *..*) echo "_test_rm refused: path contains '..': $path" >&2; return 1 ;;
  esac
  if [[ "$path" != "$TEST_TMPDIR" && "$path" != "$TEST_TMPDIR/"* ]]; then
    echo "_test_rm refused: path outside TEST_TMPDIR: $path (TEST_TMPDIR=$TEST_TMPDIR)" >&2
    return 1
  fi
  rm -rf "$path"
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
  _test_rm "$seed"

  export PWORK_INSTALL_DIR="$SCRIPT_DIR"
  source "$PWORK_INSTALL_DIR/lib/shell-helpers.sh"

  TEST_WORKSPACE="$TEST_TMPDIR/workspace"
}

teardown_test_workspace() {
  _test_rm "$TEST_TMPDIR"
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
