# CLAUDE.md — quotatool project instructions

## First Priority: Consult MASTERPLAN.org

Before any work, read `MASTERPLAN.org` to determine which milestone is
active and what the current context is. Then read the active milestone's
step-plan in `steps/`. Never start work without knowing where we are.

## State Tracking

This is the #1 concern. LLM context is ephemeral — files are not.

- **All state lives in files.** Never rely on conversation context alone.
- **Update files at every checkpoint.** After completing a task, finishing
  research, or making a decision — write it down immediately.
- **No duplication.** Each piece of information has one canonical location.
  Reference it, don't copy it. Duplication causes conflicts and confusion.
- **Alignment.** When updating one file, check that related files still
  agree. Decisions, status, and progress must be consistent across
  MASTERPLAN.org, the active step-plan, session.md, and research docs.
- **Survive everything.** Files must be self-sufficient. A cold start
  (new session, context cleared, auto-compacted) must be recoverable
  by reading the files alone. No information exists only in conversation.
- **On session start:** Read MASTERPLAN.org, the active step-plan, and
  .claude/session.md. Orient. Report status briefly.

### File layout

| File/Dir         | Purpose                                        |
|------------------|------------------------------------------------|
| MASTERPLAN.org   | High-level milestones, goal, current state     |
| steps/NN-*.org   | Detailed step-plan per milestone               |
| research/*.org   | Background research (read-only reference)      |
| .claude/session.md | Session-level scratchpad (what just happened) |
| CLAUDE.md        | This file — project instructions for Claude    |

## Org-mode Conventions

All planning and research documents use org-mode. Follow these rules:

### TODO States

Use only these keywords. They are styled by the org-render skill
and must be used consistently across all org files.

| Keyword     | Meaning                              | Rendered as   |
|-------------|--------------------------------------|---------------|
| `TODO`      | Not started                          | Red badge     |
| `DOING`     | In progress                          | Blue badge    |
| `WAITING`   | Blocked or deferred, needs something | Amber badge   |
| `DONE`      | Completed                            | Green badge   |
| `CANCELLED` | Skipped or abandoned                 | Grey badge    |

Do NOT use other keywords (WIP, BLOCKED, SKIP, DEFER, RESOLVED, etc.).
Map to the above: WIP→DOING, BLOCKED→WAITING, SKIP→CANCELLED,
DEFER→WAITING, RESOLVED→DONE.

### Tags

Org tags on headings (`:tag:`) are supported and render as purple
badges. Use for categorization where helpful.

## Project Details

- Language: C (ANSI C, no external dependencies)
- Build: GNU autoconf + Make (`./configure && make`)
- Platforms: Linux (primary), FreeBSD, OpenBSD
- No test suite yet (M1 milestone will create one)

## Conventions

- Org-mode for all planning and research documents
- Git commits: descriptive, one logical change per commit
- Branches for non-trivial work
- Do not push without explicit permission
