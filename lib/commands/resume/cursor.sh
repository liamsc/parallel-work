#!/usr/bin/env bash
# Cursor session helpers — everything that knows about Cursor's on-disk
# format and process model. Adding a new tool? Mirror this file.
#   _pwork_resume_encode_cursor       — abs path → ~/.cursor/projects/<name>
#   _pwork_resume_title_cursor        — pull session title out of a jsonl
#   _pwork_resume_recover_cwd_cursor  — best-effort cwd recovery from jsonl
#   _pwork_jump_live_cursor_pid       — pgrep for an active `cursor agent`

# Encode an absolute path the way Cursor names its dir under
# ~/.cursor/projects: / and _ become dashes, dots are dropped, no leading
# dash. e.g. /Users/me/.foo_bar/p1 → Users-me-foo-bar-p1
_pwork_resume_encode_cursor() {
  local p="${1%/}"
  # ${var#/} strips a single leading / if present.
  p="${p#/}"
  # ${var//pattern} with empty replacement deletes every match of pattern.
  p="${p//./}"
  printf '%s' "$p" | tr '/_' '--'
}

# Cursor stores the first user message as content[0].text. Cursor wraps
# prompts in <user_query>…</user_query> alongside <attached_files> noise —
# when present, extract just the user_query so the title isn't a dump of
# attached file contents.
_pwork_resume_title_cursor() {
  local f="$1" line t="" inside
  line=$(grep -m 1 '"role":"user"' "$f" 2>/dev/null)
  if [[ -n "$line" ]]; then
    t=$(printf '%s' "$line" | jq -r '.message.content[0].text // ""' 2>/dev/null)
  fi
  # Collapse newlines first — sed processes line-by-line, but jq returns
  # the text with real newlines, and the user_query block often spans
  # multiple lines. sed -n suppresses default output; -E enables extended
  # regex; p prints matches.
  inside=$(printf '%s' "$t" | tr '\n' ' ' | sed -nE 's/.*<user_query>[[:space:]]*([^<]+).*/\1/p')
  [[ -n "$inside" ]] && t="$inside"
  _pwork_resume_truncate "$t"
}

# Best-effort decode of a cursor encoded dirname back to its original
# absolute workspace path. The encoder is lossy — it strips leading /,
# deletes all dots, and replaces both / and _ with - — so a single
# encoded form like "Users-liamcassidy-socratic-ml" could in principle
# decode to several different paths. We resolve the ambiguity by walking
# segments left-to-right and accumulating each into the longest prefix
# that matches a real directory on disk. Each segment is tried as-is and
# with a leading dot (so hidden dirs like .pwork_repos resolve too).
#
# Returns empty if the chain never matched anything below $HOME's depth
# (defends against "/Users" leaking through when nothing on disk lined
# up). Trailing unmatched segments are appended best-effort so deleted
# workspaces still get a meaningful label.
_pwork_resume_decode_cursor_dir() {
  # nullglob: an unmatched glob (e.g. a directory with no dotfiles) is a
  # hard error under zsh's default options ("no matches found"). The walk
  # below probes "$cur"/.* which silently misses with nullglob — exactly
  # what we want. ksharrays keeps array indexing 0-based to match bash.
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    setopt localoptions ksharrays nullglob
  fi

  local encoded="$1"
  [[ -z "$encoded" ]] && return 0

  # Split $encoded on '-' into parts[]. We can't use `read -a` (bash) or
  # `read -A` (zsh) without forking the script — and `arr=($var)` with
  # IFS='-' doesn't word-split under zsh's default options. Stick to
  # parameter expansion, which behaves the same in both shells:
  #   ${rest%%-*} — everything before the first `-`
  #   ${rest#*-}  — everything after the first `-`
  local -a parts=()
  local rest="$encoded" part
  while [[ -n "$rest" ]]; do
    part="${rest%%-*}"
    parts+=("$part")
    if [[ "$part" == "$rest" ]]; then
      rest=""
    else
      rest="${rest#*-}"
    fi
  done

  local cur=""        # absolute path matched so far
  local segment=""    # bytes accumulated since last successful match
  local p matched entry name enc_name

  for p in "${parts[@]}"; do
    if [[ -z "$segment" ]]; then
      segment="$p"
    else
      segment="${segment}-${p}"
    fi

    # Walk the actual filesystem at the current point and look for a
    # directory whose name, after applying cursor's lossy encoding
    # (drop all dots, _ → -), exactly equals the segment we're after.
    # This handles hidden dirs (leading .) and underscores in one step
    # without trying combinatorial substitutions.
    matched=""
    # When cur is empty (we're at root) "$cur"/* still globs to /* —
    # bash collapses the implicit leading "" into a single /. Avoid
    # ${cur:-/} which produces "//*" with a literal double slash on macOS.
    for entry in "$cur"/* "$cur"/.*; do
      [[ -d "$entry" ]] || continue
      name="$(basename "$entry")"
      # Skip the special . and .. entries that come from the .* glob.
      [[ "$name" == "." || "$name" == ".." ]] && continue
      enc_name="${name//./}"      # delete every dot
      enc_name="${enc_name//_/-}" # _ → - (cursor's encode does both)
      if [[ "$enc_name" == "$segment" ]]; then
        matched="$entry"
        break
      fi
    done

    if [[ -n "$matched" ]]; then
      cur="$matched"
      segment=""
    fi
  done

  # Trailing unmatched segment means we couldn't fully resolve the path
  # — bail rather than guess. Encoded paths whose deepest component was
  # deleted/renamed end up here.
  [[ -n "$segment" ]] && return 0

  # HOME-floor: reject results shallower than $HOME (e.g. "/Users") so a
  # totally-failed decode doesn't leak as a misleading label.
  # ${var//pat/} keeps only / chars; we compare lengths.
  local home_slashes="${HOME//[^\/]/}"
  local cur_slashes="${cur//[^\/]/}"
  [[ ${#cur_slashes} -lt ${#home_slashes} ]] && return 0

  printf '%s' "$cur"
}

# Best-effort recovery of the workspace path a Cursor session was opened
# in. Unlike Claude, Cursor doesn't store a structured cwd field in its
# transcripts — but absolute paths (file references) appear inside message
# content. We grab the first one and walk up to the deepest existing
# directory, which lands on the workspace root rather than a leaf file.
#
# Caveat: if the user references files outside their workspace before
# referencing one inside it, this can over-shoot to a parent. For the
# common case it's accurate enough; callers should treat an empty result
# as "couldn't determine cwd" and render "(unknown)".
_pwork_resume_recover_cwd_cursor() {
  local f="$1" path
  # grep -E — extended regex; -h — no filename prefix; -o — match only.
  # Match "/Users/...", "/home/...", or "/private/var/folders/..." (macOS
  # tmpdirs) inside double-quoted strings — those are the path shapes
  # Cursor embeds in tool-call args.
  path=$(grep -m 1 -hoE '"/(Users|home|private/var/folders)/[^"[:space:]]+"' "$f" 2>/dev/null)
  [[ -z "$path" ]] && return 0
  # Strip the surrounding quotes: ${var#"} and ${var%"}.
  path="${path#\"}"
  path="${path%\"}"
  # Walk up until we hit an existing directory. Guard against a runaway
  # loop (the path is absolute, so we're guaranteed to terminate at "/").
  while [[ -n "$path" && "$path" != "/" && ! -d "$path" ]]; do
    path="$(dirname "$path")"
  done
  [[ "$path" == "/" ]] && return 0

  # Floor: refuse anything shallower than $HOME's depth. Catches the case
  # where a transcript references a path from another machine (a user dir
  # that doesn't exist locally) and the walk-up lands at /Users or /home —
  # those are real directories but useless as session identifiers.
  # ${var//pat/} strips characters; we keep only the / chars and compare
  # lengths to count path depth without needing awk.
  local home_slashes="${HOME//[^\/]/}"
  local path_slashes="${path//[^\/]/}"
  [[ ${#path_slashes} -lt ${#home_slashes} ]] && return 0

  printf '%s' "$path"
}

# Find a live PID running `cursor agent --resume <session-id>`. Anchors
# the regex tightly to avoid catching unrelated processes whose argv just
# happens to contain the session UUID. Returns the pid (one line) or
# empty if no match.
_pwork_jump_live_cursor_pid() {
  local sid="$1"
  [[ -z "$sid" ]] && return 0
  # pgrep -f matches against the full command line (not just executable).
  # head -1 takes only the first match.
  pgrep -f "cursor.*agent.*--resume.*$sid" 2>/dev/null | head -1
}

# Extract the --workspace value from a live cursor-agent's argv. The CLI
# is always invoked as `... agent --resume <sid> --workspace <path>`, so
# when the agent is currently running we can recover its workspace path
# even if the JSONL transcript doesn't embed an absolute path. Returns
# the path or empty if the pid is gone or has no --workspace flag.
_pwork_resume_cursor_pid_workspace() {
  local pid="$1"
  [[ -z "$pid" ]] && return 0
  # ps -o args= prints the full command line. sed pulls the path that
  # follows --workspace; -nE = extended regex, suppress default output;
  # the (...) capture group is what gets printed by the trailing /1/p.
  ps -p "$pid" -o args= 2>/dev/null \
    | sed -nE 's/.*--workspace[[:space:]]+([^[:space:]]+).*/\1/p'
}
