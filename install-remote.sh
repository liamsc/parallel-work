#!/usr/bin/env bash
# Remote installer for parallel-work.
# Usage: curl -fsSL https://raw.githubusercontent.com/liamsc/parallel-work/main/install-remote.sh | bash
set -euo pipefail

INSTALL_DIR="$HOME/.parallel-work"
REPO_URL="https://github.com/liamsc/parallel-work.git"

echo "parallel-work: remote installer"
echo "================================"
echo ""

if [[ -d "$INSTALL_DIR/.git" ]]; then
  echo "Updating existing installation at $INSTALL_DIR ..."
  git -C "$INSTALL_DIR" pull
else
  echo "Installing to $INSTALL_DIR ..."
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

echo ""
"$INSTALL_DIR/install.sh"
