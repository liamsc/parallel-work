#!/usr/bin/env bash
# p-setup: configure statusline, CLAUDE.local.md, and git excludes on existing clones.
# Useful for adopting parallel-work in a workspace that already has clones,
# or re-applying setup after upgrading.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../clone-setup.sh"

p-setup() {
  local root
  root="$(_pwork_root)" || return 1
  source "$root/.parallel-work/pwork.conf"

  local clones
  # _pwork_clones lists pN directories in numeric order
  clones=$(_pwork_clones)
  # -z tests if the string is empty
  if [[ -z "$clones" ]]; then
    echo "No clones found in $root" >&2
    return 1
  fi

  local clone dir count=0
  for clone in $clones; do
    dir="$root/$clone"
    echo "Setting up $clone ..."
    _pwork_setup_clone "$clone" "$dir" "$root"
    (( count++ ))
  done

  echo ""
  echo "Done — configured $count clone(s)."
}
