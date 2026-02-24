#!/usr/bin/env bash
# p-new: create a new pN clone directory.

p-new() {
  local root
  # || return 1 — if the left-hand command fails, bail out immediately
  _pwork_conf || return 1
  root="$_PWORK_ROOT"

  # Find the next available pN number
  local max=0 num
  # p[0-9]* is a glob: matches paths starting with p followed by a digit
  for d in "$root"/p[0-9]*; do
    # -d tests if a path is a directory; || continue skips to the next iteration if not
    [[ -d "$d" ]] || continue
    # ${d##*p} strips everything up to and including the last "p", leaving just the number
    num="${d##*p}"
    # (( )) is arithmetic context; this sets max to num if num is larger
    (( num > max )) && max=$num
  done
  # $(( )) is arithmetic expansion — evaluates the expression and returns the result
  local next=$(( max + 1 ))
  local clone="p${next}"
  local dir="$root/$clone"

  echo "Creating $clone ..."

  if ! git clone "$PWORK_REPO_URL" "$dir"; then
    echo "Error: git clone failed for $clone" >&2
    echo "  Check the repo URL and your SSH/HTTPS credentials." >&2
    return 1
  fi
  # ( … ) runs in a subshell so the cd doesn't change our working directory
  # ${VAR:-default} expands to default if VAR is unset or empty
  (cd "$dir" && git checkout "${PWORK_DEFAULT_BRANCH:-main}")
  echo "  Cloned $clone"

  _pwork_setup_clone "$clone" "$dir" "$root"

  echo ""
  echo "$clone is ready at $dir"
  echo "  Run: p${next}"
}
