---
name: writing-github-issues
description: Write well-structured GitHub issues for parallel-work. Use when the user wants to file a bug report, request a feature, report unexpected behavior, or draft a GitHub issue.
---

# Writing GitHub Issues for parallel-work

## Before Writing

1. **Reproduce the problem** (for bugs) — run the command again, note the exact output.
2. **Search existing issues** — use `gh issue list -R liamsc/parallel-work --search "<keywords>"` to avoid duplicates.
3. **Identify the category** — bug report, feature request, or question.

## Issue Templates

### Bug Report

Use this structure:

```markdown
**What happened**
One or two sentences describing the unexpected behavior.

**Steps to reproduce**
1. Run `p-init git@github.com:org/repo.git ~/path --clones 3`
2. `cd ~/path/p1`
3. Run `p-status`
4. Observe: <what you see>

**Expected behavior**
What you expected to happen instead.

**Environment**
- OS: <macOS version / Linux distro>
- Shell: <bash / zsh + version>
- gh CLI: <version or "not installed">
- parallel-work: <commit hash or "installed via install-remote.sh">

**Logs / output**
<paste terminal output in a fenced code block>
```

### Feature Request

```markdown
**What would you like?**
One or two sentences describing the desired behavior.

**Why is this useful?**
The workflow or pain point this addresses.

**Suggested approach** (optional)
If you have an idea for how it could work — commands, flags, behavior.
```

### Question / Discussion

```markdown
**Question**
What you're trying to understand or accomplish.

**Context**
What you've already tried or read.
```

## Writing Guidelines

- **Title**: Start with the command name if relevant (e.g., "p-clean: doesn't detect merged PRs from forks"). Keep it under ~70 characters.
- **Be specific**: Include exact commands, exact error output, and exact OS/shell details. "It doesn't work" is not actionable.
- **Minimal reproduction**: Strip the report down to the fewest steps that trigger the issue. Don't include unrelated workspace setup.
- **One issue per issue**: If you hit two separate bugs, file two separate issues.
- **Use fenced code blocks** for all terminal output, commands, and config snippets.
- **Label hints**: If you know the affected area, mention it — e.g., "This is in `lib/gh.sh`" or "Relates to the `p-status` command". Don't worry about applying GitHub labels yourself.

## Creating the Issue

Use the `gh` CLI to file directly from the terminal:

```bash
gh issue create -R liamsc/parallel-work \
  --title "p-clean: <concise summary>" \
  --body "$(cat <<'EOF'
<issue body here>
EOF
)"
```

Or if you prefer to draft interactively:

```bash
gh issue create -R liamsc/parallel-work
```

## Checklist Before Submitting

- [ ] Title is concise and mentions the relevant command (if applicable)
- [ ] Bug reports include reproduction steps and environment info
- [ ] Terminal output is in fenced code blocks
- [ ] Searched for duplicates first
- [ ] One issue per report
