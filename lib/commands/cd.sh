#!/usr/bin/env bash
# p1–p20: quick-cd into a clone directory.

_pwork_cd() {
  local root
  # || return 1 — if the left-hand command fails, bail out immediately
  root="$(_pwork_root)" || return 1
  local target="$root/p${1}"
  # -d tests if a path is a directory; ! negates
  if [[ ! -d "$target" ]]; then
    # >&2 redirects output to stderr (for error messages)
    echo "Error: $target does not exist" >&2
    return 1
  fi
  cd "$target"
}
# seq 1 20 generates integers 1 through 20, one per line
for _i in $(seq 1 20); do
  # 2>/dev/null suppresses stderr — silently ignore "not found" if no alias exists
  unalias "p${_i}" 2>/dev/null
  # eval builds a string and executes it as code — creates p1(), p2(), ... p20()
  eval "p${_i}() { _pwork_cd ${_i}; }"
done
# unset removes the temporary loop variable so it doesn't leak into the shell
unset _i
