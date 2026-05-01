#!/usr/bin/env bash
# parallel-work shell helpers.
# Source this from .zshrc to get p1–pN and p-* commands.
# Usage: source /path/to/parallel-work/lib/shell-helpers.sh

# BASH_SOURCE works in bash; %x prompt expansion works in zsh.
PWORK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
source "$PWORK_LIB_DIR/core.sh"
source "$PWORK_LIB_DIR/gh.sh"
source "$PWORK_LIB_DIR/clone-setup.sh"
source "$PWORK_LIB_DIR/window-jump.sh"
source "$PWORK_LIB_DIR/commands.sh"
