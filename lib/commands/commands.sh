#!/usr/bin/env bash
# p-commands — view, suggest, and apply CLI command documentation from hook logs.
#
# The command-log.sh hook captures commands run during Claude Code sessions.
# This command reads that JSONL log and helps turn it into documentation that
# future sessions can use, organized by domain (aws, docker, npm, etc.).

# ── Helpers ───────────────────────────────────────────────────

# Find the JSONL log file — pwork workspace or git-root fallback.
_pwork_command_log_path() {
  local root
  root="$(_pwork_root 2>/dev/null)" && {
    echo "$root/.parallel-work/command-log.jsonl"
    return 0
  }
  # Fallback: git root or cwd.
  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -n "$git_root" ]]; then
    echo "$git_root/.claude/command-log.jsonl"
  else
    echo "$PWD/.claude/command-log.jsonl"
  fi
}

# Pretty-print a domain name for markdown headings (e.g. "aws" → "AWS").
_pwork_domain_label() {
  case "$1" in
    aws)     echo "AWS" ;;
    docker)  echo "Docker" ;;
    npm)     echo "Node / npm" ;;
    python)  echo "Python" ;;
    rust)    echo "Rust" ;;
    go)      echo "Go" ;;
    git)     echo "Git" ;;
    infra)   echo "Infrastructure" ;;
    build)   echo "Build" ;;
    test)    echo "Test" ;;
    general) echo "General" ;;
    *)       echo "$1" ;;
  esac
}

# ── Subcommands ───────────────────────────────────────────────

# Show a frequency-sorted table of all logged commands.
_pwork_commands_list() {
  local log_file
  log_file="$(_pwork_command_log_path)"

  if [[ ! -f "$log_file" ]]; then
    echo "No command log found at $log_file" >&2
    echo "Run some commands with the command-log hook enabled first." >&2
    return 1
  fi

  echo "Logged commands (most frequent first):"
  echo ""
  # jq extracts cmd+domain; sort | uniq -c counts; sort -rn orders by frequency.
  printf "  %-6s %-12s %s\n" "COUNT" "DOMAIN" "COMMAND"
  printf "  %-6s %-12s %s\n" "-----" "------" "-------"
  jq -r '[.domain, .cmd] | @tsv' "$log_file" \
    | sort | uniq -c | sort -rn \
    | while read -r count domain cmd; do
        printf "  %-6s %-12s %s\n" "$count" "$domain" "$cmd"
      done
}

# Print markdown documentation to stdout, grouped by domain.
_pwork_commands_suggest() {
  local log_file filter_domain="${1:-}"
  log_file="$(_pwork_command_log_path)"

  if [[ ! -f "$log_file" ]]; then
    echo "No command log found at $log_file" >&2
    return 1
  fi

  # Get unique domains from the log, optionally filtered.
  local domains
  if [[ -n "$filter_domain" ]]; then
    domains="$filter_domain"
  else
    domains=$(jq -r '.domain' "$log_file" | sort -u)
  fi

  local first=true
  for domain in $domains; do
    local label
    label="$(_pwork_domain_label "$domain")"

    # Get commands for this domain, sorted by frequency.
    local entries
    entries=$(jq -r --arg d "$domain" 'select(.domain == $d) | .cmd' "$log_file" \
      | sort | uniq -c | sort -rn)

    # -z tests if the string is zero-length.
    [[ -z "$entries" ]] && continue

    # Blank line between sections (not before the first one).
    [[ "$first" == "true" ]] || echo ""
    first=false

    echo "## $label Commands"
    echo ""
    echo "| Command | Frequency |"
    echo "|---------|-----------|"
    echo "$entries" | while read -r count cmd; do
      # Backtick-wrap the command for markdown code formatting.
      echo "| \`$cmd\` | $count |"
    done
  done
}

# Write domain files to .claude/rules/commands/ — Claude Code auto-discovers
# all *.md files under .claude/rules/ so no CLAUDE.local.md wiring is needed.
_pwork_commands_apply() {
  local log_file filter_domain="${1:-}"
  log_file="$(_pwork_command_log_path)"

  if [[ ! -f "$log_file" ]]; then
    echo "No command log found at $log_file" >&2
    return 1
  fi

  # Determine the project root for writing .claude/rules/commands/ files.
  local project_root
  project_root="$(_pwork_root 2>/dev/null)" || {
    project_root=$(git rev-parse --show-toplevel 2>/dev/null) || project_root="$PWD"
  }

  local commands_dir="$project_root/.claude/rules/commands"
  mkdir -p "$commands_dir"

  # Get domains to process.
  local domains
  if [[ -n "$filter_domain" ]]; then
    domains="$filter_domain"
  else
    domains=$(jq -r '.domain' "$log_file" | sort -u)
  fi

  for domain in $domains; do
    local label
    label="$(_pwork_domain_label "$domain")"
    local domain_file="$commands_dir/$domain.md"

    # Get commands for this domain, sorted by frequency.
    local entries
    entries=$(jq -r --arg d "$domain" 'select(.domain == $d) | .cmd' "$log_file" \
      | sort | uniq -c | sort -rn)

    [[ -z "$entries" ]] && continue

    # Write the domain file.
    {
      echo "# $label Commands"
      echo ""
      echo "Commonly-used CLI commands captured from development sessions."
      echo ""
      echo "| Command | Frequency |"
      echo "|---------|-----------|"
      echo "$entries" | while read -r count cmd; do
        echo "| \`$cmd\` | $count |"
      done
    } > "$domain_file"

    echo "  Wrote $domain_file"
  done
}

# List domains that have logged commands.
_pwork_commands_domains() {
  local log_file
  log_file="$(_pwork_command_log_path)"

  if [[ ! -f "$log_file" ]]; then
    echo "No command log found." >&2
    return 1
  fi

  jq -r '.domain' "$log_file" | sort -u
}

# ── Main entry point ──────────────────────────────────────────

p-commands() {
  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required for p-commands" >&2
    return 1
  fi

  local subcmd="${1:-}"
  case "$subcmd" in
    "")       _pwork_commands_list ;;
    suggest)  shift; _pwork_commands_suggest "$@" ;;
    apply)    shift; _pwork_commands_apply "$@" ;;
    clear)
      local log_file
      log_file="$(_pwork_command_log_path)"
      # Truncate the file — > redirects nothing into it, emptying it.
      > "$log_file"
      echo "Cleared $log_file"
      ;;
    domains)  _pwork_commands_domains ;;
    *)
      echo "Usage: p-commands [suggest|apply|clear|domains] [domain]" >&2
      return 1
      ;;
  esac
}
