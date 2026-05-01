#!/usr/bin/env bash
# Generic formatters used across the p-resume pipeline.
# No knowledge of Claude or Cursor — just string and time helpers.
#   _pwork_resume_truncate       — squash whitespace, cap at 60 chars with …
#   _pwork_resume_mtime          — file mtime as epoch (BSD or GNU stat)
#   _pwork_resume_relative_time  — epoch-delta → "Xs/m/h/d ago" label

# Squash newlines/tabs to spaces and cap at 60 chars so a row stays one line.
_pwork_resume_truncate() {
  # ${var//pattern/replacement} replaces every occurrence.
  local s="${1//$'\n'/ }"
  s="${s//$'\t'/ }"
  if [[ -z "$s" ]]; then
    printf '%s' "(no title)"
    return
  fi
  # ${#var} is the string length.
  if [[ ${#s} -gt 60 ]]; then
    # ${var:offset:length} is substring extraction.
    s="${s:0:59}…"
  fi
  printf '%s' "$s"
}

# File mtime as epoch seconds. Tries BSD stat (-f %m, macOS) first, falls
# back to GNU stat (-c %Y, Linux). Echoes nothing if both fail, so callers
# can guard with `[[ -z "$mt" ]] && continue`.
_pwork_resume_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
}

# Format an epoch-seconds delta as "Xs/m/h/d ago". Pure shell math so we
# don't depend on GNU date (macOS ships BSD date).
_pwork_resume_relative_time() {
  local then="$1" now diff
  now=$(date +%s)
  # (( … )) is arithmetic context — no $ needed for variables.
  (( diff = now - then ))
  if   (( diff < 60 ));    then printf '%ds ago'  "$diff"
  elif (( diff < 3600 ));  then printf '%dm ago'  "$((diff / 60))"
  elif (( diff < 86400 )); then printf '%dh ago'  "$((diff / 3600))"
  else                          printf '%dd ago'  "$((diff / 86400))"
  fi
}
