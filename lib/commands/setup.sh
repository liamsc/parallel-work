#!/usr/bin/env bash
# p-setup: configure statusline, CLAUDE.local.md, and git excludes on existing clones.
# Useful for adopting parallel-work in a workspace that already has clones,
# or re-applying setup after upgrading.

p-setup() {
  local root
  root="$(_pwork_root)" || return 1
  # Source the workspace config so _pwork_setup_clone can read PWORK_* variables
  # (e.g. PWORK_SHARED_FILES, PWORK_INSTALL_DIR) needed to configure each clone.
  source "$root/.parallel-work/pwork.conf"

  local clone dir count=0
  # IFS= prevents trimming whitespace; read -r prevents backslash interpretation
  # < <(cmd) is process substitution: feeds cmd's output as if it were a file
  while IFS= read -r clone; do
    # -n tests that a string is non-empty
    [[ -n "$clone" ]] || continue
    dir="$root/$clone"
    echo "Setting up $clone ..."
    # _pwork_setup_clone (defined in lib/clone-setup.sh) creates CLAUDE.local.md,
    # .claude/settings.json (statusline), symlinks, and git exclude entries.
    _pwork_setup_clone "$clone" "$dir" "$root"
    # (( )) is arithmetic context; count += 1 avoids the exit-code-1 gotcha
    # of (( count++ )) when count=0 (post-increment evaluates to 0 → false).
    (( count += 1 ))
  done < <(_pwork_clones)

  if [[ $count -eq 0 ]]; then
    echo "No clones found in $root" >&2
    return 1
  fi

  echo ""
  echo "Done — configured $count clone(s)."
}
