#!/usr/bin/env bash
# Workspace-aware label for an absolute cwd. Used by g-resume to populate
# the "Where" column. The goal is to give a short, scannable label:
#   • If cwd is inside a registered parallel-work workspace as pN, → "pN"
#   • Else if cwd is anywhere under $HOME, → "~/relative/path"
#   • Else → the absolute path
#   • Empty input → "(unknown)"
#
# Exports:
#   _pwork_resume_where_label

# Cache the registered workspace list once per shell — _pwork_list_workspaces
# rewrites the registry file every call (it self-prunes), so calling it once
# per row would be both wasteful and write-heavy. The guard variable is
# inspected on each call; first call populates the cache.
_pwork_resume_where_label() {
  local cwd="$1"
  if [[ -z "$cwd" ]]; then
    printf '%s' "(unknown)"
    return 0
  fi

  # Lazy-load the workspace list. _PWORK_RESUME_WS_LOADED guards the cache.
  if [[ -z "${_PWORK_RESUME_WS_LOADED:-}" ]]; then
    _PWORK_RESUME_WS_LIST=()
    local ws
    while IFS= read -r ws; do
      [[ -n "$ws" ]] && _PWORK_RESUME_WS_LIST+=("$ws")
    done < <(_pwork_list_workspaces 2>/dev/null)
    _PWORK_RESUME_WS_LOADED=1
  fi

  # Longest-prefix match against workspace roots so a workspace nested
  # inside another (rare but possible) resolves to the deeper one.
  local best="" ws
  for ws in "${_PWORK_RESUME_WS_LIST[@]}"; do
    # Match either "$ws" exactly or "$ws/..." (avoid "$wsX" false matches).
    if [[ "$cwd" == "$ws" || "$cwd" == "$ws"/* ]]; then
      # ${#var} is string length — pick the longest match.
      if [[ ${#ws} -gt ${#best} ]]; then
        best="$ws"
      fi
    fi
  done

  if [[ -n "$best" ]]; then
    # Strip the workspace prefix; what remains is "" (cwd was the
    # workspace root) or "pN" or "pN/sub/...".
    local rel="${cwd#$best/}"
    [[ "$rel" == "$cwd" ]] && rel=""
    # Take the first path segment via ${var%%/*} (greedy strip from the
    # right of the first /).
    local first="${rel%%/*}"
    # Fall through to the path fallback unless the first segment is "pN".
    if [[ "$first" =~ ^p[0-9]+$ ]]; then
      printf '%s' "$first"
      return 0
    fi
  fi

  # Fall back to a $HOME-shortened path. ${cwd/#$HOME/~} replaces a leading
  # $HOME with literal ~ (the /# anchor restricts to the start of the string).
  printf '%s' "${cwd/#$HOME/~}"
}
