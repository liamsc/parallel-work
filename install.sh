#!/usr/bin/env bash
# parallel-work installer: adds p-* commands to your shell.
# Usage: ./install.sh
# Supports bash and zsh on macOS and Linux.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "parallel-work installer"
echo "======================="

# ── Dependency check ─────────────────────────────────────────
if ! command -v git &>/dev/null; then
  echo "Error: git is required but not found. Install git first." >&2
  exit 1
fi

if ! command -v gh &>/dev/null; then
  echo "Info: gh (GitHub CLI) not found — PR status features will be unavailable."
  echo "  Install: https://cli.github.com/"
fi

if ! command -v claude &>/dev/null; then
  echo "Info: claude (Claude Code) not found — yolo will be unavailable."
  echo "  Install: https://docs.anthropic.com/en/docs/claude-code"
fi

echo ""

# ── Portable sed -i ───────────────────────────────────────────
# macOS sed requires -i '', GNU sed requires -i (no argument).
_sed_i() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# ── Add source lines to an rc file ───────────────────────────
_install_to_rc() {
  local rc_file="$1"
  local rc_name="$2"
  local shell_helpers="$SCRIPT_DIR/lib/shell-helpers.sh"
  local export_line="export PWORK_INSTALL_DIR=\"$SCRIPT_DIR\""
  local source_line="source \"$shell_helpers\""

  if [[ -f "$rc_file" ]]; then
    # Add/update PWORK_INSTALL_DIR
    if grep -qF 'PWORK_INSTALL_DIR' "$rc_file" 2>/dev/null; then
      _sed_i "s|^export PWORK_INSTALL_DIR=.*|$export_line|" "$rc_file"
      echo "Updated PWORK_INSTALL_DIR in $rc_name"
    else
      echo "" >> "$rc_file"
      echo "# parallel-work" >> "$rc_file"
      echo "$export_line" >> "$rc_file"
      echo "Added PWORK_INSTALL_DIR to $rc_name"
    fi

    # Add source line
    if ! grep -qF "source \"$shell_helpers\"" "$rc_file" 2>/dev/null; then
      echo "$source_line" >> "$rc_file"
      echo "Added shell-helpers.sh to $rc_name"
    else
      echo "shell-helpers.sh already in $rc_name — skipping"
    fi
  else
    echo "# parallel-work" > "$rc_file"
    echo "$export_line" >> "$rc_file"
    echo "$source_line" >> "$rc_file"
    echo "Created $rc_name with parallel-work setup"
  fi
}

# ── Detect which rc files to update ──────────────────────────
updated=0

# Always update the rc file for the user's login shell
case "${SHELL:-}" in
  */zsh)
    _install_to_rc "${HOME}/.zshrc" "~/.zshrc"
    updated=1
    # Also update .bashrc if it exists (some users source one from the other)
    if [[ -f "${HOME}/.bashrc" ]]; then
      _install_to_rc "${HOME}/.bashrc" "~/.bashrc"
    fi
    ;;
  */bash)
    _install_to_rc "${HOME}/.bashrc" "~/.bashrc"
    updated=1
    # Also update .zshrc if it exists
    if [[ -f "${HOME}/.zshrc" ]]; then
      _install_to_rc "${HOME}/.zshrc" "~/.zshrc"
    fi
    ;;
  *)
    # Unknown shell — try both common rc files
    if [[ -f "${HOME}/.zshrc" ]]; then
      _install_to_rc "${HOME}/.zshrc" "~/.zshrc"
      updated=1
    fi
    if [[ -f "${HOME}/.bashrc" ]]; then
      _install_to_rc "${HOME}/.bashrc" "~/.bashrc"
      updated=1
    fi
    if [[ $updated -eq 0 ]]; then
      echo "Warning: could not detect shell. Defaulting to ~/.bashrc"
      _install_to_rc "${HOME}/.bashrc" "~/.bashrc"
      updated=1
    fi
    ;;
esac

# ── Summary ──────────────────────────────────────────────────
echo ""
echo "Done! Restart your shell or run: source ~/.zshrc  (or ~/.bashrc)"
echo ""
echo "Then set up a workspace:"
echo "  p-init <repo-url> <workspace-path>"
echo ""
echo "Example:"
echo "  p-init git@github.com:yourorg/yourrepo.git ~/pwork-repos/yourrepo"
