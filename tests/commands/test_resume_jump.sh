#!/usr/bin/env bash
# Tests for window-jump in p-resume: live-session detection, listing markers,
# and dispatch (jump-vs-launch with --force-new escape hatch).

# ── Local helpers ────────────────────────────────────────────

# Override the Claude sessions metadata dir so tests don't read or write the
# user's real ~/.claude/sessions.
_jump_setup_storage() {
  export PWORK_CLAUDE_SESSIONS_DIR="$TEST_TMPDIR/.claude-sessions"
  mkdir -p "$PWORK_CLAUDE_SESSIONS_DIR"
}

_jump_teardown_storage() {
  unset PWORK_CLAUDE_SESSIONS_DIR
}

# Spawn a long sleep so we have a *real* live PID to test against. Caller
# stores the pid (assigned to REPLY) and is responsible for `kill`-ing it.
_jump_spawn_live_pid() {
  sleep 60 &
  REPLY=$!
}

# Write a fake Claude session metadata file at <pid>.json. Mirrors the real
# schema (~/.claude/sessions/<pid>.json) closely enough for our scanner.
_jump_seed_session_meta() {
  local pid="$1" sid="$2" cwd="${3:-/tmp/fake-cwd}"
  # Use a heredoc — keeps the JSON readable and avoids quoting headaches.
  cat > "$PWORK_CLAUDE_SESSIONS_DIR/$pid.json" <<EOF
{"pid":$pid,"sessionId":"$sid","cwd":"$cwd","startedAt":1,"updatedAt":2}
EOF
}

# ── Tests ────────────────────────────────────────────────────

# Description: live-claude-sessions scanner emits the live session and drops dead PIDs.
test_jump_live_claude_sessions_filters_dead_pids() {
  setup_test_workspace
  _jump_setup_storage

  # Real live PID via a short-lived sleep.
  _jump_spawn_live_pid
  local live_pid=$REPLY
  _jump_seed_session_meta "$live_pid" "live-session-id" "/tmp/live"

  # 99999999 is reliably unallocated on macOS — passes as a "dead" PID.
  _jump_seed_session_meta "99999999" "dead-session-id" "/tmp/dead"

  local output
  output=$(_pwork_jump_live_claude_sessions)

  # Clean up the sleep before assertions so the process doesn't leak even on failure.
  kill "$live_pid" 2>/dev/null

  assert_contains "$output" "live-session-id" "live session emitted" || { _jump_teardown_storage; teardown_test_workspace; return 1; }
  assert_not_contains "$output" "dead-session-id" "dead PID's session filtered out" || { _jump_teardown_storage; teardown_test_workspace; return 1; }

  _jump_teardown_storage
  teardown_test_workspace
}

# Description: scanner returns empty (no error) when the metadata dir doesn't exist.
test_jump_live_claude_sessions_missing_dir() {
  setup_test_workspace

  export PWORK_CLAUDE_SESSIONS_DIR="$TEST_TMPDIR/nonexistent"
  local output
  output=$(_pwork_jump_live_claude_sessions)
  assert_eq "" "$output" "empty when sessions dir is missing"
  unset PWORK_CLAUDE_SESSIONS_DIR

  teardown_test_workspace
}

# Description: _pwork_jump_pid_terminal walks the ppid chain and identifies iTerm2.
test_jump_pid_terminal_identifies_iterm2() {
  setup_test_workspace

  # Stub ps with a fake process tree: 100 (zsh) -> 200 (iTerm2) -> 1 (init).
  # case "$*" matches against the args joined with spaces.
  ps() {
    case "$*" in
      "-o ppid= -p 100") echo "200" ;;
      "-o ppid= -p 200") echo "1"   ;;
      "-o comm= -p 100") echo "-zsh" ;;
      "-o comm= -p 200") echo "/Applications/iTerm.app/Contents/MacOS/iTerm2" ;;
      *) command ps "$@" ;;
    esac
  }

  local result
  result=$(_pwork_jump_pid_terminal 100)
  assert_eq "iterm2" "$result" "iTerm2 detected from ancestor process"

  unset -f ps
  teardown_test_workspace
}

# Description: _pwork_jump_pid_terminal identifies Ghostty in the same way.
test_jump_pid_terminal_identifies_ghostty() {
  setup_test_workspace

  ps() {
    case "$*" in
      "-o ppid= -p 100") echo "200" ;;
      "-o ppid= -p 200") echo "1"   ;;
      "-o comm= -p 100") echo "-zsh" ;;
      "-o comm= -p 200") echo "/Applications/Ghostty.app/Contents/MacOS/ghostty" ;;
      *) command ps "$@" ;;
    esac
  }

  local result
  result=$(_pwork_jump_pid_terminal 100)
  assert_eq "ghostty" "$result" "Ghostty detected from ancestor process"

  unset -f ps
  teardown_test_workspace
}

# Description: _pwork_jump_pid_terminal returns "detached" when the chain reaches launchd (no parent terminal).
# Real-world case: `cursor-agent` daemonizes itself so its parent becomes
# pid 1. Distinguishing this from "unknown terminal app" matters because
# detached → launch fresh (no window to focus); unknown → warn the user.
test_jump_pid_terminal_detached_returns_detached() {
  setup_test_workspace

  ps() {
    case "$*" in
      "-o ppid= -p 100") echo "1" ;;
      "-o comm= -p 100") echo "some-daemon" ;;
      *) command ps "$@" ;;
    esac
  }

  local result
  result=$(_pwork_jump_pid_terminal 100)
  assert_eq "detached" "$result" "chain reaching launchd → detached" || { unset -f ps; teardown_test_workspace; return 1; }

  unset -f ps
  teardown_test_workspace
}

# Description: _pwork_jump_pid_terminal returns "unknown" when the chain walks through unrecognized apps without reaching launchd.
# Real-world case: terminal apps we don't have AppleScript focus support
# for (alacritty, kitty, wezterm). The session IS in a window the user
# could find — caller should warn rather than launch a duplicate.
test_jump_pid_terminal_unknown_terminal_app() {
  setup_test_workspace

  # Chain: 100 → 200 (alacritty) → ps fails (process gone). Loop exits
  # with pid="" (not "1"), so we fall to the "unknown" branch.
  ps() {
    case "$*" in
      "-o ppid= -p 100") echo "200" ;;
      "-o comm= -p 100") echo "-zsh" ;;
      "-o ppid= -p 200") echo "" ;;
      "-o comm= -p 200") echo "alacritty" ;;
      *) command ps "$@" ;;
    esac
  }

  local result
  result=$(_pwork_jump_pid_terminal 100)
  assert_eq "unknown" "$result" "unrecognized terminal app → unknown" || { unset -f ps; teardown_test_workspace; return 1; }

  unset -f ps
  teardown_test_workspace
}

# Description: _pwork_jump_window returns non-zero (launch fresh) for a live cursor session whose process is detached.
# Real-world case: cursor-agent daemonizes itself, so its parent is
# launchd. Returning 0 here would print "switch manually" and refuse to
# launch — leaving the user stuck because there's no terminal window
# to switch to. We want the caller to launch a fresh resume instead.
test_jump_window_detached_cursor_returns_failure() {
  setup_test_workspace
  _jump_setup_storage

  # Spawn a real live PID so pgrep can find it.
  _jump_spawn_live_pid
  local live_pid=$REPLY

  # Stub _pwork_jump_live_cursor_pid to return our live pid for a known sid.
  # Stub _pwork_jump_pid_terminal to simulate the detached classification
  # that _pwork_jump_pid_terminal would return for a real cursor-agent.
  _pwork_jump_live_cursor_pid() { echo "$live_pid"; }
  _pwork_jump_pid_terminal()    { echo "detached"; }

  local status
  _pwork_jump_window "fake-cursor-sid" "cursor" "/tmp/fake-cwd" >/dev/null 2>&1
  status=$?

  kill "$live_pid" 2>/dev/null
  unset -f _pwork_jump_live_cursor_pid _pwork_jump_pid_terminal

  assert_status_fail "$status" "detached cursor session → caller launches fresh" || { _jump_teardown_storage; teardown_test_workspace; return 1; }

  _jump_teardown_storage
  teardown_test_workspace
}

# Description: _pwork_jump_window returns 0 (refuse-to-duplicate) for an unknown but real terminal app.
# Distinct from `detached`: the user IS in a terminal window (alacritty,
# kitty, etc.) we just can't AppleScript-focus. Launching a duplicate
# would visibly nest two agents — refuse and tell the user to switch.
test_jump_window_unknown_terminal_refuses_launch() {
  setup_test_workspace
  _jump_setup_storage

  _jump_spawn_live_pid
  local live_pid=$REPLY

  _pwork_jump_live_cursor_pid() { echo "$live_pid"; }
  _pwork_jump_pid_terminal()    { echo "unknown"; }

  local output status
  output=$(_pwork_jump_window "fake-cursor-sid" "cursor" "/tmp/fake-cwd" 2>&1)
  status=$?

  kill "$live_pid" 2>/dev/null
  unset -f _pwork_jump_live_cursor_pid _pwork_jump_pid_terminal

  assert_status_ok "$status" "unknown-but-real terminal → refuse to launch new" || { _jump_teardown_storage; teardown_test_workspace; return 1; }
  assert_contains "$output" "switch manually" "user told to switch manually" || { _jump_teardown_storage; teardown_test_workspace; return 1; }

  _jump_teardown_storage
  teardown_test_workspace
}

# Description: _pwork_jump_window returns non-zero when no live process matches the session id.
test_jump_window_no_live_session_returns_failure() {
  setup_test_workspace
  _jump_setup_storage

  # Empty metadata dir — no session file matches.
  local status
  _pwork_jump_window "nonexistent-session-id" "claude" "/tmp/foo" >/dev/null 2>&1
  status=$?
  assert_status_fail "$status" "_pwork_jump_window returns non-zero when session is closed"

  _jump_teardown_storage
  teardown_test_workspace
}

# Description: p-resume listing shows ● next to live sessions and prints the hint.
test_p_resume_listing_marks_live_session() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage
  _jump_setup_storage

  _seed_claude_session "$TEST_WORKSPACE/p1" "live-id"   "Live session"   "202604281000"
  _seed_claude_session "$TEST_WORKSPACE/p2" "closed-id" "Closed session" "202604280900"

  _jump_spawn_live_pid
  local live_pid=$REPLY
  _jump_seed_session_meta "$live_pid" "live-id" "$TEST_WORKSPACE/p1"

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && echo "" | p-resume 2>&1)

  kill "$live_pid" 2>/dev/null

  assert_contains "$output" "currently open" "hint header shown when a row is live" || { _jump_teardown_storage; _resume_teardown_storage; teardown_test_workspace; return 1; }
  assert_contains "$output" "●" "● glyph appears in listing" || { _jump_teardown_storage; _resume_teardown_storage; teardown_test_workspace; return 1; }

  _jump_teardown_storage
  _resume_teardown_storage
  teardown_test_workspace
}

# Description: when no rows are live, the listing omits the hint header.
test_p_resume_no_live_no_hint() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage
  _jump_setup_storage

  _seed_claude_session "$TEST_WORKSPACE/p1" "closed-id" "Just closed" "202604281000"
  # No metadata seeded → no live sessions.

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && echo "" | p-resume 2>&1)

  assert_not_contains "$output" "currently open" "no hint when nothing is live"

  _jump_teardown_storage
  _resume_teardown_storage
  teardown_test_workspace
}

# Description: selecting a live session calls _pwork_jump_window and skips claude launch.
test_p_resume_open_session_jumps_not_launches() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage
  _jump_setup_storage

  _seed_claude_session "$TEST_WORKSPACE/p1" "open-id" "Open one" "202604281200"
  _jump_spawn_live_pid
  local live_pid=$REPLY
  _jump_seed_session_meta "$live_pid" "open-id" "$TEST_WORKSPACE/p1"

  local stub_log="$TEST_TMPDIR/stub.log"
  # Subshell scopes the stubs and any cd to this test only.
  (
    cd "$TEST_WORKSPACE/p1"
    _pwork_jump_window() { printf 'jump: sid=%s tool=%s cwd=%s\n' "$1" "$2" "$3" >> "$stub_log"; return 0; }
    claude() { printf 'claude args=%s\n' "$*" >> "$stub_log"; }
    p-resume 1 >/dev/null 2>&1
  )

  kill "$live_pid" 2>/dev/null

  local logged
  logged=$(cat "$stub_log" 2>/dev/null)

  assert_contains "$logged" "jump: sid=open-id" "jump function called with the right session id" || { _jump_teardown_storage; _resume_teardown_storage; teardown_test_workspace; return 1; }
  assert_not_contains "$logged" "claude args=" "claude launch was skipped" || { _jump_teardown_storage; _resume_teardown_storage; teardown_test_workspace; return 1; }

  _jump_teardown_storage
  _resume_teardown_storage
  teardown_test_workspace
}

# Description: --force-new bypasses jump dispatch even when the session is live.
test_p_resume_force_new_bypasses_jump() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage
  _jump_setup_storage

  _seed_claude_session "$TEST_WORKSPACE/p1" "open-id-2" "Open" "202604281200"
  _jump_spawn_live_pid
  local live_pid=$REPLY
  _jump_seed_session_meta "$live_pid" "open-id-2" "$TEST_WORKSPACE/p1"

  local stub_log="$TEST_TMPDIR/stub.log"
  (
    cd "$TEST_WORKSPACE/p1"
    _pwork_jump_window() { printf 'jump-called\n' >> "$stub_log"; return 0; }
    claude() { printf 'claude args=%s\n' "$*" >> "$stub_log"; }
    p-resume 1 --force-new >/dev/null 2>&1
  )

  kill "$live_pid" 2>/dev/null

  local logged
  logged=$(cat "$stub_log" 2>/dev/null)

  assert_not_contains "$logged" "jump-called" "jump function NOT called under --force-new" || { _jump_teardown_storage; _resume_teardown_storage; teardown_test_workspace; return 1; }
  assert_contains "$logged" "claude args=" "claude launched directly" || { _jump_teardown_storage; _resume_teardown_storage; teardown_test_workspace; return 1; }
  assert_contains "$logged" "open-id-2" "correct session id passed to claude" || { _jump_teardown_storage; _resume_teardown_storage; teardown_test_workspace; return 1; }

  _jump_teardown_storage
  _resume_teardown_storage
  teardown_test_workspace
}

# Description: closed session falls through to launch (preserves existing behavior).
test_p_resume_closed_session_launches() {
  setup_test_workspace
  create_workspace 2
  _resume_setup_storage
  _jump_setup_storage  # empty metadata dir → nothing is "live"

  _seed_claude_session "$TEST_WORKSPACE/p1" "closed-only" "Closed only" "202604281200"

  local stub_log="$TEST_TMPDIR/stub.log"
  (
    cd "$TEST_WORKSPACE/p1"
    claude() { printf 'claude args=%s\n' "$*" >> "$stub_log"; }
    p-resume 1 >/dev/null 2>&1
  )

  local logged
  logged=$(cat "$stub_log" 2>/dev/null)

  assert_contains "$logged" "closed-only" "claude launched for closed session"
  assert_contains "$logged" "--dangerously-skip-permissions" "bypass-permissions flag still passed"

  _jump_teardown_storage
  _resume_teardown_storage
  teardown_test_workspace
}
