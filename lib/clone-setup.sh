#!/usr/bin/env bash
# Per-clone setup: symlinks, venv, CLAUDE.local.md, git exclude.

# Full per-clone setup: symlinks, CLAUDE.local.md, git exclude.
# Usage: _pwork_setup_clone <clone_name> <clone_dir> <workspace_root>
_pwork_setup_clone() {
  local clone="$1" dir="$2" root="$3"
  local shared_dir="$root/.shared"

  # Symlink shared files
  if [[ ${#PWORK_SHARED_FILES[@]} -gt 0 ]]; then
    local src dest dest_dir
    for mapping in "${PWORK_SHARED_FILES[@]}"; do
      src="${mapping%%:*}"
      dest="${mapping##*:}"
      if [[ -f "$shared_dir/$src" ]]; then
        dest_dir="$(dirname "$dir/$dest")"
        mkdir -p "$dest_dir"
        if [[ ! -L "$dir/$dest" ]]; then
          ln -s "$shared_dir/$src" "$dir/$dest"
          echo "    Symlinked $dest"
        fi
      fi
    done
  fi

  # Create per-clone CLAUDE.local.md
  local local_md="$dir/.claude/CLAUDE.local.md"
  if [[ ! -f "$local_md" ]]; then
    mkdir -p "$dir/.claude"
    cat > "$local_md" <<EOF
# Clone: $clone
## Current Task
_unassigned_

## Notes
- This clone is part of a parallel-work workspace.
- See root CLAUDE.md for full project context.
EOF
    echo "    Created CLAUDE.local.md"
  fi

  # Add CLAUDE.local.md to git's local exclude
  local exclude="$dir/.git/info/exclude"
  if ! grep -q 'CLAUDE.local.md' "$exclude" 2>/dev/null; then
    echo '.claude/CLAUDE.local.md' >> "$exclude"
    echo "    Added CLAUDE.local.md to git exclude"
  fi
}
