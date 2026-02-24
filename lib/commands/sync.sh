#!/usr/bin/env bash
# p-sync: pull + dependency sync across all clones.

p-sync() {
  local root
  # || return 1 — if the left-hand command fails, bail out immediately
  _pwork_conf || return 1
  root="$_PWORK_ROOT"

  local fail_file
  # mktemp creates a temporary file with a unique name and returns its path
  fail_file="$(mktemp)"

  for clone in $(_pwork_clones); do
    # ( … ) runs commands in a subshell so the cd doesn't change our working directory
    (
      cd "$root/$clone" &&
      echo "[$clone] syncing ..." &&
      git pull &&
      # ${VAR:-} expands to empty string if VAR is unset (safe with set -u)
      if [[ -n "${PWORK_SYNC_CMD:-}" ]]; then
        # eval runs a string as a command — needed because PWORK_SYNC_CMD may contain pipes/flags
        eval "$PWORK_SYNC_CMD"
      fi &&
      echo "[$clone] done"
    # || — if the subshell fails, log the clone name; & backgrounds the whole thing
    ) || echo "$clone" >> "$fail_file" &
  done
  # wait pauses until all backgrounded (&) jobs finish
  wait

  # -s tests if a file exists and is non-empty
  if [[ -s "$fail_file" ]]; then
    # tr '\n' ' ' replaces newlines with spaces (joins lines into one)
    echo "Warning: sync failed for: $(tr '\n' ' ' < "$fail_file")" >&2
  fi
  # rm -f removes the file; -f means don't error if it's already gone
  rm -f "$fail_file"
}
