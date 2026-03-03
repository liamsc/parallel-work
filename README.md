# parallel-work

![Tests](https://github.com/liamsc/parallel-work/actions/workflows/test.yml/badge.svg)
![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)

Run N copies of Claude Code in parallel on the same repo.

Each clone is a full, independent git checkout — no worktree lock conflicts, no shared `.git` state. Just N directories, each with its own branch and Claude Code session.

## Why parallel clones?

Git worktrees share a single `.git` directory, which causes lock conflicts when multiple processes run git operations simultaneously. Full clones avoid this entirely — each clone is completely independent.

This lets you run 5+ Claude Code sessions in parallel, each working on a different task, without any of them stepping on each other.

## Quick start

```bash
# Install (once):
curl -fsSL https://raw.githubusercontent.com/liamsc/parallel-work/main/install-remote.sh | bash
source ~/.zshrc

# Set up a workspace (one line per repo):
p-init git@github.com:yourorg/yourrepo.git ~/pwork-repos/yourrepo

# Use it:
cd ~/pwork-repos/yourrepo/p1
p-status
```

Or install manually:

```bash
git clone https://github.com/liamsc/parallel-work.git ~/.parallel-work
~/.parallel-work/install.sh && source ~/.zshrc
```

That's it. `p-init` auto-detects the default branch, derives the GitHub slug, and creates 5 clones.

### Options

```bash
p-init git@github.com:org/repo.git ~/pwork-repos/repo \
  --clones 3 \
  --branch develop \
  --sync-cmd "npm install"
```

| Flag | Description |
|---|---|
| `--clones N` | Number of parallel clones (default: 5) |
| `--branch NAME` | Override default branch (auto-detected if omitted) |
| `--sync-cmd "..."` | Command to run after `git pull` (e.g. `npm install`, `bundle install`) |

## Multiple workspaces

Each workspace is isolated. Commands auto-detect which workspace you're in based on your current directory:

```
~/pwork-repos/frontend/          <-- workspace A
  .parallel-work/pwork.conf
  p1/  p2/  p3/  p4/  p5/

~/pwork-repos/webapp/               <-- workspace B
  .parallel-work/pwork.conf
  p1/  p2/  p3/
```

```bash
$ cd ~/pwork-repos/frontend/p2
$ p-status          # shows frontend clones

$ cd ~/pwork-repos/webapp/p1
$ p-status          # shows webapp clones
$ p2                # cd to ~/pwork-repos/webapp/p2
```

To set up a second workspace, just run `p-init` again:

```bash
p-init git@github.com:yourorg/another-repo.git ~/pwork-repos/another-repo
```

Use `pw` to list all workspaces and jump between them:

```bash
pw              # list all workspaces
pw 2            # cd to workspace 2
```

## Configuration

Each workspace stores its config at `<workspace>/.parallel-work/pwork.conf`. Here's the full reference:

| Variable | Required | Description |
|---|---|---|
| `PWORK_REPO_URL` | Yes | Git clone URL (SSH or HTTPS) |
| `PWORK_REPO_SLUG` | Yes | GitHub `owner/repo` for `gh` CLI commands |
| `PWORK_CLONE_COUNT` | Yes | Number of parallel clones to create |
| `PWORK_DEFAULT_BRANCH` | Yes | Default branch name (e.g. `main`) |
| `PWORK_SYNC_CMD` | No | Command to run after `git pull` (e.g. `npm install`, `bundle install`) |
| `PWORK_SHARED_FILES` | No | Array of `"source:dest"` symlink mappings from `.shared/` |

All of these are set automatically by `p-init`. To change them after setup, edit `<workspace>/.parallel-work/pwork.conf` directly.

### Shared files

To share files (like `.env`) across all clones without committing them:

1. Place the file in `<workspace>/.shared/` (e.g. `.shared/.env_main`)
2. Add a mapping to your config:
   ```bash
   PWORK_SHARED_FILES=(
     ".env_main:.env"
   )
   ```
3. Each clone will get a symlink: `p1/.env -> ../.shared/.env_main`

## Commands

All commands (except `plist` and `yolo`) auto-detect which workspace you're in based on your current directory.

### `p-init <url> <path>` — set up a new workspace

```bash
p-init git@github.com:yourorg/yourrepo.git ~/pwork-repos/yourrepo
p-init git@github.com:yourorg/yourrepo.git ~/pwork-repos/yourrepo --clones 3 --sync-cmd "npm install"
```

### `p<N>` — cd into a clone

```bash
p3           # cd into p3 of the current workspace
```

### `pw` — list and jump between workspaces

With no arguments, shows a numbered table of all registered workspaces:

```bash
pw
```

Example output:

```
#     Project               Clones    Path
----  --------------------  --------  ----
1     frontend              5         /Users/you/pwork-repos/frontend
2     webapp                3         /Users/you/pwork-repos/webapp
```

Jump to a workspace by number:

```bash
pw 2            # cd to /Users/you/pwork-repos/webapp
```

Manually register a pre-existing workspace:

```bash
pw --add ~/pwork-repos/legacy-app
```

Workspaces are auto-registered by `p-init`. Stale entries (deleted directories) are pruned automatically.

### `p-sync` — pull and sync all clones

Runs `git pull` (and your `PWORK_SYNC_CMD` if set) across all clones in parallel.

```bash
p-sync
```

### `p-status` — full workspace overview

Shows two tables: working tree status (branch, last commit, dirty/clean) and merge/PR status for each clone.

```bash
p-status
```

Example output:

```
Working Tree
Clone  Branch                     Last Commit                                         Status
-----  -------------------------  --------------------------------------------------  ------
p1     main                       a1b2c3d Initial commit                              clean
p2     fix-login-bug              e4f5g6h Fix session expiry on refresh                dirty
p3     add-search                 i7j8k9l Add full-text search endpoint                clean
p4     main                       a1b2c3d Initial commit                              clean
p5     refactor-auth              m0n1o2p Extract auth middleware                      clean

Merge Status
Clone  Branch                     PR / Merge
-----  -------------------------  ----------------------
p1     main                       available for new work
p2     fix-login-bug              PR open
p3     add-search                 PR merged
p4     main                       available for new work
p5     refactor-auth              no PR
```

**Status definitions:**
- **clean** — no uncommitted changes and no untracked files
- **dirty** — has uncommitted changes (staged or unstaged) or untracked files

### `p-branches` — quick branch overview

Compact view of which branch each clone is on, with PR status.

```bash
p-branches
```

### `p-new` — add another clone

Creates the next `pN` directory in the current workspace with all the configured setup (symlinks, CLAUDE.local.md).

```bash
p-new
```

### `p-clean` — recycle merged clones

Checks out the default branch on clones whose PR has been merged. Old branches are preserved (not deleted) to avoid data loss.

```bash
p-clean              # recycle all merged clones
p-clean p2           # recycle just p2 (if its PR is merged)
p-clean --dry-run    # show what would be recycled
```

### `plist` — show help

```bash
plist
```

### `yolo` — skip Claude permissions

Alias for `claude --dangerously-skip-permissions`. Works from anywhere.

```bash
yolo
```

## FAQ

**Can I use this with repos that aren't on GitHub?**
Yes for cloning and basic operations. The `p-status` and `p-branches` commands use `gh pr list` for PR status, so those features require GitHub. The `p-init` branch detection also uses `git ls-remote`, which works with any git host. You can still use everything else.

**Can I change the number of clones after setup?**
Yes. Use `p-new` to add clones one at a time, or update `PWORK_CLONE_COUNT` in your workspace config.

**Where does the config live?**
Each workspace has its own config at `<workspace>/.parallel-work/pwork.conf`. The shell helpers are sourced once from the `parallel-work` repo itself.

**How do I remove a workspace?**
Delete the workspace directory. The shell helpers will simply not detect it when you're not inside it.

## Updating

If you already have `p-update` (v0.1.0+):

```bash
p-update
```

If you installed before `p-update` existed, update manually once:

```bash
cd ~/.parallel-work   # or wherever you cloned parallel-work
git pull
./install.sh
source ~/.zshrc
```

After that, `p-update` will be available for future upgrades.

Check your installed version at any time:

```bash
p-version
```

## Troubleshooting

**`git clone` fails with "Permission denied (publickey)"**
Your SSH key isn't set up for this host. Run `ssh -T git@github.com` to test. See [GitHub's SSH docs](https://docs.github.com/en/authentication/connecting-to-github-with-ssh).

**`gh` commands fail or show empty PR status**
Run `gh auth login` to authenticate. You need a GitHub token with `repo` scope.

**p-status / p-branches show "gh CLI not found"**
Install the GitHub CLI: `brew install gh` (macOS) or see [cli.github.com](https://cli.github.com/).

## Running tests

```bash
./test.sh
```

All tests run in isolated temp directories — nothing touches your real filesystem, HOME, or existing repos.

## Requirements

- git
- bash or zsh
- [gh](https://cli.github.com/) (GitHub CLI) — optional, for PR status features
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — optional, for `yolo`
- macOS or Linux

## Planned features

### `p-open` — launch a tiled terminal layout

A single command that opens N co-located terminal windows (one per clone) arranged in a grid. Run it from anywhere inside a workspace:

```bash
p-open              # open a window for each clone, tiled 2x2 (or NxN)
p-open 4            # open windows for p1–p4 only
```

Each window `cd`s into its clone directory and is ready for a Claude Code session. Supports:

- **iTerm2** — uses the native Python API to create a tiled split layout
- **Ghostty** — launches windows with the `ghostty` CLI and positions them via config
- **macOS Terminal** — falls back to AppleScript for basic grid tiling

Auto-detects which terminal emulator is running and picks the right backend. The layout scales to your clone count — 4 clones get a 2x2 grid, 6 get a 3x2, etc.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT
