#!/usr/bin/env bash
# Workspace internals: root detection, config loading, clone discovery.

# Walk up from $PWD to find the nearest .parallel-work/pwork.conf marker.
_pwork_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.parallel-work/pwork.conf" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "Error: not inside a parallel-work workspace" >&2
  return 1
}

# Source pwork.conf; sets _PWORK_ROOT and all PWORK_* variables in caller's scope.
_pwork_conf() {
  _PWORK_ROOT="$(_pwork_root)" || return 1
  source "$_PWORK_ROOT/.parallel-work/pwork.conf"
}

# List pN clone directories in numeric order.
_pwork_clones() {
  local root
  root="$(_pwork_root)" || return 1
  for d in "$root"/p[0-9]*; do
    [[ -d "$d" ]] && basename "$d"
  done | sort -t p -k 2 -n
}

# ── Global workspace registry ────────────────────────────────
# Stores one workspace path per line at ~/.parallel-work/workspaces
# so `pw` can list and jump between workspaces from anywhere.
_PWORK_REGISTRY="${HOME}/.parallel-work/workspaces"

# Idempotently add a workspace path to the global registry.
_pwork_register() {
  local ws_path="$1"
  mkdir -p "$(dirname "$_PWORK_REGISTRY")"
  if [[ -f "$_PWORK_REGISTRY" ]] && grep -qxF "$ws_path" "$_PWORK_REGISTRY"; then
    return 0
  fi
  echo "$ws_path" >> "$_PWORK_REGISTRY"
}

# Return valid workspace paths, one per line. Prunes stale entries automatically.
_pwork_list_workspaces() {
  [[ -f "$_PWORK_REGISTRY" ]] || return 0
  local line
  local -a valid=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ -d "$line/.parallel-work" ]]; then
      valid+=("$line")
    fi
  done < "$_PWORK_REGISTRY"
  printf '%s\n' "${valid[@]}" > "$_PWORK_REGISTRY"
  printf '%s\n' "${valid[@]}"
}
