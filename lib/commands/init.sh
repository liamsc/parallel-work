#!/usr/bin/env bash
# p-init: set up a new workspace from a repo URL.
# Usage: p-init <repo-url> [workspace-path] [--clones N] [--branch NAME] [--sync-cmd "..."]

p-init() {
  # $# is the number of arguments; -lt means "less than"
  if [[ $# -lt 1 ]]; then
    echo "Usage: p-init <repo-url> [workspace-path] [options]" >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  --clones N         Number of parallel clones (default: 5)" >&2
    echo "  --branch NAME      Default branch (auto-detected if omitted)" >&2
    echo "  --sync-cmd \"...\"   Command to run after git pull" >&2
    echo "" >&2
    echo "Example:" >&2
    echo "  p-init git@github.com:yourorg/yourrepo.git" >&2
    echo "  p-init git@github.com:yourorg/yourrepo.git ~/pwork-repos/yourrepo" >&2
    return 1
  fi

  local repo_url="$1"
  # shift removes $1 and slides all remaining args down ($2 becomes $1, etc.)
  shift

  # If no path given (next arg is missing or is a flag), derive one from the repo name
  # and confirm with the user.
  local workspace_root
  # --* matches any string starting with -- (i.e., a flag)
  if [[ $# -eq 0 ]] || [[ "$1" == --* ]]; then
    local _name
    # basename strips the directory path; the second arg (.git) strips that suffix
    _name=$(basename "$repo_url" .git)
    workspace_root="$HOME/.pwork_repos/$_name"
    printf "Create workspace at %s? [Y/n] " "$workspace_root"
    local _answer
    read -r _answer
    # =~ is regex match; ^[Nn] means "starts with N or n"
    if [[ "$_answer" =~ ^[Nn] ]]; then
      echo "Aborted." >&2
      return 1
    fi
  else
    # ${var/#pattern/replacement} replaces pattern at the start of the string only
    workspace_root="${1/#\~/$HOME}"
    shift
  fi

  # Defaults
  local clone_count=5
  local branch_override=""
  local sync_cmd=""
  # $# -gt 0 — loop while arguments remain
  while [[ $# -gt 0 ]]; do
    case "$1" in
      # shift 2 consumes both the flag and its value at once
      --clones)   clone_count="$2"; shift 2 ;;
      --branch)   branch_override="$2"; shift 2 ;;
      --sync-cmd) sync_cmd="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; return 1 ;;
    esac
  done

  # =~ ^[0-9]+$ ensures the string is all digits (a positive integer)
  if ! [[ "$clone_count" =~ ^[0-9]+$ ]] || [[ "$clone_count" -lt 1 ]] || [[ "$clone_count" -gt 20 ]]; then
    echo "Error: --clones must be between 1 and 20 (got: $clone_count)" >&2
    return 1
  fi

  # Auto-derive slug (owner/repo) and project name from URL.
  # Handles both SSH (git@host:owner/repo.git) and HTTPS (https://host/owner/repo.git).
  local slug project_name
  local _bare
  # ${var%.git} strips the trailing .git suffix (% = strip shortest match from end)
  _bare="${repo_url%.git}"
  # ${var##*:} strips everything up to and including the last : (## = longest match from start)
  _bare="${_bare##*:}"
  # ${var##*/} strips everything up to and including the last /
  _bare="${_bare##*/}"
  # Re-derive from the cleaned URL: strip .git, then take last two path components.
  _bare="${repo_url%.git}"
  # ${var//pattern/replacement} replaces all occurrences — normalize : to /
  _bare="${_bare//://}"
  project_name=$(basename "$_bare")
  # dirname gives the parent directory path; nested basename extracts the owner
  slug="$(basename "$(dirname "$_bare")")/$project_name"

  local default_branch
  # -n tests that a string is non-empty
  if [[ -n "$branch_override" ]]; then
    default_branch="$branch_override"
  else
    echo "Detecting default branch ..."
    # git ls-remote queries the remote without cloning; sed extracts the branch name
    default_branch=$(git ls-remote --symref "$repo_url" HEAD 2>/dev/null | grep 'ref:' | sed 's#.*refs/heads/##; s#\t.*##')
    # -z tests that a string is empty
    if [[ -z "$default_branch" ]]; then
      default_branch="main"
      echo "  Could not detect — defaulting to 'main'"
    else
      echo "  Detected: $default_branch"
    fi
  fi

  # ${VAR:-} expands to empty string if VAR is unset (safe with set -u)
  if [[ -z "${PWORK_INSTALL_DIR:-}" ]]; then
    echo "Error: PWORK_INSTALL_DIR is not set." >&2
    echo "  Run: source ~/.zshrc (after running install.sh)" >&2
    return 1
  fi

  echo ""
  echo "parallel-work: initializing workspace"
  echo "======================================"
  echo "  Repo:       $repo_url"
  echo "  Slug:       $slug"
  echo "  Project:    $project_name"
  echo "  Branch:     $default_branch"
  echo "  Clones:     $clone_count"
  echo "  Workspace:  $workspace_root"
  echo ""

  # mkdir -p creates the directory and any missing parents
  mkdir -p "$workspace_root/.parallel-work"

  # cat > file <<EOF ... EOF is a heredoc: writes multi-line text into a file
  cat > "$workspace_root/.parallel-work/pwork.conf" <<EOF
PWORK_REPO_URL="$repo_url"
PWORK_REPO_SLUG="$slug"
PWORK_CLONE_COUNT=$clone_count
PWORK_DEFAULT_BRANCH="$default_branch"
PWORK_SYNC_CMD="$sync_cmd"
PWORK_SHARED_FILES=()
EOF
  echo "Generated pwork.conf"

  source "$workspace_root/.parallel-work/pwork.conf"
  WORKSPACE_ROOT="$workspace_root"
  source "$PWORK_INSTALL_DIR/lib/bootstrap.sh"
  bootstrap_workspace

  echo ""
  echo "Workspace ready!"
  echo ""
  printf "%-7s  %-8s  %s\n" "Clone" "Branch" "Path"
  printf "%-7s  %-8s  %s\n" "-------" "--------" "----"
  local _clone _dir _branch
  # seq 1 N generates integers from 1 to N, one per line
  for i in $(seq 1 "$clone_count"); do
    _clone="p${i}"
    _dir="$workspace_root/$_clone"
    # -d tests if a path is a directory
    if [[ -d "$_dir" ]]; then
      # || echo "?" — if the left-hand command fails, use "?" as fallback
      _branch=$(cd "$_dir" && git branch --show-current 2>/dev/null || echo "?")
      printf "%-7s  %-8s  %s\n" "$_clone" "$_branch" "$_dir"
    fi
  done
  echo ""
  echo "Next: cd $workspace_root/p1 && p-status"

  _pwork_register "$workspace_root"
}
