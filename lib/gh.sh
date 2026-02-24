#!/usr/bin/env bash
# GitHub CLI helpers: gh availability check and PR branch fetching.

# Print warning if gh CLI is not installed; returns 1.
_pwork_check_gh() {
  if ! command -v gh &>/dev/null; then
    echo "Note: gh CLI not found — PR status unavailable. Install: https://cli.github.com/" >&2
    return 1
  fi
  return 0
}

# Fetch merged and open PR branch lists into caller variables.
# Usage: _pwork_fetch_pr_branches <clone_dir> <repo_slug> <merged_var> <open_var>
_pwork_fetch_pr_branches() {
  local clone_dir="$1" repo_slug="$2" merged_var="$3" open_var="$4"
  local _merged _open
  _merged=$(cd "$clone_dir" && gh pr list --repo "$repo_slug" \
    --state merged --limit 100 --json headRefName --jq '.[].headRefName' 2>/dev/null)
  _open=$(cd "$clone_dir" && gh pr list --repo "$repo_slug" \
    --state open --json headRefName --jq '.[].headRefName' 2>/dev/null)
  eval "$merged_var=\$_merged"
  eval "$open_var=\$_open"
}

# Return a status label for a branch given merged/open branch lists.
_pwork_branch_status() {
  local branch="$1" default_branch="$2" merged_branches="$3" open_branches="$4"
  if [[ "$branch" == "$default_branch" ]]; then
    echo "available for new work"
  elif echo "$merged_branches" | grep -qx "$branch"; then
    echo "PR merged"
  elif echo "$open_branches" | grep -qx "$branch"; then
    echo "PR open"
  else
    echo "no PR"
  fi
}
