#!/usr/bin/env bash
# Bootstrap: creates and configures clones for a workspace.
# Sourced by p-init — not meant to be run directly.

# Expects these variables to be set by the caller:
#   WORKSPACE_ROOT  — path to the workspace directory
#   All PWORK_* variables from pwork.conf

_PWORK_BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_PWORK_BOOTSTRAP_DIR/clone-setup.sh"

bootstrap_workspace() {
  local root="$WORKSPACE_ROOT"
  local shared_dir="$root/.shared"

  # Create .shared directory if there are shared files configured
  if [[ ${#PWORK_SHARED_FILES[@]} -gt 0 ]]; then
    mkdir -p "$shared_dir"
    echo "Created $shared_dir/"
    echo "  Place your shared files here. Configured mappings:"
    local src
    for mapping in "${PWORK_SHARED_FILES[@]}"; do
      src="${mapping%%:*}"
      echo "    $shared_dir/$src"
    done
  fi

  # Create each clone
  local clone dir
  for i in $(seq 1 "$PWORK_CLONE_COUNT"); do
    clone="p${i}"
    dir="$root/$clone"

    if [[ -d "$dir" ]]; then
      echo "  [$i/$PWORK_CLONE_COUNT] $clone already exists — skipping clone"
    else
      echo "  [$i/$PWORK_CLONE_COUNT] Cloning $clone ..."
      if ! git clone "$PWORK_REPO_URL" "$dir"; then
        echo "Error: git clone failed for $clone" >&2
        echo "  Check the repo URL and your SSH/HTTPS credentials." >&2
        return 1
      fi
      (cd "$dir" && git checkout "${PWORK_DEFAULT_BRANCH:-main}")
      echo "  Cloned $clone"
    fi

    _pwork_setup_clone "$clone" "$dir" "$root"
  done
}
