# Contributing

Thanks for your interest! This is primarily a personal project that I maintain for my own workflow, but you're absolutely welcome to fork it and make it your own.

If you'd like to open a PR, feel free — I'll do my best to review it when I can, though response times may vary. For anything beyond small fixes, opening an issue first to discuss the idea is a good call.

## Code style

- Keep code simple and easy to read — favor clarity over cleverness
- Keep files small and focused
- Add comments that explain the *why* and *how* behind commands, not just the *what*

Full code style guidelines, architecture docs, and conventions are in [`CLAUDE.md`](CLAUDE.md). Read it before making changes — it's the source of truth for how this codebase is structured.

## Making changes

1. Fork + branch
2. Read [`CLAUDE.md`](CLAUDE.md) to understand the architecture and conventions
3. Make changes
4. Run `./test.sh` — all tests must pass
5. Open a PR

## For AI agents

If you're an AI coding agent (Claude Code, Cursor, Copilot, etc.) working on this repo:

1. **Start with [`CLAUDE.md`](CLAUDE.md)** — it contains the full architecture map, naming conventions, code style guide with good/bad examples, and a simplicity checklist. Treat it as your primary reference.
2. **Follow the naming conventions** — internal functions use `_pwork_` prefix, user commands use `p-` prefix, config variables use `PWORK_` prefix.
3. **Keep files small** — each file in `lib/` has a single responsibility. If you're adding a new command, create a new file in `lib/commands/`. Don't grow existing files beyond ~150 lines.
4. **Add bash-newbie comments** — annotate non-obvious shell syntax (test operators, redirections, parameter expansion, sort flags, etc.) with inline comments. Skip comments for things that read like English.
5. **Run `./test.sh`** before finishing — all tests must pass. Tests live in `tests/` and use the helpers in `tests/helpers.sh`.
6. **Don't over-engineer** — read the simplicity checklist in `CLAUDE.md`. If you can delete it, delete it. If you can inline it, inline it.
