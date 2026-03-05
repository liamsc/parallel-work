# Cloud Hooks — Implementation Plan

## Concept

"Cloud hooks" = proactively spin off lightweight tasks from a conversation onto available clones. This builds on two things:

1. **parallel-work's clone infrastructure** — idle clones are ready-made isolated workspaces
2. **Claude Code's native hooks system** — lifecycle events (`Stop`, `PostToolUse`, etc.) can trigger shell commands automatically

The feature has two layers:
- **`p-hook` CLI command** — manually dispatch a task to an available clone (the foundation)
- **Claude Code hook integration** — wire `p-hook` into Claude Code's `Stop` event so tasks can be suggested/dispatched automatically at the end of a conversation turn

**Use cases:**
- ML research: "test whether assumption X holds" → spins off a clone to write a quick experiment/analysis
- Software dev: "generate docs for the CLI we just built" → spins off a clone to write docs, tests, or scripts

## New Files

| File | Purpose |
|------|---------|
| `lib/hooks.sh` | Hook infrastructure: clone availability, task tracking, log management |
| `lib/commands/hook.sh` | `p-hook` — dispatch a task to an available clone |
| `lib/commands/hooks.sh` | `p-hooks` — list/monitor active and completed hook tasks |
| `hooks/stop-suggest.sh` | Claude Code `Stop` hook script — suggests tasks to spin off |
| `tests/commands/test_hook.sh` | Tests for p-hook, p-hooks, and hook helpers |

## Data Model

Hook tasks stored as simple files under `.parallel-work/hooks/`:

```
.parallel-work/hooks/
  001.env          # task metadata (sourced as shell vars)
  001.prompt       # the full prompt sent to Claude
  001.log          # stdout/stderr from the Claude session
```

Each `.env` file:
```bash
HOOK_ID=001
HOOK_CLONE=p3
HOOK_STATUS=running    # pending | running | done | failed
HOOK_PID=12345
HOOK_CREATED=2026-03-05T14:30:00
HOOK_FINISHED=
HOOK_SUMMARY="Generate API docs for p-hook command"
```

## Step-by-step Implementation

### Step 1: `lib/hooks.sh` — Hook infrastructure (~80 lines)

Core helper functions:

- **`_pwork_next_hook_id()`** — Scans `.parallel-work/hooks/` for the next sequential ID (zero-padded, 3 digits).

- **`_pwork_available_clone()`** — Returns the first clone that is: (a) on the default branch, (b) has a clean working tree, and (c) has no running hook task. Checks running hooks' `HOOK_CLONE` values against `_pwork_clones` output. Won't hijack a clone someone is actively using.

- **`_pwork_create_hook(clone, summary, prompt)`** — Writes `.env` and `.prompt` files, returns the hook ID.

- **`_pwork_update_hook(hook_id, key, value)`** — Updates a single field in a hook's `.env` file.

- **`_pwork_reap_hooks()`** — Checks PIDs of running hooks; if the process is gone, marks the hook as `done` or `failed` based on exit code.

### Step 2: `lib/commands/hook.sh` — `p-hook` command (~60 lines)

```
p-hook "write unit tests for the new parser"
p-hook --clone p3 "write unit tests for the new parser"
p-hook --dry-run "write unit tests for the new parser"
```

Flow:
1. Parse args: optional `--clone pN` to target a specific clone, optional `--dry-run` to show what would happen without running.
2. `_pwork_conf || return 1`
3. Find an available clone (or use the specified one). Error if none free.
4. Create a new branch on that clone: `hook/<hook_id>-<slugified-summary>`.
5. Write the prompt to `.parallel-work/hooks/<id>.prompt`. The prompt includes:
   - The user's task summary
   - Instruction to commit work when done
   - Workspace context (repo slug, branch info)
6. Register metadata via `_pwork_create_hook`.
7. Launch `claude -p "$(cat <prompt_file>)"` in a subshell, backgrounded, with stdout/stderr redirected to the hook's `.log` file. Store PID.
8. Print: `Hook #001 started on p3 — "write unit tests for the new parser"`

### Step 3: `lib/commands/hooks.sh` — `p-hooks` command (~50 lines)

```
p-hooks           # list all hooks with status
p-hooks 001       # show details + tail log for hook 001
p-hooks --clear   # remove completed/failed hook records
```

Flow:
1. `_pwork_conf || return 1`
2. Call `_pwork_reap_hooks` to update stale statuses.
3. No args → table: `ID | Clone | Status | Summary`
4. Hook ID → full metadata + last 20 lines of log.
5. `--clear` → remove files for done/failed hooks.

### Step 4: `hooks/stop-suggest.sh` — Claude Code Stop hook (~40 lines)

This is a Claude Code `Stop` hook script that fires when Claude finishes a response. It uses Claude Code's native hooks system (`type: "prompt"`) to evaluate whether the conversation surfaced any tasks worth spinning off.

**Configuration** (added to `.claude/settings.json` in each clone by `_pwork_setup_clone`):

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Review the conversation. If it surfaced a concrete, self-contained task that could be done in parallel (writing docs, tests, scripts, or testing an assumption), suggest it. Respond with {\"ok\": true} if there's nothing to spin off, or {\"ok\": false, \"reason\": \"Suggested task: <description>. Run: p-hook \\\"<description>\\\"\"} if there is. Only suggest tasks that are clearly actionable and don't require the current conversation's full context. Be conservative — suggest at most one task per stop."
          }
        ]
      }
    ]
  }
}
```

When the prompt-based hook returns `ok: false`, Claude receives the suggestion as feedback and can present it to the user: "I noticed we could spin off a task: _write tests for the new parser_. Want me to run `p-hook \"write tests for the new parser\"`?"

This is opt-in — the hook config is only added if the user passes `--cloud-hooks` to `p-init` or enables it later via `p-hook --enable`.

### Step 5: Wire into the loader

- Add `source "$PWORK_LIB_DIR/hooks.sh"` to `shell-helpers.sh` (after `gh.sh`, before `commands.sh`)
- Add `source` lines for `hook.sh` and `hooks.sh` to `commands.sh`
- Add `p-hook` and `p-hooks` to `plist` output in `commands/list.sh`

### Step 6: Update `_pwork_setup_clone` for opt-in hook config

If the workspace has cloud hooks enabled (a `PWORK_CLOUD_HOOKS=true` flag in `pwork.conf`), `_pwork_setup_clone` writes the `Stop` hook configuration into each clone's `.claude/settings.local.json` (local, not committed). This uses the existing clone-setup pattern.

### Step 7: Tests (~60 lines)

`tests/commands/test_hook.sh`:

- **`test_hook_next_id`** — Verify sequential IDs with zero-padding.
- **`test_hook_available_clone`** — 3-clone workspace, verify `_pwork_available_clone` returns an idle clone. Mark one busy via a hook `.env`, verify it's skipped.
- **`test_hook_no_available_clone`** — All clones busy → error message.
- **`test_hook_creates_metadata`** — `p-hook --dry-run "test task"`, verify `.env` and `.prompt` created with correct fields.
- **`test_hooks_list`** — Create hook records manually, verify `p-hooks` output format.
- **`test_hooks_clear`** — Create done hooks, `p-hooks --clear`, verify files removed.

### Step 8: Update CLAUDE.md

Add new files to the architecture table, new commands to the commands table.

## Design Decisions

**Why integrate with Claude Code hooks?** Claude Code already has a lifecycle event system with `Stop`, `PostToolUse`, etc. Building on this means we get the trigger mechanism for free — no need to build our own event system. The `Stop` event with a `type: "prompt"` hook is ideal: it uses a lightweight model (Haiku) to evaluate whether the conversation surfaced spin-off-worthy tasks, and feeds suggestions back to Claude naturally.

**Why also keep a standalone `p-hook` command?** The Claude Code hook integration suggests tasks; `p-hook` executes them. This separation means users can also run `p-hook` manually from any terminal, not just from within a Claude session. The hook is the "proactive" layer; the command is the "manual" layer.

**Why `type: "prompt"` over `type: "command"` for the Stop hook?** A command hook would need to parse conversation context itself. A prompt hook lets a model evaluate whether there's a spinnable task — that's judgment, not a deterministic rule. This is exactly the use case Claude Code's prompt hooks were designed for.

**Why opt-in?** Not every workspace needs proactive task suggestions. The Stop hook adds a model call at every turn end, which has cost/latency implications. Making it opt-in (`--cloud-hooks` flag or `PWORK_CLOUD_HOOKS=true`) keeps the default experience unchanged.

**Why files for task tracking?** Matches existing patterns (pwork.conf, workspaces registry). Simple to debug — `cat .parallel-work/hooks/001.env`. No dependencies.

**Why branch-per-hook?** Isolates hook work from whatever the clone was doing. Easy to review, merge, or discard.

## What This Doesn't Include (future work)

- **Hook chaining** — tasks that depend on each other
- **Auto-PR creation** — opening a PR from hook work
- **Conversation context forwarding** — passing conversation history to the hook
- **Hook templates** — predefined types like "write tests", "write docs"
- **Desktop notifications** — could use Claude Code's `Notification` hook to alert when a `p-hook` finishes
