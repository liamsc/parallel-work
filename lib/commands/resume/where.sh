#!/usr/bin/env bash
# Workspace-aware label for an absolute cwd. Used by g-resume to populate
# the "Where" column. The goal is to give a short, scannable label:
#   • Empty cwd               → "(unknown)"
#   • Anywhere under $HOME    → "~/relative/path"
#   • Anything else           → the absolute path
#
# Long paths are left-truncated with a leading "…" so the trailing
# component (the repo or clone name) stays visible. Width is matched to
# render.sh's label_w when the "Where" header is in use.
#
# We deliberately don't try to summarize "this cwd is workspace X's pN"
# — the user could be running g-resume from anywhere, and "p3" alone is
# ambiguous when multiple workspaces have a p3 clone. Showing the path
# always identifies which p3 you're looking at.
#
# Exports:
#   _pwork_resume_where_label

# Width must match render.sh's label_w for the "Where" header.
_PWORK_RESUME_LABEL_MAX_W=22

_pwork_resume_where_label() {
  local cwd="$1"
  if [[ -z "$cwd" ]]; then
    printf '%s' "(unknown)"
    return 0
  fi

  # ${cwd/#$HOME/~} replaces a leading $HOME with literal ~ (the /#
  # anchor restricts to the start of the string).
  local label="${cwd/#$HOME/~}"

  # Left-truncate so the trailing component (the repo/clone name) stays
  # visible — that's what identifies the session. ${var: -N} takes the
  # last N chars; the leading space in `: -` is required to disambiguate
  # from the default-value parameter expansion ${var:-default}.
  if [[ ${#label} -gt $_PWORK_RESUME_LABEL_MAX_W ]]; then
    local keep=$(( _PWORK_RESUME_LABEL_MAX_W - 1 ))
    label="…${label: -$keep}"
  fi
  printf '%s' "$label"
}
