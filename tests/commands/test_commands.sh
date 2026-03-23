#!/usr/bin/env bash
# Tests for p-commands — the CLI command documentation viewer/generator.

# ── Helper to seed a command log with test data ───────────────

_seed_command_log() {
  local log_file="$1"
  mkdir -p "$(dirname "$log_file")"
  cat > "$log_file" <<'EOF'
{"ts":"2026-03-22T10:00:00Z","clone":"p1","cmd":"npm test","domain":"npm"}
{"ts":"2026-03-22T10:01:00Z","clone":"p1","cmd":"npm test","domain":"npm"}
{"ts":"2026-03-22T10:02:00Z","clone":"p1","cmd":"npm test","domain":"npm"}
{"ts":"2026-03-22T10:03:00Z","clone":"p2","cmd":"npm run build","domain":"npm"}
{"ts":"2026-03-22T10:04:00Z","clone":"p1","cmd":"aws s3 ls","domain":"aws"}
{"ts":"2026-03-22T10:05:00Z","clone":"p1","cmd":"aws s3 ls","domain":"aws"}
{"ts":"2026-03-22T10:06:00Z","clone":"p2","cmd":"docker build .","domain":"docker"}
{"ts":"2026-03-22T10:07:00Z","clone":"p1","cmd":"cargo test","domain":"rust"}
EOF
}

# Description: p-commands displays a frequency table of logged commands.
test_p_commands_list() {
  setup_test_workspace
  create_workspace 2

  local log="$TEST_WORKSPACE/.parallel-work/command-log.jsonl"
  _seed_command_log "$log"

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && p-commands 2>&1)

  assert_contains "$output" "npm test" "output should contain npm test"
  assert_contains "$output" "aws s3 ls" "output should contain aws s3 ls"
  assert_contains "$output" "3" "npm test should appear 3 times"

  teardown_test_workspace
}

# Description: p-commands suggest generates markdown grouped by domain.
test_p_commands_suggest() {
  setup_test_workspace
  create_workspace 2

  local log="$TEST_WORKSPACE/.parallel-work/command-log.jsonl"
  _seed_command_log "$log"

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && p-commands suggest 2>&1)

  # Should have domain headings.
  assert_contains "$output" "## AWS Commands" "should have AWS heading"
  assert_contains "$output" "## Node / npm Commands" "should have npm heading"
  assert_contains "$output" "## Docker Commands" "should have Docker heading"
  assert_contains "$output" "## Rust Commands" "should have Rust heading"
  # Should have markdown table syntax.
  assert_contains "$output" "| Command | Frequency |" "should have table header"
  assert_contains "$output" '`npm test`' "should have npm test in backticks"

  teardown_test_workspace
}

# Description: p-commands suggest filters by domain when one is specified.
test_p_commands_suggest_domain_filter() {
  setup_test_workspace
  create_workspace 2

  local log="$TEST_WORKSPACE/.parallel-work/command-log.jsonl"
  _seed_command_log "$log"

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && p-commands suggest aws 2>&1)

  assert_contains "$output" "## AWS Commands" "should have AWS heading"
  assert_contains "$output" "aws s3 ls" "should have aws command"
  assert_not_contains "$output" "npm test" "should NOT have npm commands"
  assert_not_contains "$output" "docker" "should NOT have docker commands"

  teardown_test_workspace
}

# Description: p-commands apply creates domain files in .claude/commands/.
test_p_commands_apply() {
  setup_test_workspace
  create_workspace 2

  local log="$TEST_WORKSPACE/.parallel-work/command-log.jsonl"
  _seed_command_log "$log"

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && p-commands apply 2>&1)

  # Check that domain files were created.
  # -f tests if the file exists.
  [[ -f "$TEST_WORKSPACE/p1/.claude/commands/aws.md" ]]
  assert_status_ok $? "aws.md should be created"

  [[ -f "$TEST_WORKSPACE/p1/.claude/commands/npm.md" ]]
  assert_status_ok $? "npm.md should be created"

  [[ -f "$TEST_WORKSPACE/p1/.claude/commands/docker.md" ]]
  assert_status_ok $? "docker.md should be created"

  # Verify content of aws.md.
  local aws_content
  aws_content=$(cat "$TEST_WORKSPACE/p1/.claude/commands/aws.md")
  assert_contains "$aws_content" "# AWS Commands" "aws.md should have heading"
  assert_contains "$aws_content" "aws s3 ls" "aws.md should have the command"

  # Verify CLAUDE.local.md was updated with references.
  local local_md
  local_md=$(cat "$TEST_WORKSPACE/p1/.claude/CLAUDE.local.md")
  assert_contains "$local_md" "## CLI Command References" "should have references heading"
  assert_contains "$local_md" ".claude/commands/aws.md" "should reference aws.md"

  teardown_test_workspace
}

# Description: p-commands apply with a domain filter only writes that domain.
test_p_commands_apply_single_domain() {
  setup_test_workspace
  create_workspace 2

  local log="$TEST_WORKSPACE/.parallel-work/command-log.jsonl"
  _seed_command_log "$log"

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && p-commands apply aws 2>&1)

  [[ -f "$TEST_WORKSPACE/p1/.claude/commands/aws.md" ]]
  assert_status_ok $? "aws.md should be created"

  # npm.md should NOT be created when filtering to aws only.
  [[ ! -f "$TEST_WORKSPACE/p1/.claude/commands/npm.md" ]]
  assert_status_ok $? "npm.md should NOT be created with aws filter"

  teardown_test_workspace
}

# Description: p-commands clear truncates the log file.
test_p_commands_clear() {
  setup_test_workspace
  create_workspace 2

  local log="$TEST_WORKSPACE/.parallel-work/command-log.jsonl"
  _seed_command_log "$log"

  # Verify log has content before clearing.
  local before
  before=$(wc -l < "$log" | tr -d ' ')
  assert_eq "8" "$before" "log should have 8 entries before clear"

  (cd "$TEST_WORKSPACE/p1" && p-commands clear) >/dev/null 2>&1

  local after
  after=$(wc -l < "$log" | tr -d ' ')
  assert_eq "0" "$after" "log should be empty after clear"

  teardown_test_workspace
}

# Description: p-commands domains lists unique domains from the log.
test_p_commands_domains() {
  setup_test_workspace
  create_workspace 2

  local log="$TEST_WORKSPACE/.parallel-work/command-log.jsonl"
  _seed_command_log "$log"

  local output
  output=$(cd "$TEST_WORKSPACE/p1" && p-commands domains 2>&1)

  assert_contains "$output" "aws" "should list aws domain"
  assert_contains "$output" "npm" "should list npm domain"
  assert_contains "$output" "docker" "should list docker domain"
  assert_contains "$output" "rust" "should list rust domain"

  teardown_test_workspace
}

# Description: p-commands fails gracefully when no log file exists.
test_p_commands_no_log() {
  setup_test_workspace
  create_workspace 2

  local output status
  output=$(cd "$TEST_WORKSPACE/p1" && p-commands 2>&1)
  status=$?

  assert_status_fail "$status" "should fail when no log exists"
  assert_contains "$output" "No command log found" "should report missing log"

  teardown_test_workspace
}

# Description: p-commands shows usage for unknown subcommands.
test_p_commands_usage() {
  setup_test_workspace
  create_workspace 2

  local output status
  output=$(cd "$TEST_WORKSPACE/p1" && p-commands invalid 2>&1)
  status=$?

  assert_status_fail "$status" "should fail on invalid subcommand"
  assert_contains "$output" "Usage" "should show usage"

  teardown_test_workspace
}
