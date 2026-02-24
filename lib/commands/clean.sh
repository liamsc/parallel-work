#!/usr/bin/env bash
# p-clean: recycle clones whose PR has been merged.

p-clean() {
  local root
  # || return 1 — if the left-hand command fails, bail out immediately
  _pwork_conf || return 1
  root="$_PWORK_ROOT"

  local dry_run=false
  local target=""

  # $# is the number of arguments; -gt 0 means "greater than zero"
  while [[ $# -gt 0 ]]; do
    # case … in — pattern-match $1 against each pattern before the )
    case "$1" in
      # shift removes the current $1 and slides remaining args down by one
      --dry-run) dry_run=true; shift ;;
      # p[0-9]* — match a string starting with "p" followed by a digit
      p[0-9]*) target="$1"; shift ;;
      # *) — wildcard catch-all for anything that didn't match above
      *) echo "Usage: p-clean [--dry-run] [pN]" >&2; return 1 ;;
    # ;; ends each case branch; esac closes the case block
    esac
  done

  # -n tests that a string is non-empty; -d tests that a path is a directory
  if [[ -n "$target" ]] && [[ ! -d "$root/$target" ]]; then
    echo "Error: $root/$target does not exist" >&2
    return 1
  fi

  # command -v checks if a program exists; &>/dev/null discards all output
  if ! command -v gh &>/dev/null; then
    echo "Error: gh CLI required for p-clean. Install: https://cli.github.com/" >&2
    return 1
  fi

  local first_clone
  # head -1 takes only the first line of output
  first_clone="$(echo "$(_pwork_clones)" | head -1)"

  echo "Checking for merged PRs ..."
  local merged_branches open_branches
  _pwork_fetch_pr_branches "$root/$first_clone" "$PWORK_REPO_SLUG" merged_branches open_branches

  # ${VAR:-default} expands to default if VAR is unset or empty
  local default_branch="${PWORK_DEFAULT_BRANCH:-main}"
  local branch recycled=0
  local clones_to_check
  clones_to_check="${target:-$(_pwork_clones)}"

  # Unquoted $clones_to_check lets word-splitting iterate over each clone name
  for clone in $clones_to_check; do
    # 2>/dev/null suppresses stderr (e.g., git errors in detached HEAD state)
    branch=$(cd "$root/$clone" && git branch --show-current 2>/dev/null)
    if [[ "$branch" == "$default_branch" ]]; then
      continue
    fi
    # grep -q suppresses output (just sets exit code); -x matches the whole line
    if echo "$merged_branches" | grep -qx "$branch"; then
      if [[ "$dry_run" == true ]]; then
        echo "  Would recycle $clone (branch: $branch — PR merged)"
      else
        echo "  Recycling $clone (branch: $branch — PR merged) ..."
        # ( … ) runs in a subshell so the cd doesn't change our working directory
        (cd "$root/$clone" && git checkout "$default_branch" && git pull)
        echo "  $clone now on $default_branch"
      fi
      # (( … )) is arithmetic context; ++ increments by one
      (( recycled++ ))
    fi
  done

  # -eq is numeric equality (vs == which is string comparison)
  if [[ $recycled -eq 0 ]]; then
    echo "No clones to recycle — all on $default_branch or no merged PRs found."
  elif [[ "$dry_run" == true ]]; then
    echo ""
    echo "$recycled clone(s) would be recycled. Run without --dry-run to apply."
  else
    echo ""
    echo "Recycled $recycled clone(s) back to $default_branch."
  fi
}
