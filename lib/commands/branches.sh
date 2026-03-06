#!/usr/bin/env bash
# p-branches: quick view of what branch each clone is on.

p-branches() {
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

  # printf %-Ns left-pads a string to N characters
  printf "%-6s  %-25s  %s\n" "Clone" "Branch" "Status"
  printf "%-6s  %-25s  %s\n" "------" "-------------------------" "--------------------"
  local branch pr_status
  # IFS= read -r: read one clone name per line without trimming or backslash processing
  while IFS= read -r clone; do
    [[ -n "$clone" ]] || continue
    # 2>/dev/null suppresses stderr; || echo "(unknown)" provides a fallback if git fails
    branch=$(cd "$root/$clone" && git branch --show-current 2>/dev/null || echo "(unknown)")
    # ${VAR:-default} expands to default if VAR is unset or empty
    pr_status="$(_pwork_branch_status "$branch" "${PWORK_DEFAULT_BRANCH:-main}" "$merged_branches" "$open_branches")"
    printf "%-6s  %-25s  %s\n" "$clone" "$branch" "$pr_status"
  done < <(_pwork_clones)
}
