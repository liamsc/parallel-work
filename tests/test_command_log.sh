#!/usr/bin/env bash
# Tests for lib/command-log.sh — the PostToolUse hook that logs CLI commands.

# Description: Hook filters out navigation commands (cd, ls, pwd).
test_hook_filters_navigation() {
  local hook="$SCRIPT_DIR/lib/command-log.sh"
  local tmpdir
  tmpdir=$(mktemp -d)
  local log="$tmpdir/.claude/command-log.jsonl"
  mkdir -p "$tmpdir/.claude"

  # Feed a "cd" command — should be filtered out.
  echo '{"tool_input":{"command":"cd /tmp"}}' | (cd "$tmpdir" && bash "$hook")
  # -f tests if the file exists.
  if [[ -f "$log" ]]; then
    local lines
    lines=$(wc -l < "$log")
    assert_eq "0" "$lines" "cd should be filtered out"
  fi

  # Feed an "ls" command — should be filtered out.
  echo '{"tool_input":{"command":"ls -la"}}' | (cd "$tmpdir" && bash "$hook")
  if [[ -f "$log" ]]; then
    local lines
    lines=$(wc -l < "$log")
    assert_eq "0" "$lines" "ls should be filtered out"
  fi

  rm -rf "$tmpdir"
}

# Description: Hook filters out simple git read commands (git status, git log).
test_hook_filters_git_reads() {
  local hook="$SCRIPT_DIR/lib/command-log.sh"
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/.claude"
  local log="$tmpdir/.claude/command-log.jsonl"

  for cmd in "git status" "git log --oneline" "git diff" "git branch -a" "git show HEAD"; do
    echo "{\"tool_input\":{\"command\":\"$cmd\"}}" | (cd "$tmpdir" && bash "$hook")
  done

  if [[ -f "$log" ]]; then
    local lines
    lines=$(wc -l < "$log")
    assert_eq "0" "$lines" "git read commands should be filtered out"
  fi

  rm -rf "$tmpdir"
}

# Description: Hook logs meaningful commands like npm test and cargo build.
test_hook_logs_meaningful_commands() {
  local hook="$SCRIPT_DIR/lib/command-log.sh"
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/.claude"
  local log="$tmpdir/.claude/command-log.jsonl"

  echo '{"tool_input":{"command":"npm test"}}' | (cd "$tmpdir" && bash "$hook")
  echo '{"tool_input":{"command":"cargo build --release"}}' | (cd "$tmpdir" && bash "$hook")

  assert_eq "2" "$(wc -l < "$log" | tr -d ' ')" "should log 2 commands"

  # Verify first entry is valid JSON with expected fields.
  local first
  first=$(head -1 "$log")
  assert_contains "$first" '"cmd":"npm test"' "first entry should contain npm test"
  assert_contains "$first" '"domain":"npm"' "npm test should have npm domain"

  local second
  second=$(tail -1 "$log")
  assert_contains "$second" '"cmd":"cargo build --release"' "second entry should contain cargo build"
  assert_contains "$second" '"domain":"rust"' "cargo should have rust domain"

  rm -rf "$tmpdir"
}

# Description: Hook tags commands with correct domains.
test_hook_domain_tagging() {
  local hook="$SCRIPT_DIR/lib/command-log.sh"
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/.claude"
  local log="$tmpdir/.claude/command-log.jsonl"

  # Test several domain mappings.
  local -A expected_domains=(
    ["aws s3 ls"]="aws"
    ["docker build ."]="docker"
    ["pip install requests"]="python"
    ["go test ./..."]="go"
    ["terraform plan"]="infra"
    ["make all"]="build"
    ["kubectl get pods"]="infra"
    ["git push origin main"]="git"
    ["./test.sh"]="general"
  )

  for cmd in "${!expected_domains[@]}"; do
    echo "{\"tool_input\":{\"command\":\"$cmd\"}}" | (cd "$tmpdir" && bash "$hook")
  done

  # Check each domain tag.
  for cmd in "${!expected_domains[@]}"; do
    local expected="${expected_domains[$cmd]}"
    local actual
    actual=$(jq -r --arg c "$cmd" 'select(.cmd == $c) | .domain' "$log")
    assert_eq "$expected" "$actual" "domain for '$cmd'"
  done

  rm -rf "$tmpdir"
}

# Description: Hook produces valid JSONL with required fields.
test_hook_jsonl_format() {
  local hook="$SCRIPT_DIR/lib/command-log.sh"
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/.claude"
  local log="$tmpdir/.claude/command-log.jsonl"

  echo '{"tool_input":{"command":"npm run build"}}' | (cd "$tmpdir" && bash "$hook")

  local entry
  entry=$(cat "$log")

  # jq -e exits non-zero if expression is false/null.
  echo "$entry" | jq -e '.ts' >/dev/null 2>&1
  assert_status_ok $? "entry should have ts field"

  echo "$entry" | jq -e '.cmd' >/dev/null 2>&1
  assert_status_ok $? "entry should have cmd field"

  echo "$entry" | jq -e '.domain' >/dev/null 2>&1
  assert_status_ok $? "entry should have domain field"

  echo "$entry" | jq -e '.clone' >/dev/null 2>&1
  assert_status_ok $? "entry should have clone field"

  rm -rf "$tmpdir"
}

# Description: Hook writes to pwork workspace log when inside a workspace.
test_hook_writes_to_workspace_log() {
  setup_test_workspace
  create_workspace 2

  local hook="$SCRIPT_DIR/lib/command-log.sh"
  local expected_log="$TEST_WORKSPACE/.parallel-work/command-log.jsonl"

  echo '{"tool_input":{"command":"npm test"}}' | (cd "$TEST_WORKSPACE/p1" && bash "$hook")

  # -f tests if file exists.
  [[ -f "$expected_log" ]]
  assert_status_ok $? "log should be written to workspace .parallel-work/"

  local entry
  entry=$(cat "$expected_log")
  assert_contains "$entry" '"clone":"p1"' "clone should be p1"

  teardown_test_workspace
}

# Description: Hook skips empty commands gracefully.
test_hook_skips_empty_command() {
  local hook="$SCRIPT_DIR/lib/command-log.sh"
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/.claude"
  local log="$tmpdir/.claude/command-log.jsonl"

  # Empty command field.
  echo '{"tool_input":{"command":""}}' | (cd "$tmpdir" && bash "$hook")
  # Missing command field.
  echo '{"tool_input":{}}' | (cd "$tmpdir" && bash "$hook")

  if [[ -f "$log" ]]; then
    local lines
    lines=$(wc -l < "$log" | tr -d ' ')
    assert_eq "0" "$lines" "empty commands should not be logged"
  fi

  rm -rf "$tmpdir"
}
