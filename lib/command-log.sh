#!/usr/bin/env bash
# PostToolUse hook for Bash — logs CLI commands to a JSONL file for later
# analysis by `p-commands`. Designed to be fast: filter + append only.
#
# Claude Code pipes JSON to stdin with tool_input.command after each Bash call.
# We extract the command, skip noise (cd, ls, git status, etc.), tag a domain
# (aws, docker, npm, etc.), and append one JSONL line to the log.

# -u treats unset variables as errors; pipefail catches failures in pipes.
set -uo pipefail

# Bail out silently if jq isn't installed — logging is non-critical.
# command -v checks if a command exists without running it.
command -v jq &>/dev/null || exit 0

# Read all of stdin (JSON from Claude Code) into a variable.
input=$(cat)

# Extract the command that was run.
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

# Nothing to log if the command is empty.
# -z tests if the string is zero-length.
[[ -z "$cmd" ]] && exit 0

# ── Noise filter ──────────────────────────────────────────────
# Strip the first word from the command for matching.
# ${cmd%% *} removes everything after the first space.
first_word="${cmd%% *}"

# Commands that are pure navigation / inspection — never interesting.
case "$first_word" in
  cd|ls|pwd|cat|head|tail|echo|printf|wc|which|type|file|mkdir|touch|cp|mv|rm|less|more|tree|stat|realpath|dirname|basename|env|export|source|true|false|test|"[")
    exit 0 ;;
esac

# Git sub-commands that are read-only / trivial — skip them.
if [[ "$first_word" == "git" ]]; then
  # Extract the git subcommand (second word).
  git_sub=$(echo "$cmd" | awk '{print $2}')
  case "$git_sub" in
    status|log|diff|branch|show|stash|remote|config|rev-parse|describe|tag|shortlog|blame|reflog)
      exit 0 ;;
  esac
fi

# ── Domain tagging ────────────────────────────────────────────
# Match the command prefix to a domain for later grouping.
domain="general"
case "$first_word" in
  aws|sam|cdk)                        domain="aws" ;;
  docker|docker-compose|podman)       domain="docker" ;;
  npm|npx|yarn|pnpm)                  domain="npm" ;;
  pip|pip3|python|python3|pytest|poetry|uv|ruff|mypy|black|isort)
                                      domain="python" ;;
  cargo|rustc|rustup)                 domain="rust" ;;
  go)                                 domain="go" ;;
  git)                                domain="git" ;;
  terraform|kubectl|helm|pulumi)      domain="infra" ;;
  make|cmake|ninja)                   domain="build" ;;
  # Try to detect test runners
  jest|vitest|mocha|phpunit|rspec|bundle)
                                      domain="test" ;;
esac

# ── Find log location ────────────────────────────────────────
# Walk up from cwd to find a pwork workspace; fall back to git root or cwd.
log_file=""
clone_name=""
dir="$PWD"

# Check for pwork workspace.
while [[ "$dir" != "/" ]]; do
  if [[ -f "$dir/.parallel-work/pwork.conf" ]]; then
    log_file="$dir/.parallel-work/command-log.jsonl"
    break
  fi
  # Detect clone name (pN directory) while walking up.
  base="$(basename "$dir")"
  # p[0-9]* matches directory names like p1, p2, p10, etc.
  if [[ "$base" =~ ^p[0-9]+$ && -z "$clone_name" ]]; then
    clone_name="$base"
  fi
  dir="$(dirname "$dir")"
done

# Fallback: use .claude/ in the git root, or cwd.
if [[ -z "$log_file" ]]; then
  git_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -n "$git_root" ]]; then
    mkdir -p "$git_root/.claude"
    log_file="$git_root/.claude/command-log.jsonl"
  else
    mkdir -p "$PWD/.claude"
    log_file="$PWD/.claude/command-log.jsonl"
  fi
fi

# ── Append JSONL entry ────────────────────────────────────────
# Build a compact JSON line with jq to ensure proper escaping.
ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq -cn \
  --arg ts "$ts" \
  --arg clone "$clone_name" \
  --arg cmd "$cmd" \
  --arg domain "$domain" \
  '{ts: $ts, clone: $clone, cmd: $cmd, domain: $domain}' \
  >> "$log_file"
