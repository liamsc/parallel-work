#!/usr/bin/env bash
# parallel-work test runner — discovers and runs tests/test_*.sh files.
# Usage: ./test.sh
set +e -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Counters ─────────────────────────────────────────────────
PASS=0
FAIL=0
ERRORS=()

# ── Source helpers and all test files (including subdirectories) ──
source "$SCRIPT_DIR/tests/helpers.sh"
for test_file in "$SCRIPT_DIR"/tests/test_*.sh "$SCRIPT_DIR"/tests/*/test_*.sh; do
  [[ -f "$test_file" ]] && source "$test_file"
done

# ── Run ──────────────────────────────────────────────────────

run_tests() {
  echo ""
  echo -e "${BOLD}parallel-work test suite${RESET}"
  echo "========================"
  echo ""

  # Discover all test_* functions
  local tests
  tests=$(declare -F | awk '{print $3}' | grep '^test_' | sort)
  local total
  total=$(echo "$tests" | wc -l | tr -d ' ')

  local i=0
  for test_fn in $tests; do
    i=$((i + 1))
    local label="${test_fn#test_}"
    label="${label//_/ }"

    if $test_fn >/dev/null 2>"$SCRIPT_DIR/.test_stderr"; then
      PASS=$((PASS + 1))
      echo -e "  ${GREEN}✓${RESET} $label"
    else
      FAIL=$((FAIL + 1))
      ERRORS+=("$test_fn")
      echo -e "  ${RED}✗${RESET} $label"
      # Show failure details
      if [[ -s "$SCRIPT_DIR/.test_stderr" ]]; then
        cat "$SCRIPT_DIR/.test_stderr" | sed 's/^/    /'
      fi
    fi
  done

  rm -f "$SCRIPT_DIR/.test_stderr"

  echo ""
  echo "────────────────────────"
  echo -e "  ${GREEN}$PASS passed${RESET}  ${FAIL:+${RED}$FAIL failed${RESET}  }($(( PASS + FAIL )) total)"

  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo ""
    echo -e "${RED}Failed tests:${RESET}"
    for t in "${ERRORS[@]}"; do
      echo "  - $t"
    done
  fi

  echo ""
  return "$FAIL"
}

run_tests
