#!/usr/bin/env bash
# p-update: update parallel-work to the latest version.

p-update() {
  # ${VAR:-} expands to empty string if VAR is unset (safe with set -u)
  if [[ -z "${PWORK_INSTALL_DIR:-}" ]]; then
    echo "Error: PWORK_INSTALL_DIR is not set." >&2
    return 1
  fi

  # -d tests if the path is a directory
  if [[ ! -d "$PWORK_INSTALL_DIR/.git" ]]; then
    echo "Error: $PWORK_INSTALL_DIR is not a git repo — cannot auto-update." >&2
    return 1
  fi

  # Refuse to update when the install dir is checked out on something other
  # than main. Git pull would happily update <branch> from origin/<branch>,
  # which is silently the wrong thing — the user thinks they got the latest
  # release but they're still on a stale branch (we hit this exact failure
  # mode after merging v0.3.0). Clear, actionable error beats silent no-op.
  local current_branch
  current_branch=$(git -C "$PWORK_INSTALL_DIR" branch --show-current 2>/dev/null)
  if [[ "$current_branch" != "main" ]]; then
    echo "Error: install dir is on branch '$current_branch', not 'main'." >&2
    echo "  p-update only follows main. Recover with:" >&2
    echo "    git -C \"\$PWORK_INSTALL_DIR\" checkout main && p-update" >&2
    return 1
  fi

  local old_version
  old_version="$(_pwork_version)"

  echo "Updating parallel-work ..."
  # -C tells git to run as if started in the given directory
  git -C "$PWORK_INSTALL_DIR" pull || { echo "Error: git pull failed" >&2; return 1; }

  echo "Running installer ..."
  "$PWORK_INSTALL_DIR/install.sh"

  echo "Reloading shell helpers ..."
  source "$PWORK_INSTALL_DIR/lib/shell-helpers.sh"

  local new_version
  new_version="$(_pwork_version)"

  if [[ "$old_version" != "$new_version" ]]; then
    echo "${old_version} -> ${new_version}"
  fi

  echo "Done! parallel-work is up to date."
}
