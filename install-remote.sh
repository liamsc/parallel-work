#!/usr/bin/env bash
# Remote installer for parallel-work.
# Usage: curl -fsSL https://raw.githubusercontent.com/liamsc/parallel-work/main/install-remote.sh | bash
# Pin a version: curl ... | bash -s v0.1.0
set -euo pipefail

INSTALL_DIR="$HOME/.parallel-work"
REPO_URL="https://github.com/liamsc/parallel-work.git"
# ${1:-} is the optional version tag (e.g. v0.1.0); empty means latest main
VERSION="${1:-}"

echo "parallel-work: remote installer"
echo "================================"
echo ""

if [[ -d "$INSTALL_DIR/.git" ]]; then
  echo "Updating existing installation at $INSTALL_DIR ..."
  git -C "$INSTALL_DIR" fetch --tags
  git -C "$INSTALL_DIR" pull
else
  echo "Installing to $INSTALL_DIR ..."
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

# If a version tag was requested, check it out
if [[ -n "$VERSION" ]]; then
  echo "Checking out $VERSION ..."
  git -C "$INSTALL_DIR" checkout "$VERSION"
fi

echo ""
"$INSTALL_DIR/install.sh"
