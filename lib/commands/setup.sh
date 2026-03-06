#!/usr/bin/env bash
# p-setup: configure statusline, CLAUDE.local.md, and git excludes on existing clones.
# Useful for adopting parallel-work in a workspace that already has clones,
# or re-applying setup after upgrading.

p-setup() {
  local root
  root="$(_pwork_root)" || return 1
  source "$root/.parallel-work/pwork.conf"

  local clone dir count=0
  # IFS= prevents trimming whitespace; read -r prevents backslash interpretation
  # < <(cmd) is process substitution: feeds cmd's output as if it were a file
  while IFS= read -r clone; do
    # -n tests that a string is non-empty
    [[ -n "$clone" ]] || continue
    dir="$root/$clone"
    echo "Setting up $clone ..."
    _pwork_setup_clone "$clone" "$dir" "$root"
    (( count++ ))
  done < <(_pwork_clones)

  if [[ $count -eq 0 ]]; then
    echo "No clones found in $root" >&2
    return 1
  fi

  echo ""
  echo "Done — configured $count clone(s)."
}
