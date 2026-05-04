#!/usr/bin/env bash
# Listing renderer — turns the parallel arrays built by p-resume into a
# colored, glyph-marked terminal table. Pure presentation; no I/O beyond
# stdout, no knowledge of which tool wrote which session.
#
# Two redundant visual cues per row so colorblind readers and color-stripped
# terminals (e.g. logs, CI) still get the signal:
#   • leading ●  (live session)  + green color
#   • Tool column "* claude" / "> cursor" + yellow / cyan
#
# Reads these arrays from the caller's scope (bash dynamic scoping):
#   row_when[]   row_label[]   row_tool[]   row_title[]   is_open[]
#
# row_label[] is the per-row workspace identifier — "pN" for clone-mode
# (p-resume) and a "Where" label like "p3", "~/repos/foo", or "(unknown)"
# for global-mode (g-resume).
#
# Args: <show_tool: true|false> <any_live: 0|1> <row_count> <label_header>

_pwork_resume_render() {
  local show_tool="$1" any_live="$2" row_count="$3" label_header="${4:-Clone}"
  # Width follows header: short for "Clone", wider for "Where" so paths fit.
  local label_w=5
  [[ "$label_header" != "Clone" ]] && label_w=22

  # ANSI color codes. -t 1 tests whether stdout is a terminal — when
  # piped/captured (e.g. by tests), we skip codes so output stays plain.
  local c_claude="" c_cursor="" c_live="" c_reset=""
  if [[ -t 1 ]]; then
    c_claude=$'\033[33m'   # yellow — Claude
    c_cursor=$'\033[36m'   # cyan   — Cursor
    c_live=$'\033[32m'     # green  — "session is live"
    c_reset=$'\033[0m'
  fi

  # Hint header is suppressed when nothing is live so the listing isn't
  # cluttered for the common "all closed" case.
  if [[ "$any_live" == "1" ]]; then
    printf "%s●%s = currently open in a terminal — selecting one will jump to its window\n\n" \
      "$c_live" "$c_reset"
  fi

  # Leading "live" column is one char wide (● or blank). We always render
  # it so the rest of the table aligns regardless of any-live state.
  # %-*s — `*` consumes the next arg as the field width.
  local label_dashes
  printf -v label_dashes '%*s' "$label_w" ''
  label_dashes="${label_dashes// /-}"
  if [[ "$show_tool" == true ]]; then
    printf "%s  %-3s  %-10s  %-*s  %-9s  %s\n" " " "#" "When" "$label_w" "$label_header" "Tool" "Title"
    printf "%s  %-3s  %-10s  %-*s  %-9s  %s\n" " " "---" "----------" "$label_w" "$label_dashes" "---------" "-----"
  else
    printf "%s  %-3s  %-10s  %-*s  %s\n" " " "#" "When" "$label_w" "$label_header" "Title"
    printf "%s  %-3s  %-10s  %-*s  %s\n" " " "---" "----------" "$label_w" "$label_dashes" "-----"
  fi

  local i n color glyph live_marker
  for (( i = 0; i < row_count; i++ )); do
    n=$(( i + 1 ))
    if [[ "${is_open[$i]}" == "1" ]]; then
      live_marker="${c_live}●${c_reset}"
    else
      live_marker=" "
    fi
    if [[ "$show_tool" == true ]]; then
      case "${row_tool[$i]}" in
        claude) color="$c_claude"; glyph="*" ;;
        cursor) color="$c_cursor"; glyph=">" ;;
        *)      color="";          glyph=" " ;;
      esac
      # %s%-9s%s — color codes wrap the padded "<glyph> <tool>" cell.
      # ANSI codes have zero printed width, so column alignment is preserved.
      printf "%s  %-3s  %-10s  %-*s  %s%-9s%s  %s\n" \
        "$live_marker" "$n" "${row_when[$i]}" "$label_w" "${row_label[$i]}" \
        "$color" "$glyph ${row_tool[$i]}" "$c_reset" "${row_title[$i]}"
    else
      printf "%s  %-3s  %-10s  %-*s  %s\n" \
        "$live_marker" "$n" "${row_when[$i]}" "$label_w" "${row_label[$i]}" "${row_title[$i]}"
    fi
  done
}
