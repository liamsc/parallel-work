#!/usr/bin/env bash
# p-version: show the installed parallel-work version and git SHA.

p-version() {
  local version
  version="$(_pwork_version)"

  local sha=""
  local suffix=""

  # -C tells git to run as if started in the given directory
  if [[ -d "$PWORK_INSTALL_DIR/.git" ]]; then
    # --short gives abbreviated (7-char) SHA; 2>/dev/null in case git fails
    sha=$(git -C "$PWORK_INSTALL_DIR" rev-parse --short HEAD 2>/dev/null)

    # Check for uncommitted changes (unstaged or staged) in the install dir
    # --quiet exits non-zero if there are changes; --cached checks the staging area
    if ! git -C "$PWORK_INSTALL_DIR" diff --quiet --ignore-submodules 2>/dev/null \
       || ! git -C "$PWORK_INSTALL_DIR" diff --quiet --cached --ignore-submodules 2>/dev/null; then
      suffix=", dirty"
    fi
  fi

  if [[ -n "$sha" ]]; then
    echo "parallel-work ${version} (${sha}${suffix})"
  else
    echo "parallel-work ${version}"
  fi
}
