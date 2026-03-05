# Cloud Hooks — Implementation Plan

## Concept

"Cloud hooks" = proactively spin off lightweight tasks from a conversation onto available clones. This builds on two things:

1. **parallel-work's clone infrastructure** — idle clones are ready-made isolated workspaces
2. **Claude Code's native hooks system** — lifecycle events (`Stop`, `PostToolUse`, etc.) can trigger shell commands automatically

The feature has two layers:
- **`p-hook` CLI command** — manually dispatch a task to an available clone (the foundation)
- **Claude Code hook integration** — wire `p-hook` into Claude Code's `Stop` event so tasks can be suggested/dispatched automatically at the end of a conversation turn

## Immediate User Value

### Who uses this and when?

The target user is someone running multiple Claude Code sessions via parallel-work who wants to capture "side quests" that surface during a main conversation — without losing focus or context-switching.

### Scenario 1: ML Research — Assumption Testing

You're in p1 discussing experiment design for a paper. Claude says "we're assuming the distribution is roughly normal — we should verify that." Today, you'd either (a) derail the current conversation to test it, or (b) make a mental note and forget.

With cloud hooks:
```
p-hook "Load dataset from data/samples.csv, plot the distribution of the 'latency' column, run a Shapiro-Wilk normality test, and write results to FINDINGS.md"
```

This spins up on idle clone p3. Five minutes later you check `p-hooks` — the task is done, there's a branch with `FINDINGS.md` and a histogram PNG. Your main conversation in p1 never lost context.

**Why this matters:** Research conversations are exploratory. They surface 3-5 testable assumptions per hour. Most get lost because switching context is expensive. Cloud hooks lower the cost of "let's check that" to a single command.

### Scenario 2: Software Dev — Documentation from CLI History

You've been building a deployment pipeline in p2. Over 45 minutes you ran a dozen manual CLI commands: `aws ecs create-service`, `aws logs create-log-group`, kubectl commands, etc. The conversation has all the context for why each command was run.

With cloud hooks:
```
p-hook "Review the git log and any shell history in this workspace. Create a scripts/deploy.sh that automates the deployment steps, and a docs/deployment.md runbook explaining each step"
```

This runs on p4. The spawned session reads the commit history and any artifacts in the workspace, then produces a deploy script and runbook.

**Why this matters:** "I'll document this later" is where documentation goes to die. Cloud hooks capture the intent while the context is fresh — the cost is one command instead of 30 minutes of writing.

### Scenario 3: Test Gap Filling

You're implementing a feature in p1 and Claude mentions "this edge case isn't covered by tests." You don't want to interrupt the feature work:

```
p-hook "Add unit tests for the edge cases in lib/parser.sh: empty input, input with only whitespace, and input exceeding 1MB. Follow the existing test patterns in tests/"
```

Runs on p5. You review the test branch later and merge it.

### Scenario 4: Refactor Scouting

Mid-conversation, you notice a function has grown to 200 lines. You want to know if it's worth splitting, but not right now:

```
p-hook "Analyze lib/commands/init.sh for complexity. Identify functions over 50 lines, suggest how to split them, and estimate the blast radius of each refactor. Write findings to REFACTOR-PLAN.md"
```

This is read-only analysis — no code changes, just a written assessment waiting for you when you're ready.

### What makes these "immediately useful" vs. future aspirations?

All four scenarios work with **just `p-hook` and `p-hooks`** — no Claude Code hook integration needed. The `Stop` hook layer (proactive suggestions) is a bonus that makes the system smarter over time, but the core value is the manual command. A user can install this, run `p-hook "do X"`, and get value in the first session.

## New Files

| File | Purpose |
|------|---------|
| `lib/hooks.sh` | Hook infrastructure: clone availability, task tracking, log management |
| `lib/commands/hook.sh` | `p-hook` — dispatch a task to an available clone |
| `lib/commands/hooks.sh` | `p-hooks` — list/monitor active and completed hook tasks |
| `hooks/stop-suggest.sh` | Claude Code `Stop` hook script — extracts context, invokes suggestion |
| `evals/stop-hook/run-evals.sh` | Eval harness for the Stop hook prompt |
| `evals/stop-hook/cases/` | Test cases (input JSON + expected output) |
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
HOOK_TOKENS_IN=0       # input tokens consumed (updated on completion)
HOOK_TOKENS_OUT=0      # output tokens consumed (updated on completion)
```

## Step-by-step Implementation

### Step 1: `lib/hooks.sh` — Hook infrastructure (~80 lines)

Core helper functions:

- **`_pwork_next_hook_id()`** — Scans `.parallel-work/hooks/` for the next sequential ID (zero-padded, 3 digits).

- **`_pwork_available_clone()`** — Returns the first clone that is: (a) on the default branch, (b) has a clean working tree, and (c) has no running hook task. Checks running hooks' `HOOK_CLONE` values against `_pwork_clones` output. Won't hijack a clone someone is actively using.

- **`_pwork_create_hook(clone, summary, prompt)`** — Writes `.env` and `.prompt` files, returns the hook ID.

- **`_pwork_update_hook(hook_id, key, value)`** — Updates a single field in a hook's `.env` file.

- **`_pwork_reap_hooks()`** — Checks PIDs of running hooks; if the process is gone, marks the hook as `done` or `failed` based on exit code. Also parses token usage from the log file (see Token Validation section).

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
3. No args → table: `ID | Clone | Status | Tokens | Summary`
4. Hook ID → full metadata + last 20 lines of log.
5. `--clear` → remove files for done/failed hooks.

### Step 4: `hooks/stop-suggest.sh` — Claude Code Stop hook

**Critical design constraint:** Prompt-based Stop hooks (`type: "prompt"`) only see the hook input JSON — specifically `last_assistant_message`, `session_id`, `transcript_path`, and `cwd`. They do NOT see the full conversation. This means a pure prompt hook can only judge based on Claude's final response text.

This is actually fine for many cases ("I've finished implementing the parser" → suggest writing tests), but insufficient for others (detecting that multiple CLI commands were run that should be scripted).

**Chosen approach: `type: "command"` hook that extracts context, then calls the Anthropic API.**

The `hooks/stop-suggest.sh` script:
1. Reads the hook input JSON from stdin (includes `transcript_path` and `last_assistant_message`)
2. Parses the transcript JSONL to extract:
   - Tool calls made (which files were edited, which bash commands were run)
   - A condensed summary of what happened (last N tool calls, not the full transcript)
3. Builds a prompt with this extracted context
4. Calls the Anthropic API directly (`curl` to `api.anthropic.com/v1/messages`) with Haiku, asking whether there's a spinnable task
5. If yes: exits with code 0 and writes JSON to stdout with `additionalContext` suggesting the task. Claude then naturally presents this to the user.
6. If no spinnable task: exits with code 0 silently.

**Why `type: "command"` instead of `type: "prompt"`?** The prompt hook only sees `last_assistant_message`. By using a command hook, we can parse the `transcript_path` JSONL to extract tool calls, file edits, and bash commands — much richer context for deciding what to spin off. The tradeoff is we make our own API call (requires `ANTHROPIC_API_KEY`), but users of Claude Code already have this set.

**Configuration** (written to `.claude/settings.local.json` in each clone):
```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$PWORK_INSTALL_DIR/hooks/stop-suggest.sh"
          }
        ]
      }
    ]
  }
}
```

This is opt-in via `PWORK_CLOUD_HOOKS=true` in pwork.conf.

### Step 5: Wire into the loader

- Add `source "$PWORK_LIB_DIR/hooks.sh"` to `shell-helpers.sh` (after `gh.sh`, before `commands.sh`)
- Add `source` lines for `hook.sh` and `hooks.sh` to `commands.sh`
- Add `p-hook` and `p-hooks` to `plist` output in `commands/list.sh`

### Step 6: Update `_pwork_setup_clone` for opt-in hook config

If `PWORK_CLOUD_HOOKS=true` in pwork.conf, `_pwork_setup_clone` writes the Stop hook config into each clone's `.claude/settings.local.json`. This uses the existing clone-setup pattern.

### Step 7: Tests

See Tests section below.

### Step 8: Update CLAUDE.md

Add new files to architecture table, new commands to commands table.

## Token Usage Validation

### The Problem

Each `p-hook` invocation runs a full `claude -p` session. Without visibility into token consumption, users can't gauge the cost of their hook tasks or detect runaway sessions.

### Token Tracking Strategy

**Layer 1: Per-hook token capture from `claude -p` output**

`claude -p` outputs JSON that includes token usage stats. When `_pwork_reap_hooks` detects a completed hook, it parses the log file for the token usage summary and writes `HOOK_TOKENS_IN` and `HOOK_TOKENS_OUT` to the hook's `.env` file.

The parsing logic looks for Claude Code's session summary output, which reports input/output tokens used. This is fragile (depends on output format), so we also support an environment variable approach:

**Layer 2: `--output-format json` flag**

Run hooks with `claude -p --output-format json`, which outputs structured JSON including token counts. Parse with `jq`:
```bash
claude -p --output-format json "$(cat prompt)" 2>"$log_file" | jq -r '.usage'
```

**Layer 3: Aggregate reporting in `p-hooks`**

`p-hooks` shows per-hook token counts and a total across all hooks:
```
ID   Clone  Status  Tokens (in/out)  Summary
001  p3     done    12.4k / 3.2k     Write unit tests for parser
002  p5     running —                 Generate deployment docs
003  p2     done    8.1k / 1.8k      Analyze init.sh complexity
                    ─────────────
                    20.5k / 5.0k total
```

**Layer 4: Budget guard (optional, future)**

A `PWORK_HOOK_TOKEN_LIMIT` config option that kills a hook session if it exceeds a threshold. Not in v1, but the tracking infrastructure makes this easy to add.

### What we validate

1. **Tokens are captured** — After each hook completes, `p-hooks <id>` shows non-zero token counts
2. **Totals are correct** — `p-hooks` aggregate matches sum of individual hooks
3. **Runaway detection** — If a hook is still `running` after an unusually long time (configurable, default 10min), `p-hooks` shows a warning

## Stop Hook Prompt Eval Strategy

### The Problem

The Stop hook's Haiku prompt must:
1. **Detect spinnable tasks** — when the conversation surfaced work that could run in parallel
2. **Avoid false positives** — not suggest tasks when the conversation is self-contained or the user is mid-thought
3. **Produce actionable output** — suggestions must be specific enough to pass directly to `p-hook`
4. **Handle tool-call context well** — recognize patterns like "multiple CLI commands run manually" or "files edited that lack tests"

Since this is a judgment call made by Haiku on extracted context, we need evals to tune the prompt.

### Eval Framework

`evals/stop-hook/` — a lightweight bash-based eval harness (no Python deps, consistent with project conventions).

#### Structure

```
evals/stop-hook/
  run-evals.sh          # harness: runs each case, scores, reports
  prompt.txt            # the current prompt template (single source of truth)
  cases/
    01-cli-commands.json      # input context + expected outcome
    02-test-gap.json
    03-mid-conversation.json
    04-simple-question.json
    05-docs-opportunity.json
    06-refactor-mention.json
    07-already-complete.json
    08-ml-assumption.json
    09-config-only.json
    10-error-debugging.json
```

#### Test Case Format

Each case is a JSON file:
```json
{
  "name": "CLI commands that should be scripted",
  "description": "User ran 6 manual AWS CLI commands during deployment setup",
  "context": {
    "last_assistant_message": "I've finished setting up the ECS service. Here's a summary of what we did...",
    "tool_calls_summary": [
      {"tool": "Bash", "command": "aws ecs create-cluster --cluster-name prod"},
      {"tool": "Bash", "command": "aws ecs register-task-definition --cli-input-json file://task-def.json"},
      {"tool": "Bash", "command": "aws ecs create-service --cluster prod --service-name api"},
      {"tool": "Bash", "command": "aws logs create-log-group --log-group-name /ecs/api"},
      {"tool": "Bash", "command": "aws ecs update-service --cluster prod --service-name api --desired-count 2"},
      {"tool": "Edit", "file": "infrastructure/task-def.json"}
    ],
    "files_changed": ["infrastructure/task-def.json"]
  },
  "expected": {
    "should_suggest": true,
    "task_must_contain": ["script", "deploy"],
    "task_must_not_contain": ["rewrite", "refactor"]
  }
}
```

#### Eval Dimensions

Each case is scored on three dimensions:

| Dimension | How scored | Weight |
|-----------|-----------|--------|
| **Detection** (did it suggest when it should / stay silent when it shouldn't?) | Binary: correct / incorrect | 50% |
| **Specificity** (is the suggestion actionable enough for `p-hook`?) | 0-2 scale: vague (0), directional (1), ready-to-run (2) | 30% |
| **Restraint** (did it suggest exactly one task, not a laundry list?) | Binary: one task / multiple tasks | 20% |

#### Running Evals

```bash
./evals/stop-hook/run-evals.sh
```

The harness:
1. Reads `prompt.txt` (the Stop hook prompt template)
2. For each case in `cases/`:
   a. Builds the full prompt by injecting the case's `context` into the template
   b. Calls the Anthropic API with Haiku (same model the hook will use in production)
   c. Parses the response (`ok: true/false` + `reason`)
   d. Scores against `expected` criteria
3. Reports per-case pass/fail + overall score

```
Stop Hook Eval Results
======================
  ✓ 01-cli-commands          detect=✓  specific=2  restrain=✓  (100%)
  ✓ 02-test-gap              detect=✓  specific=2  restrain=✓  (100%)
  ✗ 03-mid-conversation      detect=✗  specific=—  restrain=—  (0%)
  ✓ 04-simple-question       detect=✓  specific=—  restrain=✓  (100%)
  ...
────────────────────
  8/10 passed  (80% overall, target: 90%)
```

#### The Eval Cases

Ten cases covering the critical decision boundary:

**Should suggest (true positives):**
1. **CLI commands → script** — Multiple manual bash commands run → suggest creating a script
2. **Test gap mentioned** — Claude says "this edge case isn't tested" → suggest writing tests
3. **Docs opportunity** — New functions added with no docstrings/readme updates → suggest docs
4. **ML assumption** — Claude says "assuming X, which we should verify" → suggest verification task
5. **Refactor mention** — Claude notes "this function is getting long" → suggest analysis

**Should NOT suggest (true negatives):**
6. **Mid-conversation** — User is still asking questions, conversation isn't at a natural break
7. **Simple question** — User asked "what does this function do?" → no task to spin off
8. **Already complete** — Claude finished the exact task requested, nothing outstanding
9. **Config-only change** — Small .env or config edit, nothing to spin off
10. **Error debugging** — Actively debugging a failure, user needs to stay focused

#### Prompt Iteration Workflow

1. Run evals: `./evals/stop-hook/run-evals.sh`
2. If below target (90%): examine failures, adjust `prompt.txt`
3. Re-run evals to confirm improvement
4. Version the prompt: `git log` tracks prompt changes alongside eval results

The eval harness makes prompt tuning empirical rather than guesswork. When someone wants to change the prompt, they run the evals to make sure the change doesn't regress.

### Token Cost of the Stop Hook Itself

The Stop hook fires on every `Stop` event (every time Claude finishes a response). This is frequent — potentially 10-50 times per session.

**Estimated per-invocation cost:**
- Input: ~500-800 tokens (prompt template + extracted context summary)
- Output: ~50-100 tokens (JSON response)
- At Haiku rates: roughly $0.0002-0.0004 per invocation

**Estimated per-session cost:**
- 20 stop events × $0.0003 = ~$0.006 per session
- This is negligible relative to the main conversation cost

**Mitigation for excessive firing:**
The command hook script includes a cooldown: if it already suggested a task in the last 5 minutes (tracked via a timestamp file), it exits immediately without making an API call. This prevents suggestion fatigue and reduces cost for long sessions.

## Design Decisions

**Why `type: "command"` over `type: "prompt"` for the Stop hook?** Prompt hooks only see `last_assistant_message` — they can't access tool call history or files changed. By using a command hook that parses the `transcript_path` JSONL, we get much richer context: which files were edited, which bash commands were run, what errors occurred. The tradeoff is making our own Haiku API call, but users already have `ANTHROPIC_API_KEY` set.

**Why also keep a standalone `p-hook` command?** The Stop hook suggests tasks; `p-hook` executes them. This separation means users can also run `p-hook` manually from any terminal, not just from within a Claude session. The core value is the manual command — the proactive layer is a bonus.

**Why opt-in?** Not every workspace needs proactive task suggestions. The Stop hook adds API calls at every turn end, which has cost implications. Making it opt-in (`PWORK_CLOUD_HOOKS=true`) keeps the default experience unchanged.

**Why files for task tracking?** Matches existing patterns (pwork.conf, workspaces registry). Simple to debug — `cat .parallel-work/hooks/001.env`. No dependencies.

**Why branch-per-hook?** Isolates hook work from whatever the clone was doing. Easy to review, merge, or discard.

**Why bash evals instead of Python?** The project is a shell toolkit. Keeping evals in bash means no additional dependencies and maintains the "one language" simplicity. The eval logic is just: call API, parse JSON, compare against expected.

## What This Doesn't Include (future work)

- **Hook chaining** — tasks that depend on each other
- **Auto-PR creation** — opening a PR from hook work
- **Conversation context forwarding** — passing full conversation history to the spawned session
- **Hook templates** — predefined types like "write tests", "write docs"
- **Desktop notifications** — could use Claude Code's `Notification` hook event
- **Token budgets** — `PWORK_HOOK_TOKEN_LIMIT` to auto-kill expensive hooks
