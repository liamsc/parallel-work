# parallel-work

Shell toolkit for running N Claude Code sessions in parallel against independent clones of the same repo.

## Architecture

The `VERSION` file at the repo root is the single source of truth for the current release (semver, e.g. `0.1.0`). GitHub tags use `v` prefix (`v0.1.0`).

All code lives in `lib/`:

| File | Purpose |
|------|---------|
| `core.sh` | Workspace root detection (`_pwork_root`), config loading (`_pwork_conf`), clone discovery (`_pwork_clones`), version info (`_pwork_version`), global registry helpers (`_pwork_register`, `_pwork_list_workspaces`) |
| `commands.sh` | Loader that sources all files in `commands/` |
| `commands/init.sh` | `p-init` — set up a new workspace from a repo URL |
| `commands/cd.sh` | `p1`–`p20` — quick-cd into a clone |
| `commands/pw.sh` | `pw` — list and jump between workspaces |
| `commands/sync.sh` | `p-sync` — pull + dependency sync across all clones |
| `commands/status.sh` | `p-status` — branch, commit, dirty/clean, and PR status |
| `commands/branches.sh` | `p-branches` — quick branch + PR/merge status per clone |
| `commands/new.sh` | `p-new` — create the next pN clone |
| `commands/setup.sh` | `p-setup` — apply statusline + clone config to existing clones |
| `commands/clean.sh` | `p-clean` — recycle clones whose PR has been merged |
| `commands/resume.sh` | `p-resume` — entry point: arg parse, listing build, render, prompt, dispatch (sources everything in `commands/resume/`) |
| `commands/resume/format.sh` | Generic formatters: `_pwork_resume_truncate`, `_pwork_resume_mtime` (BSD/GNU portable), `_pwork_resume_relative_time` |
| `commands/resume/claude.sh` | Claude-specific: path encoding, jsonl title extraction, live-session discovery via `~/.claude/sessions/<pid>.json` |
| `commands/resume/cursor.sh` | Cursor-specific: path encoding, title extraction (strips `<attached_files>`), live PID via `pgrep -f cursor agent` |
| `commands/resume/collect.sh` | Per-clone aggregation — calls into `claude.sh` + `cursor.sh`, emits TSV rows for sort/slice |
| `commands/resume/render.sh` | Colored table renderer — live ● marker, `* claude` / `> cursor` glyph + color, hint header |
| `commands/resume/dispatch.sh` | `_pwork_resume_exec` — pick "focus existing window" vs "launch new" with bypass permissions |
| `commands/resume/jump/terminal.sh` | `_pwork_jump_pid_tty`, `_pwork_jump_pid_terminal` — ppid walk identifies iterm2/ghostty/terminal/unknown |
| `commands/resume/jump/iterm2.sh` | `_pwork_jump_focus_iterm2` — precise TTY-based AppleScript focus |
| `commands/resume/jump/ghostty.sh` | `_pwork_jump_focus_ghostty` — best-effort focus by session name → cwd → activate |
| `commands/resume/jump/window.sh` | `_pwork_jump_window` orchestrator — glues live-discovery + per-app focus |
| `commands/update.sh` | `p-update` — update parallel-work to the latest version |
| `commands/version.sh` | `p-version` — show installed version and git SHA |
| `commands/list.sh` | `plist` + `yolo` — help listing and alias |
| `statusline.sh` | Claude Code statusline script — shows clone name, repo, branch, git state, context %, and current task |
| `clone-setup.sh` | Per-clone setup: symlinks, `CLAUDE.local.md`, statusline settings, git exclude |
| `bootstrap.sh` | Workspace initialization — creates and configures N clones |
| `gh.sh` | GitHub CLI helpers: `_pwork_check_gh`, `_pwork_fetch_pr_branches`, `_pwork_branch_status` |
| `shell-helpers.sh` | Entry point sourced from `.zshrc` — loads all other lib files, provides `p1`–`pN` functions |

## Commands

| Command | Description |
|---------|-------------|
| `p-init <url> <path>` | Set up a new workspace from a repo URL |
| `p<N>` | cd into clone pN |
| `pw [N]` | List all workspaces, or cd to workspace N |
| `p-sync` | Pull + run sync command across all clones |
| `p-status` | Branch, commit, dirty/clean, and PR status table |
| `p-branches` | Quick branch + PR/merge status per clone |
| `p-new` | Create the next pN clone |
| `p-setup` | Apply statusline + clone config to all existing clones |
| `p-clean [pN]` | Recycle clones whose PR has been merged |
| `p-resume [N] [pN]` | List recent Claude/Cursor sessions across clones; focus an open window (iTerm2/Ghostty) or launch a new resume with bypass permissions |
| `p-update` | Update parallel-work to the latest version |
| `p-version` | Show installed version and git SHA |
| `plist` | List all commands |

## Testing

```bash
./test.sh
```

- Test files: `tests/test_*.sh` and `tests/commands/test_*.sh` (auto-discovered by `test.sh`)
- Helpers: `tests/helpers.sh` — assertions (`assert_eq`, `assert_contains`, `assert_status_fail`, etc.) and workspace fixtures
- Fixture pattern: `setup_test_workspace` creates a bare origin + tmpdir, `create_workspace N` bootstraps N clones, `teardown_test_workspace` cleans up
- Tests run in subshells; stdout is suppressed, stderr shown on failure
- Every test function must have a `# Description:` comment above it explaining what the test verifies

## Manual testing

To test `_pwork_setup_clone` without creating a full workspace:

```bash
# Create a fake clone with a git repo
mkdir -p /tmp/test-clone/.claude /tmp/test-clone/.git/info
touch /tmp/test-clone/.git/info/exclude

# Source the setup code
source lib/clone-setup.sh

# Run it (needs PWORK_INSTALL_DIR and PWORK_SHARED_FILES)
export PWORK_INSTALL_DIR="$PWD"
PWORK_SHARED_FILES=()
_pwork_setup_clone "p1" "/tmp/test-clone" "/tmp"

# Verify output files
cat /tmp/test-clone/.claude/settings.local.json
cat /tmp/test-clone/.git/info/exclude
cat /tmp/test-clone/.claude/CLAUDE.local.md

# Clean up
rm -rf /tmp/test-clone
```

## Conventions

- Shell: bash, `set -uo pipefail` in scripts
- Internal functions: `_pwork_` prefix (e.g., `_pwork_root`, `_pwork_conf`)
- User commands: `p-` prefix (e.g., `p-sync`, `p-clean`)
- Config: `.parallel-work/pwork.conf` at workspace root, sourced to set `PWORK_*` variables
- Each clone gets `.claude/CLAUDE.local.md` (git-excluded)

## Code style

Keep code simple, readable, and small. Add comments that explain the **why** and **how**, not just the what.

### Good examples

```bash
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
```

- Comment says *why* this function exists and *how* it works (walks up the tree)
- Short, single-purpose, easy to follow

```bash
# List pN clone directories in numeric order.
_pwork_clones() {
  local root
  root="$(_pwork_root)" || return 1
  for d in "$root"/p[0-9]*; do
    [[ -d "$d" ]] && basename "$d"
  done | sort -t p -k 2 -n
}
```

- The `sort` flags aren't obvious — the comment explains the intent (numeric order)

### Bad examples

```bash
# This function gets the root
_pwork_root() {
```

- Comment restates the function name — doesn't explain *how* or *why*

```bash
# Get clones, filter, sort, validate, and return
_pwork_clones() {
  local root dirs filtered sorted validated
  root="$(_pwork_root)" || return 1
  dirs=()
  for d in "$root"/p[0-9]*; do
    [[ -d "$d" ]] && dirs+=("$(basename "$d")")
  done
  filtered=("${dirs[@]}")
  sorted=($(printf '%s\n' "${filtered[@]}" | sort -t p -k 2 -n))
  validated=()
  for s in "${sorted[@]}"; do
    validated+=("$s")
  done
  printf '%s\n' "${validated[@]}"
}
```

- Over-engineered — extra variables and steps that do nothing
- The simple version with a `for` loop piped to `sort` does the same thing

### Bash-newbie comments

Annotate bash syntax that isn't self-explanatory to someone new to shell scripting. Put these as inline comments on (or directly above) the line that uses the syntax. Focus on operators, flags, and idioms — not what the surrounding logic does.

```bash
# $# is the number of arguments; -gt 0 means "greater than zero"
while [[ $# -gt 0 ]]; do
  case "$1" in
    # shift removes the current $1 and slides remaining args down by one
    --dry-run) dry_run=true; shift ;;
    # p[0-9]* — match a string starting with "p" followed by a digit
    p[0-9]*) target="$1"; shift ;;
    # *) — wildcard catch-all for anything that didn't match above
    *) echo "Usage: p-clean [--dry-run] [pN]" >&2; return 1 ;;
  esac
done
```

Good candidates for these comments:
- Test operators: `-n`, `-z`, `-d`, `-f`, `-eq`, `-gt`, etc.
- Redirections: `&>/dev/null`, `2>/dev/null`, `>&2`
- Parameter expansion: `${VAR:-default}`, `${VAR%%pattern}`
- Idioms: `|| return 1`, `command -v`, `(( … ))` arithmetic, `( … )` subshells
- Flags on common tools: `grep -qx`, `sort -t p -k 2 -n`, `head -1`

Skip comments for things that read like English already (`if`, `then`, `echo`, variable assignment).

### Simplicity checklist

When writing or reviewing code, ask:

1. **Can I delete this?** — If a variable, branch, or function doesn't change behavior when removed, remove it.
2. **Can I inline this?** — If a helper is only called once and is short, inline it.
3. **Would a new reader understand this in 10 seconds?** — If not, add a comment explaining *why* or simplify the logic.
4. **Am I adding a flag/option nobody asked for?** — Don't build for hypothetical future use.
5. **Does this file do one thing?** — If it's growing beyond ~150 lines, consider splitting by responsibility (see `lib/` layout).
