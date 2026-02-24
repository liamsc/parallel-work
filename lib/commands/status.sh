#!/usr/bin/env bash
# p-status: show branch + commit + dirty status, then merge/PR table.

p-status() {
  local root
  # || return 1 — if the left-hand command fails, bail out immediately
  _pwork_conf || return 1
  root="$_PWORK_ROOT"

  local first_clone
  # head -1 takes only the first line of output
  first_clone="$(echo "$(_pwork_clones)" | head -1)"

  local merged_branches="" open_branches=""
  if _pwork_check_gh; then
    _pwork_fetch_pr_branches "$root/$first_clone" "$PWORK_REPO_SLUG" merged_branches open_branches
  fi

  # local -a declares local array variables
  local -a clones branches commits statuses
  local dir
  for clone in $(_pwork_clones); do
    dir="$root/$clone"
    # += appends an element to a bash array
    clones+=("$clone")
    branches+=("$(cd "$dir" && git branch --show-current)")
    # git log -1 shows only the latest commit; %h = short hash, %s = subject line
    commits+=("$(cd "$dir" && git log -1 --format='%h %s')")
    # git diff --quiet exits 0 (success) if there are no changes — no output printed
    # git diff --cached --quiet does the same for staged changes
    # git ls-files --others --exclude-standard lists untracked files (respecting .gitignore)
    # -z tests that the output is empty (no untracked files)
    if (cd "$dir" && git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]); then
      statuses+=("clean")
    else
      statuses+=("dirty")
    fi
  done

  # ${#array[@]} gives the number of elements in the array
  local n=${#clones[@]}

  # Table 1: Working Tree
  echo "Working Tree"
  # printf %-Ns left-pads a string to N characters
  printf "%-5s  %-25s  %-50s  %s\n" "Clone" "Branch" "Last Commit" "Status"
  printf "%-5s  %-25s  %-50s  %s\n" "-----" "-------------------------" "--------------------------------------------------" "------"
  # for (( … )) is C-style for loop with arithmetic; arrays are 1-indexed here (zsh compat)
  for (( i = 1; i <= n; i++ )); do
    printf "%-5s  %-25s  %-50s  %s\n" "${clones[$i]}" "${branches[$i]}" "${commits[$i]}" "${statuses[$i]}"
  done

  echo ""

  # Table 2: Merge / PR Status
  echo "Merge Status"
  printf "%-5s  %-25s  %s\n" "Clone" "Branch" "PR / Merge"
  printf "%-5s  %-25s  %s\n" "-----" "-------------------------" "----------------------"
  local branch pr_status
  for (( i = 1; i <= n; i++ )); do
    branch="${branches[$i]}"
    # ${VAR:-default} expands to default if VAR is unset or empty
    pr_status="$(_pwork_branch_status "$branch" "${PWORK_DEFAULT_BRANCH:-main}" "$merged_branches" "$open_branches")"
    printf "%-5s  %-25s  %s\n" "${clones[$i]}" "$branch" "$pr_status"
  done
}
