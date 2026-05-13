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
# The "sandbox marker" file is the load-bearing check: shape rules
# (length, absolute, exists) are necessary but not sufficient — a user
# could have TEST_TMPDIR exported in their shell rc to a real directory
# they care about (~/my-stuff). _test_rm requires a sentinel file that
# only setup_test_workspace creates, so it can only delete directories
# this test harness made.
#
# Refuses any of:
#   - wrong number of arguments (must be exactly 1) — protects against
#     unquoted-expansion bugs where `_test_rm $var` splits into multiple
#     arguments and only the first gets safety-checked
#   - empty path
#   - non-absolute path (relative paths resolve via $PWD — too risky)
#   - path is exactly "/" (belt-and-suspenders for the worst case)
#   - path contains ".." (defends against relative-path bypass)
#   - path contains any control character (newline, CR, tab, escape, DEL,
#     etc.) — defends against weird shell-quoting bugs that splice extra
#     arguments into "$path", and against terminal-escape mischief in
#     error messages
#   - TEST_TMPDIR is unset
#   - TEST_TMPDIR is non-absolute
#   - TEST_TMPDIR contains ".." or control characters (same hygiene we
#     apply to $path — a malformed TEST_TMPDIR shouldn't slip through
#     just because the path argument is clean)
#   - TEST_TMPDIR is suspiciously short (< 16 chars: rules out "/", "/tmp")
#   - TEST_TMPDIR is on a hardcoded denylist of system directories or
#     equals $HOME — the marker check would already refuse most of these,
#     but the explicit denylist gives a readable error and adds a layer
#     against marker-check bypass (e.g. user happened to drop the marker
#     in their home for some reason)
#   - TEST_TMPDIR doesn't actually exist as a directory
#   - TEST_TMPDIR is a symlink — mktemp -d creates real directories, so
#     a symlinked TEST_TMPDIR is either user error or hostile. Without
#     this check, TEST_TMPDIR=/tmp/imposter -> /Users/me would pass the
#     marker check (it follows the link) and rm -rf would delete real
#     user files via the link
#   - TEST_TMPDIR is missing the sandbox-marker file (i.e., wasn't
#     created by setup_test_workspace — could be the user's home dir)
#   - path isn't TEST_TMPDIR itself or strictly under it (string check)
#   - canonicalized path (symlinks resolved) escapes the canonicalized
#     TEST_TMPDIR — blocks symlink-traversal: if an intermediate dir in
#     $path is a symlink to /Users/me, the string check passes but
#     `rm -rf` would follow the link and delete the target
#
# Final `rm` invocation uses `command rm` so a user-level alias or shell
# function named `rm` can't intercept the call and bypass these guards.
#
# A trailing slash on TEST_TMPDIR (e.g. /tmp/foo/) is normalized away so
# the prefix check doesn't falsely refuse paths inside it (without this,
# the prefix would be "/tmp/foo//" and "/tmp/foo/bar" wouldn't match).
_TEST_SANDBOX_MARKER='.parallel-work-test-sandbox'

# Well-known absolute paths that must never be TEST_TMPDIR. The < 16 char
# length floor already rules out most of these; the explicit list adds
# (a) clearer errors and (b) coverage for longer paths the length check
# would miss (notably $HOME). Exact match — subpaths like /var/folders/...
# are still allowed because real mktemp output lives under them.
_TEST_RM_TMPDIR_DENYLIST=(
  / /bin /sbin /usr /lib /opt /etc /var /private /dev /proc /sys
  /home /Users /root /boot /tmp /System /Library /Applications
)

_test_rm() {
  # Arity check first. `_test_rm $var "$other"` with an empty $var collapses
  # to one arg, but with whitespace it splits into many — and only $1 gets
  # safety-checked, while every arg gets passed to rm. Refuse anything that
  # isn't exactly one argument so the caller has to fix the quoting.
  if [[ $# -ne 1 ]]; then
    echo "_test_rm refused: expected exactly 1 argument, got $#" >&2
    return 1
  fi
  local path="$1"

  # ── Path-shape checks ──────────────────────────────────────
  if [[ -z "$path" ]]; then
    echo "_test_rm refused: empty path" >&2
    return 1
  fi
  # Reject relative paths up front. With a relative path, the prefix check
  # below would compare a $PWD-dependent string against an absolute
  # TEST_TMPDIR and silently fail — better to reject loudly here.
  if [[ "$path" != /* ]]; then
    echo "_test_rm refused: path is not absolute: $path" >&2
    return 1
  fi
  # Even if every other check passed, refuse the literal root.
  if [[ "$path" == "/" ]]; then
    echo "_test_rm refused: path is '/'" >&2
    return 1
  fi
  case "$path" in
    *..*) echo "_test_rm refused: path contains '..': $path" >&2; return 1 ;;
  esac
  # Bash glob `[...]` with ANSI-C ranges. $'\001'-$'\037' covers ASCII
  # control bytes 1-31 (tab=9, newline=10, CR=13, escape=27) and $'\177'
  # is DEL. Catches malformed paths that trip up downstream tools which
  # read only the first line, plus terminal-escape sequences in paths
  # that would otherwise render in the error message.
  case "$path" in
    *[$'\001'-$'\037']*|*$'\177'*)
      echo "_test_rm refused: path contains control characters" >&2
      return 1 ;;
  esac

  # ── TEST_TMPDIR sanity ─────────────────────────────────────
  if [[ -z "${TEST_TMPDIR:-}" ]]; then
    echo "_test_rm refused: TEST_TMPDIR unset (path=$path)" >&2
    return 1
  fi
  if [[ "$TEST_TMPDIR" != /* ]]; then
    echo "_test_rm refused: TEST_TMPDIR is not absolute: $TEST_TMPDIR" >&2
    return 1
  fi
  # Same hygiene we apply to $path. A TEST_TMPDIR with `..` defeats the
  # canonical containment check (realpath would resolve "/sandbox/.." to
  # "/" before comparison), and control chars in TEST_TMPDIR could splice
  # extra args into rm or hide nasty paths inside escape sequences.
  case "$TEST_TMPDIR" in
    *..*)
      echo "_test_rm refused: TEST_TMPDIR contains '..': $TEST_TMPDIR" >&2
      return 1 ;;
    *[$'\001'-$'\037']*|*$'\177'*)
      echo "_test_rm refused: TEST_TMPDIR contains control characters" >&2
      return 1 ;;
  esac
  # ${TEST_TMPDIR%/} — bash parameter expansion that strips a single
  # trailing "/" if present. Normalizes "/tmp/foo/" to "/tmp/foo" so the
  # prefix check below doesn't end up looking for "/tmp/foo//" (which no
  # real path inside the sandbox would match).
  local tmpdir="${TEST_TMPDIR%/}"
  # Hardcoded denylist + explicit $HOME check. Most short denylist entries
  # are also caught by the length floor below — keeping them explicit gives
  # a more useful error and protects against marker-check bypass. $HOME is
  # long enough to slip past the length check, so this is the one entry
  # that adds genuinely new coverage rather than defense-in-depth.
  local denied
  for denied in "${_TEST_RM_TMPDIR_DENYLIST[@]}" "${HOME:-/dev/null/never-matches}"; do
    if [[ "$tmpdir" == "$denied" ]]; then
      echo "_test_rm refused: TEST_TMPDIR is a known-dangerous path: $tmpdir" >&2
      return 1
    fi
  done
  # Real mktemp -d results are 20+ chars on macOS (/var/folders/...) and
  # ~20 chars on Linux (/tmp/tmp.XXXXXX). Anything under 16 is suspicious
  # — for example "/" (1) or "/tmp" (4) — and would scope deletion far
  # too broadly. The threshold is generous to leave room for short tmp
  # roots while still catching obvious accidents.
  if [[ "${#tmpdir}" -lt 16 ]]; then
    echo "_test_rm refused: TEST_TMPDIR suspiciously short (${#tmpdir} chars): $tmpdir" >&2
    return 1
  fi
  # Catches typos and stale state — e.g. if TEST_TMPDIR was already cleaned
  # up by an earlier teardown but the variable still holds the old path.
  if [[ ! -d "$tmpdir" ]]; then
    echo "_test_rm refused: TEST_TMPDIR is not a directory: $tmpdir" >&2
    return 1
  fi
  # -L returns true when the path is a symbolic link. mktemp -d creates a
  # real directory, so a symlinked TEST_TMPDIR is suspicious: if it points
  # at /Users/me, the marker check would follow the link and pass (assuming
  # a marker happens to live there), then rm -rf would delete real user
  # files through the link. Refuse outright.
  if [[ -L "$tmpdir" ]]; then
    echo "_test_rm refused: TEST_TMPDIR is a symlink: $tmpdir" >&2
    return 1
  fi
  # Proof-of-ownership: the marker file is dropped by setup_test_workspace
  # right after mktemp. Without it, we can't tell apart a real test sandbox
  # from a directory the user happens to have at this path.
  if [[ ! -f "$tmpdir/$_TEST_SANDBOX_MARKER" ]]; then
    echo "_test_rm refused: TEST_TMPDIR has no sandbox marker — not created by setup_test_workspace: $tmpdir" >&2
    return 1
  fi

  # ── Containment check (string-prefix) ──────────────────────
  if [[ "$path" != "$tmpdir" && "$path" != "$tmpdir/"* ]]; then
    echo "_test_rm refused: path outside TEST_TMPDIR: $path (TEST_TMPDIR=$tmpdir)" >&2
    return 1
  fi

  # ── Symlink-escape check (canonical containment) ───────────
  # The string check above can be defeated by a symlink anywhere on the
  # path — e.g. $TEST_TMPDIR/escape -> /Users/me. Canonicalize both sides
  # with realpath (resolves all symlinks) and re-check. If either resolve
  # fails (path doesn't exist yet, etc.), fall back to the string check —
  # we've already verified the string form is inside TEST_TMPDIR.
  if command -v realpath >/dev/null 2>&1; then
    local real_path real_tmpdir
    real_path="$(realpath "$path" 2>/dev/null || true)"
    real_tmpdir="$(realpath "$tmpdir" 2>/dev/null || true)"
    if [[ -n "$real_path" && -n "$real_tmpdir" ]]; then
      if [[ "$real_path" != "$real_tmpdir" && "$real_path" != "$real_tmpdir/"* ]]; then
        echo "_test_rm refused: canonical path escapes TEST_TMPDIR via symlink: $real_path (from $path)" >&2
        return 1
      fi
    fi
  fi

  # `command rm` bypasses any user-level `rm` alias or shell function — if
  # someone shadowed rm (e.g. `alias rm='rm -i'` or a hostile function),
  # we'd silently lose our safety guarantees. `command` skips alias/function
  # lookup and goes straight to the builtin/external binary.
  # `--` ends option parsing so a path beginning with "-" (already refused
  # by the absolute-path check above, but defense-in-depth) can't be
  # interpreted as an rm flag.
  command rm -rf -- "$path"
}

# ── Workspace fixtures ───────────────────────────────────────

setup_test_workspace() {
  TEST_TMPDIR="$(mktemp -d)"
  # Drop a sandbox-marker file so _test_rm can prove this directory was
  # created by us. Without this, _test_rm cannot tell our temp dir from a
  # real directory the user might have set TEST_TMPDIR to.
  : > "$TEST_TMPDIR/$_TEST_SANDBOX_MARKER"
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
