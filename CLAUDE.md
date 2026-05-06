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
| `commands/g-resume.sh` | `g-resume` — global session picker: same UX as `p-resume` but enumerates every Claude/Cursor session on disk regardless of workspace |
| `commands/resume/format.sh` | Generic formatters: `_pwork_resume_truncate`, `_pwork_resume_mtime` (BSD/GNU portable), `_pwork_resume_relative_time` |
| `commands/resume/claude.sh` | Claude-specific: path encoding, title extraction, cwd recovery from JSONL, live-session discovery via `~/.claude/sessions/<pid>.json` |
| `commands/resume/cursor.sh` | Cursor-specific: path encoding, title extraction (strips `<attached_files>`), best-effort cwd recovery, live PID via `pgrep -f cursor agent` |
| `commands/resume/where.sh` | `_pwork_resume_where_label` — cwd → `~/relative/path` (or absolute path) with left-truncation, `(unknown)` for empty. Used by `g-resume` |
| `commands/resume/collect.sh` | Per-clone aggregation — calls into `claude.sh` + `cursor.sh`, emits TSV rows for sort/slice |
| `commands/resume/collect_global.sh` | Global aggregation — enumerates every dir under `~/.claude/projects/` and `~/.cursor/projects/`, recovers cwd per session, emits TSV rows |
| `commands/resume/render.sh` | Colored table renderer — live ● marker, `* claude` / `> cursor` glyph + color, hint header. Takes a label header arg ("Clone" or "Where") for both p-resume and g-resume |
| `commands/resume/dispatch.sh` | `_pwork_resume_exec` — pick "focus existing window" vs "launch new" with bypass permissions; takes the target cwd directly so it works for both clone-mode and global-mode |
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
| `g-resume [N]` | Like `p-resume` but searches every Claude/Cursor session on disk regardless of workspace — finds sessions in repos that aren't part of any parallel-work workspace |
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

### Never use bare `rm -rf` in tests

If a path variable is ever empty (setup failed mid-way, copy/paste typo, conditional that didn't set the var on every branch), `rm -rf "$some_var/fake-install"` silently becomes `rm -rf "/fake-install"` — running against the real filesystem. Route every cleanup through `_test_rm` from `tests/helpers.sh`:

```bash
_test_rm "$install_dir"
```

`_test_rm` refuses if any of these are true:
- path is empty, not absolute, exactly `/`, or contains `..`
- `TEST_TMPDIR` is unset, not absolute, shorter than 16 chars (rules out `/`, `/tmp`, anything too broad), or not an existing directory
- `TEST_TMPDIR` is missing the sandbox-marker file (`.parallel-work-test-sandbox`) that `setup_test_workspace` drops at creation — proves the directory was made by the test harness, not e.g. a real `~/something` the user has `TEST_TMPDIR` exported to in their shell rc
- path isn't `TEST_TMPDIR` itself or strictly under it

Rules:

- Any path you want to delete inside a test must be `$TEST_TMPDIR` itself or strictly under it.
- If a test reaches for `mktemp -d` independently, restructure it to put the temp dir under `$TEST_TMPDIR` (call `setup_test_workspace` first). The safety helper can only validate paths inside the sandbox.
- `_test_rm` itself is covered by `tests/test_helpers.sh` — those tests pin the refusal behavior so a future change can't silently weaken the guard.
- Sanity-grep before opening a PR: `grep -rn 'rm -rf' tests/` should only return hits inside `_test_rm`'s own implementation.

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

## Always confirm before opening a PR

Pull requests are the most visible artifact of a change. Once a PR is open, the diff is publicly indexed (for public repos), reviewers may already be tagged, and even after force-push the original commit objects linger in GitHub's object DB for ~30 days. **Never run `gh pr create` without an explicit user-side confirmation in the same conversation turn.**

Acceptable forms of confirmation: "open the PR", "push it up as a PR", "ready to PR", or any direct equivalent. Phrases like "looks good", "let's commit", or "push it" authorize a commit/push, not a PR — ask for explicit PR confirmation as a separate step.

When in doubt, say what you're about to do and ask. The cost of asking is one short turn; the cost of an unwanted PR is forced rewrites, lingering commit objects, and possibly leaked content.

## Don't commit personal paths

Anything that lands in git history is effectively permanent — public PRs expose the path, force-pushes don't always fully erase it, and surgical history rewrites are a hassle. **Scan staged changes for user-specific paths before every commit, including in tests, fixtures, comments, and docs.**

Common offenders:
- `/Users/<your-username>/...` (macOS home dirs)
- `/home/<your-username>/...` (Linux home dirs)
- `/private/var/folders/<user-keyed>/...` (macOS temp dirs)
- Workspace paths that include your username or company (`/Users/alice/work/internal-project`)
- And any encoded variant of the above (e.g. Claude's `-Users-alice-...` flavor of `/Users/alice/...`)

This applies to any committed file — test fixtures, doc tables, header comments, screenshots — not just source code. Don't reference your real paths in `CLAUDE.md` either; use placeholders.

Use placeholders that exercise the same shape but don't identify you:
- `/Users/me/...`, `/Users/test-user/...`
- `~/test-data/...`
- `/tmp/fixture/...`

**Pre-commit check** (run before `git commit`):

```bash
git diff --cached | grep -nE '^\+.*(/Users/|/home/|/private/var/folders/)' \
  | grep -vE '/(Users|home)/(me|test|test-user|fixture)\b' \
  && echo "✗ user-path candidate above — replace with a placeholder" \
  || echo "✓ no user paths in staged changes"
```

If a leak slips in:
1. **Don't just `git commit --amend`** — the leak is still in earlier commits on the branch.
2. Scrub every commit on the branch with `git filter-branch --tree-filter` (or `git filter-repo`), verify with `git log <base>..HEAD -p | grep <leak-pattern>`, then `git push --force-with-lease`.
3. After force-push, expire reflog and `git gc --prune=now` locally; on GitHub the orphaned commit objects can still be reached by direct SHA URL for up to ~30 days. For *sensitive* leaks (tokens, secrets, internal hostnames), rotate the underlying value — don't rely on rewrite alone.

## Code style

Keep code simple, readable, and small. Add comments that explain the **why** and **how**, not just the what.

**Expand acronyms on first use.** When an acronym appears in a comment, doc, or commit message, write it out alongside the short form the first time it shows up so a reader doesn't have to guess. Examples: "TSV (tab-separated values)", "PID (process id)", "TTY (controlling terminal)", "PR (pull request)". Subsequent uses in the same file/section can use the short form alone.

**Use descriptive variable names.** Prefer `session_file` over `f`, `mtime` over `mt`, `encoded_dir` over `enc`, `session_id` over `id`. Don't pile a row of two-letter `local` declarations at the top of a function — by the time the reader reaches the loop body, they've forgotten which is which. Single-letter names are only OK for tiny, throwaway loop variables where the type is obvious from one line away (e.g. `for d in "$root"/p[0-9]*`). When in doubt, type the extra characters.

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
5. **Does this file do one thing?** — If it's growing beyond ~150 lines, split it into a sub-folder of small modules (see "Splitting a growing command" below).

### Splitting a growing command

Once a `commands/<name>.sh` file passes ~150 lines or starts mixing concerns (encoding + dispatch + rendering + integration with another tool), break it apart so a reader can scan the layout and grasp intent quickly. `commands/resume.sh` is the canonical example — follow its shape.

**Layout:**

```
lib/commands/<name>.sh                # public entry point: arg parsing + main flow
lib/commands/<name>/
├── format.sh                         # pure helpers (no domain knowledge)
├── <tool-a>.sh                       # everything that knows about tool A's on-disk format
├── <tool-b>.sh                       # everything that knows about tool B's on-disk format
├── collect.sh                        # orchestration that calls the tool-specific files
├── render.sh                         # presentation only (printf, ANSI codes)
├── dispatch.sh                       # boundary between "user picked X" and "do X"
└── <subgroup>/                       # nest one level when a sub-concern has 3+ files
    ├── … per-piece files …
    └── <subgroup>.sh                 # orchestrator for that sub-concern
```

**Module shape (rules of thumb):**

- **≤ 80 lines per internal file.** If a module passes that, look for a sub-concern to split out further.
- **Lead each file with a 3–6 line header** explaining (1) what it does, (2) which functions it exports, (3) why it exists in the bigger picture. A new reader should pick up intent in seconds without opening other files.
- **Tool-specific code goes in tool-named files** (`claude.sh`, `cursor.sh`, …). Adding a new tool becomes "copy `<tool-a>.sh` and tweak", not a hunt through a monolith.
- **No file does two things.** Encoding, title extraction, and live-process detection for one tool can share a file (they're all "knows tool A's format"). Encoding for tool A and rendering both tools is two things — split.
- **Source order matters.** In the entry-point file, source helpers before consumers. The `commands/resume.sh` order — `format → claude/cursor → jump → collect/render/dispatch` — is a good template: pure helpers first, tool-specific next, orchestrators last.
- **Keep the public entry point thin.** It owns arg parsing, the main control flow, and the call sites for the modules. It does not own implementation details.
- **Internals stay private to the command.** Don't source them from elsewhere; the entry-point file is the only place that knows the layout. If another command needs the same helper, promote it to `lib/<name>.sh` (top-level) — but only when there's a real second caller, not a hypothetical one.

**Procedure to split an existing command:**

1. Identify the responsibilities. Group related functions; one group per file.
2. Create `commands/<name>/` and add files in dependency order (helpers first).
3. Each file gets its header comment and only the functions in its group.
4. The entry-point file shrinks to: source lines (in dependency order), arg parsing, main flow, and any glue too small to extract.
5. Run the test suite — function names are the API contract, so tests should pass without changes.
6. Update the `lib/` table at the top of `CLAUDE.md` so future readers see the new layout.

The point is not "more files" — it's that each file answers one question. A reader scanning `commands/<name>/` should be able to predict what each file contains from its name alone.
