# CLAUDE.md — quotatool project instructions

## Session Start

**First priority: read `MASTERPLAN.org`** to understand the project,
which milestone is active, and what the current context is. Then
read the active milestone's step-plan in `steps/`. Never start
work without knowing where we are.

1. Read `MASTERPLAN.org` → active step-plan in `steps/`.
2. Read `.claude/session.md`. Orient. Report status briefly.
3. Check `/dev/kvm` is accessible (needed for VM-based testing).
   If not: warn the user, simple edits are fine but test/build needs KVM.

## Project

- Language: C (ANSI C, no external dependencies)
- Build: `./configure && make`
- Platforms: Linux (primary), FreeBSD, OpenBSD
- Test suite: `test/run-tests --help` (25 kernels, ext4 + XFS, KVM)

## Rules

### State Tracking

All state lives in files. LLM context is ephemeral — files are not.

- Update files at every checkpoint. No information exists only in
  conversation.
- No duplication. Each fact has one canonical location. Reference,
  don't copy.
- On cold start, a new session must recover fully from files alone.

| File/Dir           | Purpose                                    |
|--------------------|--------------------------------------------|
| MASTERPLAN.org     | High-level milestones, goal, current state |
| steps/NN-*.org     | Detailed step-plan per milestone           |
| research/*.org     | Background research (read-only reference)  |
| .claude/session.md | Session scratchpad (gitignored)            |
| CLAUDE.md          | This file — project instructions           |

### Scratch Scripts

**ENFORCED**: Never run multi-step bash commands directly via the
Bash tool. Write them to `test/tmp_run.sh` and run that. The user
has this file pre-approved — avoids permission prompts.

**This applies to agents too.** Any agent that needs to run bash
commands must use `test/tmp_run.sh`, not direct Bash calls.

`tmp_run.sh` is gitignored. Never commit it.

### Bug Fix Workflow

For any bug in `src/`:

1. **Reproduce first.** Write or update a test that catches the bug.
   Run it — confirm it fails.
2. **Fix the code.** Minimal change.
3. **Verify.** Run the test — confirm it passes. Run `--host-only`
   for no regressions.
4. **Human review.** Present the diff. User reviews in editor and
   tests manually with `--interactive`.
5. **Commit.** One logical change per commit.

Never fix code without first demonstrating the bug exists in a test.

### No Premature Conclusions

- Do not mark issues as "not a bug" or "kernel limitation" without
  thorough investigation. Demonstrate with evidence, not speculation.
- When something fails on one host but not another, bisect
  systematically. Don't guess.
- If stuck, say so honestly. Don't paper over confusion with
  workarounds.

### Testing

- Test on multiple hosts before release. Different distros catch
  different issues (mkfs versions, kernel behavior, package layout).
- Full matrix (`--all`) before any push that changes test framework
  or `src/` code.
- `--host-only` for quick verification during development.

### Conventions

- Org-mode for all planning and research documents
- TODO states: `TODO`, `DOING`, `WAITING`, `DONE`, `CANCELLED` only
- Git commits: descriptive, one logical change per commit
- Branches for non-trivial work
- Do not push without explicit permission
- **Never install system packages** — tell the user what to install
- **Never work around missing packages** — if a canonical tool is
  needed, install it. Don't build stubs, shims, or alternatives.
  Stop, tell the user, decide together.

### Dependencies

Keep the dependency stack minimal. Reuse bash, python3, busybox,
coreutils before adding anything new. Think cross-distro — what
works on Debian may not exist on Fedora. Degrade gracefully when
optional tools are missing.
