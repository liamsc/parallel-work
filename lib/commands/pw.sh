#!/usr/bin/env bash
# pw: list and jump between workspaces.
# No args: numbered table of registered workspaces (name, clones, path).
# pw N: cd to workspace N's root.
# pw --add PATH: manually register a pre-existing workspace.

pw() {
  # zsh arrays are 1-indexed, bash arrays are 0-indexed;
  # ksharrays makes zsh use 0-indexed like bash so indexing is portable.
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    setopt localoptions ksharrays
  fi

  # ${1:-} expands to $1 if set, or empty string if unset (avoids error with set -u)
  if [[ "${1:-}" == "--add" ]]; then
    local target="${2:-}"
    # -z tests if a string is empty (opposite of -n)
    if [[ -z "$target" ]]; then
      echo "Usage: pw --add <workspace-path>" >&2
      return 1
    fi
    # ${var/#pattern/replacement} replaces pattern only at the start of the string
    target="${target/#\~/$HOME}"
    # -d tests if a path is a directory; ! negates
    if [[ ! -d "$target/.parallel-work" ]]; then
      echo "Error: $target is not a parallel-work workspace" >&2
      return 1
    fi
    _pwork_register "$target"
    echo "Registered $target"
    return 0
  fi

  # local -a declares a local array variable
  local -a paths=()
  local line
  # IFS= prevents trimming whitespace; read -r prevents backslash interpretation
  # < <(cmd) is process substitution: feeds cmd's output as if it were a file
  while IFS= read -r line; do
    # -n tests that a string is non-empty
    [[ -n "$line" ]] && paths+=("$line")
  done < <(_pwork_list_workspaces)

  # ${#array[@]} gives the number of elements in the array; -eq is numeric equality
  if [[ ${#paths[@]} -eq 0 ]]; then
    echo "No workspaces registered." >&2
    echo "  Run p-init to create one, or pw --add <path> to register an existing one." >&2
    return 1
  fi

  # pw N — jump to workspace N
  if [[ -n "${1:-}" ]]; then
    local idx="$1"
    # =~ is regex match; ^[0-9]+$ means "one or more digits, nothing else"
    # -lt / -gt are numeric less-than / greater-than
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || [[ "$idx" -lt 1 ]] || [[ "$idx" -gt ${#paths[@]} ]]; then
      echo "Error: invalid workspace number '$idx' (have ${#paths[@]} workspace(s))" >&2
      return 1
    fi
    # Arithmetic inside []: $idx - 1 converts 1-based input to 0-based array index
    cd "${paths[$idx - 1]}"
    echo "Use p1, p2, … to cd into a clone. p-status for clone status."
    return 0
  fi

  # pw (no args) — list workspaces
  # printf %-Ns left-pads a string to N characters
  printf "%-4s  %-20s  %-8s  %s\n" "#" "Project" "Clones" "Path"
  printf "%-4s  %-20s  %-8s  %s\n" "----" "--------------------" "--------" "----"
  local i=0 ws_name clone_count
  for ws in "${paths[@]}"; do
    # (( )) is arithmetic context; ++ increments by one
    (( i++ ))
    # 2>/dev/null suppresses stderr
    ws_name=$(cd "$ws" && source .parallel-work/pwork.conf 2>/dev/null && basename "${PWORK_REPO_SLUG:-$ws}")
    # wc -l counts lines; tr -d ' ' strips whitespace padding from wc output
    clone_count=$(cd "$ws" && ls -1d p[0-9]* 2>/dev/null | wc -l | tr -d ' ')
    printf "%-4s  %-20s  %-8s  %s\n" "$i" "$ws_name" "$clone_count" "$ws"
  done

  echo ""
  local choice
  # printf prompt to stderr so it shows even when stdout is captured;
  # plain `read -r` works in both bash and zsh (read -p is bash-only).
  printf "Workspace #: " >&2
  read -r choice

  # -z tests if a string is empty — user just pressed enter, do nothing
  [[ -z "$choice" ]] && return 0

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#paths[@]} ]]; then
    echo "Invalid choice: $choice" >&2
    return 1
  fi

  cd "${paths[$choice - 1]}"
  echo "Use p1, p2, … to cd into a clone. p-status for clone status."
}
