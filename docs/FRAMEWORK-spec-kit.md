---
title: "Spec Kit 0.16.4 for a KORUS build"
layout: default
---

# Spec Kit 0.16.4 for a KORUS build

## TLDR/BLUF

**What this is.** [Spec Kit](https://github.com/github/spec-kit) 0.16.4, released 2026-08-14, is
GitHub's toolkit for Spec-Driven Development. You write the spec, the plan and the task list down
instead of iterating in chat. This page maps its commands onto a [KORUS](KORUS.md) build.

**Why you should care.** It installs ten skill prompts plus a committed `.specify/` scaffold --
templates and scripts, no compiled logic, no gate. The active feature comes from a file there, not
your git branch, so two worktrees share one pointer. Not for you if you want the upstream tutorial.

**How to use it.** Start at [The flow](#the-flow) for the command order and which KORUS session runs
each one. Read [Feature state is a file, not a branch](#feature-state-is-a-file-not-a-branch) before
you cut a second worktree.

---

## What it is, measured

**Spec-Driven Development makes the written spec the source of truth, not the conversation.** Write
the requirement down first, then hold the agent to it. [KORUS](KORUS.md) recommends it as an
antidote to vibe coding's flaws.

Measured against an installation of `specify-cli` 0.16.4 on 2026-08-15:

| Component | What it is | Size |
|---|---|---|
| 10 skill prompts | `.claude/skills/speckit-<name>/SKILL.md` | 134,365 bytes of markdown |
| 5 templates | `.specify/templates/*.md` | copyable text |
| 6 PowerShell scripts | `.specify/scripts/powershell/` | 60,677 bytes |
| Directory convention | `specs/<NNN-slug>/` holding `spec.md`, `plan.md`, `tasks.md` | n/a |

**There is no compiled logic, no analyzer, and no gate.** Nothing it installs can fail a build,
block a commit, or reject a document. In a KORUS build, enforcement stays with your own CI -- see
[CI for leaders](CI-FOR-LEADERS.md) -- and with whichever session reviews the diff.

---

## How it holds state

### Feature state is a file, not a branch

This is the mechanic that matters most for a KORUS build, where every build session works in its
own worktree.

- The active feature resolves from `.specify/feature.json`, key `feature_directory`.
- `SPECIFY_FEATURE_DIRECTORY` overrides it. Priority is documented as: the environment variable,
  then `feature.json`, then an error.
- It does **not** resolve from the checked-out branch. `git checkout` alone does not retarget the
  commands.
- `create-new-feature` creates `specs/<NNN-slug>/` and `spec.md`, then saves that state. It runs no
  `git checkout -b`. Branch creation happens only through an optional hook or the opt-in git
  extension.

**Exactly one feature is active at a time** in one scope, where a scope is the directory tree the
commands search. Two build sessions on two features need two scopes. The next finding says when you
get them.

### It resolves per worktree, until the worktree has no .specify/

Measured on 2026-08-15 against `specify-cli` 0.16.4 in a repository using git worktrees.
`Find-SpecifyRoot` walks parent directories from the current one until it finds a `.specify/`
directory. Nothing in that walk consults git.

| Case | Result |
|---|---|
| Worktree whose branch carries the scaffold | Resolves to itself. Its own `feature.json`, no sharing |
| Worktree on a branch predating `specify init` | Resolves to the first ancestor holding `.specify/` |
| Two such worktrees nested under the primary | Both resolve to the primary and share one `feature.json` |

**Cut every KORUS build-session worktree from a branch that already carries `.specify/`.** The
scaffold is committed, so the worktree gets its own copy. `feature.json` is gitignored and stays
local to that checkout, so sessions do not collide.

**The trap.** A worktree cut from an older branch has no `.specify/` of its own, so the walk escapes
to the primary. A second such worktree overwrites the first session's feature pointer, and `git
status` stays clean in both: the pointer was never tracked.

[Sequence allocation](SEQUENCE-ALLOC.md) covers the same shape for feature numbering.

---

## Install and initialise

**The goal.** One scaffold, committed once, that every build-session worktree inherits.

**What to do.** Run this at the **root of the primary checkout**, then commit what it writes. The
`--here` form is load-bearing: without it, `specify init <name>` creates a new subdirectory and the
scaffold lands somewhere no worktree inherits. `uv` is a prerequisite; install it first.

```
uv tool install specify-cli
specify init --here --integration claude --script ps
```

**What happens next.** The ten commands land as skills and appear in the agent's slash list after it
restarts. Cut each build-session worktree from a commit that already carries `.specify/`. Running
`specify init` fresh in every worktree defeats the point: the scaffold is meant to be inherited.

| Fact | Detail |
|---|---|
| Agent selection | `--integration <key>`. The Claude Code key is `claude` |
| Where the commands land | `.claude/skills/speckit-<name>/SKILL.md`, one directory per command |
| New skills need a restart | The agent must reload before the commands appear in its slash list |
| `specify init` does not run `git init` | Version the project yourself first |
| It needs no git at all | A search for git across the 6 installed PowerShell scripts returns 2 comment lines |

---

## The flow

Two sequences are documented, verified against `main` and the **`v0.16.0`** tag's
`templates/commands` tree -- an earlier tag than the 0.16.4 the rest of this page measures. Nothing
in 0.16.1 through 0.16.4 was checked for a change to either order.

| Path | Sequence |
|---|---|
| Short, for smaller features | specify, plan, tasks, implement, converge |
| Full, for production work | constitution, specify, clarify, plan, checklist, tasks, analyze, implement, converge |

**The README's core-versus-optional grouping is not an execution order.** `taskstoissues` is grouped
core and appears in neither sequence. `clarify`, `checklist` and `analyze` are grouped optional and
sit inside the full path. Read the table above, not the grouping.

### Stage 1: The constitution

**The goal.** One rules document that every later step is checked against.

**What to do.** Run `/speckit-constitution [your rules]` in the console session, once, before any
feature work starts.

> `/speckit-constitution Python is our primary language. All source code must adhere to OWASP ASVS
> v5.0 Level 3 and NIST SSDF SP 800-218.`

**What happens next.** The agent writes `.specify/memory/constitution.md`. Every later planning,
coding and debugging step checks against it, twice: before Phase 0 research and again after Phase 1
design.

### Stage 2: Specify, then clarify

**The goal.** A spec that says WHAT and WHY, with its gaps closed before work fans out.

**What to do.** Run `/speckit-specify [feature requirements]`, then `/speckit-clarify [spec-name]`.
Both belong in the console session, where a human is still in the loop.

> `/speckit-specify We need a session orchestration service that integrates with our Git-backed
> database version control. It must handle temporary auth tokens and manage user sessions.`

**What happens next.** `specify` writes `specs/<NNN-slug>/spec.md`: overview, user stories,
acceptance criteria. No tech stack, no APIs, no code structure. `clarify` then checks that draft
against the constitution, asks targeted questions in chat, and folds your answers into `spec.md`.

**Nothing enforces that division except a self-check inside the skill prompt.** CI never sees it, so
a leaky spec produces an over-constrained document rather than an error.

### Stage 3: Plan, then tasks

**The goal.** HOW the feature gets built, plus the ordered work items to hand out.

**What to do.** Run `/speckit-plan [spec-name]`, then `/speckit-tasks [spec-name]`.

**What happens next.** The agent reads the spec and writes `specs/<NNN-slug>/plan.md`: HOW, not
WHAT. A `Technical Context` section holds language, storage and testing choices. A `Complexity
Tracking` table records any rejected alternative, populated only when the constitution check fails.

`plan.md` is architecture, not a checklist. The ordered work items are a separate artifact,
`specs/<NNN-slug>/tasks.md`, written by `tasks`. A KORUS console should read both before
splitting work across build sessions.

### Stage 4: Implement

**The goal.** Working code, one task at a time, inside one build session's worktree.

**What to do.** Run `/speckit-implement [spec-name]` in the build session holding that feature's
worktree.

**What happens next.** The agent works `tasks.md` top to bottom: code an item, write and run its
tests, fix on a failing test, check it off, move on. `taskstoissues` can turn the checklist into
tracked issues afterward.

`checklist` sits between plan and tasks in the full sequence, `analyze` between tasks and implement.
`checklist` builds a review checklist from the spec; `analyze` checks plan and tasks against the
constitution and writes `specs/<NNN-slug>/analysis.md`. Skip both on a short build.

### Stage 5: Handling requirement changes

**The goal.** Update the documents and let the code follow. Do not prompt the agent to "just fix the
code."

**What to do.**

1. Edit `spec.md` (yourself, or ask the agent to) to reflect the new requirement.
2. Re-run `/speckit-plan`, then `/speckit-tasks`.
3. Re-run `/speckit-implement` against the updated `tasks.md`.

**What happens next.** The agent diffs the new spec against the current plan and produces a targeted
checklist rather than a full rewrite.

### Stage 6: Converge, not "fix-findings"

**The goal.** Close the loop: find the work the documents say is unmet, and land it.

**What to do.** Run `/speckit-converge [spec-name]`. If it appends tasks, run `implement`, then
`converge` again.

**What happens next.** `converge` reads `spec.md`, `plan.md` and `tasks.md` as the sole source of
intent and appends unmet work to `tasks.md`. It never edits or deletes code. Outcomes are binary:
converged with `tasks.md` unchanged, or N tasks appended.

There is no `/speckit-fix-findings` command and no `specs/findings.fixed.md` log in the installed
10-skill set, checked against the live `templates/commands/` directory on 2026-08-16.

**Its own description says it assesses the codebase against those three documents. Measured, it
assesses the three documents against each other.** One build carried 22 requirements, 65 tasks and
85 tests through the full flow, then ran `converge` three times:

| Pass | Findings | Changed code |
|---|---|---|
| `analyze` | 8 | 0 |
| converge 1 | 7 | 1 |
| converge 2 | 5 | 1 |
| converge 3 | 4 | 0 |

2 of those 24 findings changed application code. None was a feature that did not work: no round
found an unimplemented requirement, a failing test, or behavior contradicting the spec. The other 22
described decisions already made, left behind by a later, correct decision.

Run it more than once -- the drift it catches is generated by the fixes you just made. If it reports
a missing feature, the task list was wrong rather than the code.

### A citation count is not a coverage claim

From the same build, a mechanical scan for requirement IDs in task text reported 40% coverage.
Reading each uncited requirement by hand showed 87%: the scan measured citation, not coverage. If a
KORUS build reports coverage from a requirement-ID grep, read the uncited items first.

### Which KORUS session runs which stage

| Stage | KORUS session |
|---|---|
| constitution, specify, clarify | Console. One human-reviewed pass before work fans out |
| plan, tasks | Console, or the builder the console hands the feature to |
| implement | The build session holding that feature's worktree |
| checklist, analyze, converge | The same build session, before it hands the feature back |
| taskstoissues | Console, if an issue tracker is in the loop |

The lander session is not involved. Spec Kit's artifacts live in the worktree and merge like any
other file. Nothing about `feature.json` reaches git, so the lander session's push-and-merge job is
unaffected.

---

## What failed verification

Two claims in circulation read as plausible and are not true of 0.16.4:

| Claim | Why it is wrong |
|---|---|
| `specify init --ai claude` selects the agent | Removed at v0.10.0. `--integration` replaced it |
| `/speckit-specify` creates the git branch automatically | It creates the directory only. Branch creation is opt-in, through a hook or extension |

A third belongs here from this page's own history. An earlier draft described a
`/speckit-fix-findings` command and a `specs/findings.fixed.md` log in the debugging stage. Neither
exists in the shipped template set -- see Stage 6, above.

---

## What it does not give you

Adopt the practices without the tool and you lose no capability: templates are copyable files,
commands are prompts, scripts create directories. Two things survive that test. Someone else
maintains 134KB of prompt text, and the vocabulary is legible to another session or seat.

Published criticism is cost criticism, not correctness criticism. It reports specs bloated with
generated text, and hours spent correcting generated specs on brownfield systems. No source disputes
a mechanical fact above.

**There is no architecture decision record (ADR) command.** `templates/commands/` holds no
`adr.md`. `plan.md`'s Complexity Tracking table records a rejected alternative when the constitution
check fails; it is not a decision log. Write ADRs as work lands, as [KORUS](KORUS.md) advises.

A fork, `panaversity/spec-kit-plus`, adds a native ADR command at `history/adr/NNNN-slug.md`.

Two catalog extensions were checked against this gap in an earlier pass, and the pass got one of
them wrong. The `adrkit` kill held: a compound claim whose weakest conjunct was undocumented.

The `spec-kit-arch-governance` kill did not hold. Its catalog entry requires
`speckit_version >=0.1.0`, which admits every 0.16 release, so the claim three verifiers
unanimously killed was true. See [a claim three verifiers refuted](CASE-STUDY-refuted-but-true.md)
before reaching for either.

**A Spec-Kit-shaped hole is not always a hole in your organisation.** Check what already covers the
requirement, here KORUS's own ADR habit, before installing something to fill it again.

---

## A decision rule

**Use the full sequence** when the feature is long enough that chat guidance would decay first, or
sprawling enough to need a what-before-how gate. In a KORUS build the other trigger is already true:
the work is always handed to another session.

**Use the short path** -- `specify`, `plan`, `tasks`, `implement`, `converge`. Take it when the
feature's own spec and plan would outweigh the code, or when a reviewer was already reading
every diff. That drops `constitution`, `clarify`, `checklist` and `analyze`.

**Set an exit condition when you start.** If `specify` and `clarify` produce a document that reads
as padding rather than decisions the console would defend, stop and build directly.

---

## Where the evidence runs out

No source addresses how Spec Kit's skill prompts interact with an existing `CLAUDE.md`, with
pre-existing skills, or with subagent delegation. That matters for a KORUS build, whose build
sessions already run their own sub-session workflows.

Whether an MVP should be one feature or several is also not established. Treat both as open until
you measure them against your own build.

---

## Provenance, and how to re-check

Install mechanics, flow sequences, and the feature-state resolution above rest on the installed code
or on primary sources.

To re-check any of it, in descending order of reliability:

- run `specify --version`;
- read the installed `.claude/skills/*/SKILL.md` and `.specify/scripts/`;
- read `.specify/integration.json`;
- then consult an external write-up.

The command list was re-verified against `github/spec-kit` `main` on 2026-08-16, against the same
`v0.16.4` release this page already covered.
