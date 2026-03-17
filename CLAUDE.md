# CLAUDE.md — quotatool project instructions

## *** KVM CAPABILITY CHECK — DO THIS FIRST ***

Testing requires KVM virtualization. At the start of EVERY session,
check that `/dev/kvm` exists and is accessible. If not:

```
╔══════════════════════════════════════════════════════════════╗
║  WARNING: NO KVM!  Testing requires /dev/kvm for             ║
║  QEMU/virtme-ng VM-based kernel testing.                     ║
║                                                              ║
║  Simple edits (README, docs, planning) are fine, but         ║
║  anything involving build, test, or VM work needs KVM.       ║
╚══════════════════════════════════════════════════════════════╝
```

Print this banner and wait for user acknowledgement before proceeding.

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
- Test suite: `test/run-tests` — VM-based multi-kernel testing
  (25 kernels, ext4 + XFS, requires KVM). See `test/run-tests --help`.

## Conventions

- Org-mode for all planning and research documents
- Git commits: descriptive, one logical change per commit
- Branches for non-trivial work
- Do not push without explicit permission
- **Never install system packages** (dnf, pip, npm, etc.) — tell the
  user what needs installing and let them do it

## Minimal Dependencies

**ENFORCED**: Every tool, command, or library used must justify its
existence. Before reaching for any external command, ask: can this be
done with what we already require?

The test framework's dependency stack is deliberately minimal:
- **bash** — test scripts, control flow, parsing
- **python3** — required by virtme-ng (already a hard dep)
- **busybox** — our own static binary, used by both initramfs and vng
- **coreutils** — basic system tools (present on every Linux)
- **qemu / vng** — VM infrastructure (the core requirement)

When writing new code:
1. **Reuse first.** If bash, python3, or busybox can do it, use them.
   Don't add `jq` when python3 can parse JSON. Don't add `getent`
   when bash can read `/etc/passwd` directly.
2. **No gratuitous dependencies.** Every new tool is a portability
   risk, a failure mode, and a thing the user must install. Future
   distros will drop, rename, or split packages (cf. `script` on
   Fedora).
3. **Think cross-distro.** Don't assume package names, group names,
   file paths, or tool availability. What works on Debian may not
   exist on Fedora, and vice versa. Test on both.
4. **Degrade gracefully.** If an optional tool is missing, skip or
   warn — don't crash.

## Complex Bash Commands

**ENFORCED**: Never run multi-step or complex bash commands directly via
the Bash tool. Instead, write them to `test/tmp_run.sh` and run that.
This avoids repeated permission prompts (user has `test/tmp_run.sh`
pre-approved) and makes commands reviewable.

```bash
# Write the commands to tmp_run.sh, then:
bash test/tmp_run.sh
```

`tmp_run.sh` is gitignored — it's a scratch file, not committed.
