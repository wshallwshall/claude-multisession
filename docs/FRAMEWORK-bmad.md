---
title: "BMAD 6.11.0, evaluated"
layout: default
---

# BMAD 6.11.0, evaluated

## TLDR/BLUF

**What this is.** [BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) 6.11.0, published
2026-08-15, installed and measured against Claude Code the same day. It answers the same questions
in the same order as [Spec Kit](FRAMEWORK-spec-kit.md), so the two read side by side.

**Why you should care.** It commits 49 skills and 3.0MB into `.claude/skills`, none of it
gitignored. Run from the wrong directory it stops with an error rather than binding to the wrong
scaffold. Not for you if you want a tutorial: read the upstream docs.

**How to use it.** If you run concurrent sessions, start at
[How it holds state](#how-it-holds-state). Every claim below is marked measured or researched, and
two answers remain unestablished and say so.

---

## What it is, measured

Measured against `bmad-method@6.11.0` installed with `--tools claude-code --modules bmm` on
2026-08-15:

| Component | Where | Size |
|---|---|---|
| 49 skills | `.claude/skills/bmad-<name>/` | 2,146,676 bytes of skill text, 3.0MB on disk |
| Framework core | `_bmad/` | 196KB, 21 files |
| Output tree | `_bmad-output/` | Created empty. Holds planning and implementation artifacts |
| Executable logic | 27 Python scripts across `_bmad/scripts/` and skill `scripts/` | Includes unit tests |

**There is executable logic here, and that is the sharpest difference from Spec Kit.** Spec Kit
installs prompts and path resolution only. BMAD ships Python that parses YAML, writes files
atomically, and shells out to git, with its own tests beside it.

Nothing in it is still a gate. No installed script can fail a build, block a commit, or reject a
document. The Python serves the skills rather than policing the repository.

`.claude/skills` is not gitignored by the installer. Adopting BMAD commits 248 files and 3.0MB into
the repository unless you add a rule yourself.

The 49 skills, enumerated:

```
bmad-advanced-elicitation      bmad-agent-analyst           bmad-agent-architect
bmad-agent-dev                 bmad-agent-pm                bmad-agent-ux-designer
bmad-architecture              bmad-brainstorming           bmad-build
bmad-build-auto                bmad-checkpoint-preview      bmad-code-review
bmad-correct-course            bmad-create-architecture     bmad-create-epics-and-stories
bmad-create-prd                bmad-create-story            bmad-customize
bmad-deep-recon                bmad-dev-auto                bmad-dev-story
bmad-document-project          bmad-domain-research         bmad-edit-prd
bmad-editorial-review          bmad-editorial-review-prose  bmad-editorial-review-structure
bmad-forge-idea                bmad-generate-project-context bmad-help
bmad-market-research           bmad-party-mode              bmad-prd
bmad-prfaq                     bmad-product-brief           bmad-project-context
bmad-qa-generate-e2e-tests     bmad-quick-dev               bmad-retrospective
bmad-review                    bmad-review-adversarial-general
bmad-review-edge-case-hunter   bmad-review-verification-gap bmad-spec
bmad-sprint-planning           bmad-sprint-status           bmad-technical-research
bmad-ux                        bmad-validate-prd
```

---

## How it holds state

Two findings, pointing opposite ways. Both measured on 2026-08-15 against the installed tree.

### Project-root resolution is fail-closed

**BMAD looks for its scaffold in one place: the directory you ran the skill from.** That is what
`{project-root}` means here. `load_central_config` in `_bmad/scripts/config_utils.py` resolves
`project_root / "_bmad"` and loads `config.toml` with `required=True`. It does not walk parent
directories.

Run it from a worktree whose branch predates the scaffold -- the case that silently mis-binds Spec
Kit to the shared primary -- and it stops:

```
error: required TOML file not found: .../.worktrees/legacy/_bmad/config.toml
```

**That is the correct behaviour and it is worth naming.** The failure that costs a reader time is
the one returning a confident wrong answer. This one prints the path it wanted and stops, so a
session that has strayed finds out immediately.

### The work-item state has no lock

Active work lives in `_bmad-output/implementation-artifacts/sprint-status.yaml`, from the
`implementation_artifacts` key in `_bmad/config.toml`.

`_atomic_write` in `sprint_status.py` is careful about crashes. It writes to a temp file alongside
the target, fsyncs, restores the target's permission bits, renames over it, then fsyncs the
directory. A kill or a full disk leaves the original intact.

**It is crash-atomic, not concurrency-safe, and those are different properties.** `_load_document`
reads at line 455 and `_atomic_write` writes at line 561. The read and the write are separate
operations with no lock between them.

A search of every Python file for `flock`, `fcntl`, `lockf`, `O_EXCL` or a lockfile returns nothing.
Two writers racing between that read and that write lose one update. That is the shape
[Sequence allocation](SEQUENCE-ALLOC.md) records: the check and the write were never one operation.

### Why the collision is loud rather than silent

`sprint-status.yaml` is not gitignored. It is committed, so it travels with the branch and each
worktree carries its own copy.

Two sessions in two worktrees therefore diverge into a merge conflict, which git reports. Spec Kit
is the opposite: its pointer is gitignored and shared through a parent-directory walk, so the
divergence is invisible.

**Limit: the lost-update window is two writers in one worktree, not two worktrees.** That is the
case a worktree per session already prevents, so the residual risk is one worktree driven by two
sessions at once.

**Limit: this was measured on Linux by running the shipped scripts directly, not by driving a live
agent session.** Nothing here is a claim about what an agent does with the state, only about what
the scripts do to it.

### Somebody built the concurrency story separately

The strongest corroboration is an artifact that exists. `thbst16/bmad-parallel-development` is a
third-party Claude Code skill for running BMAD stories in parallel across git worktrees, found by a
research pass on 2026-08-15.

Core BMAD ships no such thing. That skill's rules read as manual compensations for its absence:

- story files must be created on main before the worktrees exist;
- one agent takes one story;
- phases run sequentially;
- cleanup is mandatory before the next set.

Its state is a hand-maintained bash file mapping story ids to branches, and its worktrees are
created by a shell script. **That script is the only place git is invoked at all**, and it is
external to BMAD rather than one of its agents.

That is independent evidence for the measurement above. Isolation comes from a human naming stories
into disjoint modules and from separate directories, not from any mechanism the framework provides.

---

## Install and initialise

**The goal.** The scaffold in your project root and the Claude Code skills installed, with no
interactive prompts.

**What to do.**

```
npx bmad-method@6.11.0 install --yes --tools claude-code --modules bmm --directory .
```

**What happens next.** The installer writes `_bmad/` in the project root and reports it on success,
creates `_bmad-output/` empty, and adds 49 skill directories under `.claude/skills/`. None of that
is gitignored, so write the ignore rule before you commit.

| Fact | Detail |
|---|---|
| Selecting Claude Code | `--tools claude-code`. `--list-tools` prints the valid IDs |
| Non-interactive | `--yes`, and `--tools` is then required for a fresh install |
| Module selection | `--modules bmm` for BMad Method. `bmb` is the builder module |
| Where artifacts land | `.claude/skills/bmad-<name>/`, one directory per skill |
| Output folder | `--output-folder`, default `_bmad-output` |
| Config without prompts | `--set <module>.<key>=<value>`, repeatable. `--list-options` prints the keys |
| Install target | `_bmad/` in the project root, reported by the installer on success |

`npm view bmad-method` on 2026-08-15 gave 6.11.0 as `latest`, 4.39.0 tagged `rollback`, and
6.11.1-next.14 tagged `next`. The version is recorded on disk in `_bmad/config.toml`.

---

## The flow

**The documented persona order is still not established.** A research pass read the changelog and
the release feed and surfaced no upstream statement of a phase sequence, so this page states none.

The installed tree names six agent personas: analyst, architect, dev, pm, ux-designer, and the
party-mode aggregator. Artifact-shaped skills sit beside them for PRD, architecture, epics and
stories, sprint planning and retrospective.

That is an inventory, not an order. Do not infer a sequence from it: the Spec Kit page records that
upstream's own core-versus-optional grouping is not an execution order either.

### The persona set moved in the release before this one

From the changelog, read at `main` on 2026-08-15. v6.11.0 shipped 2026-08-09 and renamed
`bmad-quick-dev` to `bmad-build`, and `bmad-dev-auto` to `bmad-build-auto`. The same release:

- consolidated three developer personas into one Developer agent;
- retired the tech-writer persona;
- merged three research skills into `bmad-deep-recon`;
- merged the editorial skills into one `bmad-review`;
- deprecated `bmad-create-story` and `bmad-dev-story`.

**Measured against the install: both sides of every one of those renames ship together.**
`bmad-quick-dev` and `bmad-build` are both present, as are `bmad-dev-auto` and `bmad-build-auto`,
the three editorial skills alongside `bmad-review`, and both deprecated story skills.

So the 49-skill surface counted above carries superseded names as well as current ones. A reader
following a tutorial written before 2026-08-09 finds the old skill directory still installed.

---

## What failed verification

No adversarial pass ran, so nothing here is a vote. These are claims a research pass found
contradicted by a primary source, each with the source named.

| Published claim | What the source shows |
|---|---|
| The project folder is `.bmad-core/` | v6 installs to `_bmad/`. **Upstream's own `docs/core-architecture.md` still describes the v4 layout**, so the stale text is in the canonical repo |
| Claude Code artifacts land in `.claude/commands/` | Measured: they land in `.claude/skills/bmad-<name>/` |
| `bmad-quick-dev` and `bmad-dev-auto` are the current skills | Renamed at v6.11.0. Both old and new names install |
| Barry, Quinn and Bob are the developer personas | Consolidated into one Developer agent at v6.11.0 |
| Config lives in `core-config.yaml` | v6.11.0 moved configuration to a layered TOML system |

The v4 user guide most tutorials cite now returns 404, because v6 restructured the docs tree. That
is the mechanism behind the whole table: the material did not become wrong. Its subject moved, and
the old text stayed reachable through forks and reposts.

`rollback` on npm still points a major version back at 4.39.0, so a reader can install the layout
those tutorials describe and find them correct. Treat any BMAD write-up that does not name a version
as describing an unknown one.

---

## What it does not give you

The honest comparison is against adopting the practices: write a brief, a PRD and an architecture
document, break them into stories, and review each.

| Benefit | Weight |
|---|---|
| Someone else maintains 2.1MB of prompt text and patches it | Real, and larger than Spec Kit's 134KB |
| Executable helpers rather than prompts alone, with tests beside them | Real. Spec Kit has no equivalent |
| A vocabulary legible to another session or another seat | The strongest, as with any convention |

Against those, two measured costs: 3.0MB and 248 files committed into the repository, and 49 skills
added to the agent's surface whose context cost was not measured here.

### The reported cost is the context window

From upstream's own tracker, read 2026-08-15. Issue #1343, opened 2026-01-16, reports BMAD agents
consuming over 67% of a 200K context window **at activation**, before any work begins.

| Agent | Activation cost reported |
|---|---|
| TEA | ~172,750 tokens, 86% of the window |
| SM | ~22,130 tokens, 11% |
| DEV | ~19,830 tokens, 10% |

TEA's knowledge base alone is cited at 571KB, or roughly 143K tokens. The issue's stated goal is to
bring typical sessions under 30%. Issue #1235 reports excessive token usage in workflows separately.

**The issue names no version**, which is worth carrying: the skill consolidation at v6.11.0 cut the
core count from fourteen to eight, so these figures may predate it. They are the hardest numbers
published and they are unpinned.

**This is cost criticism, not correctness criticism.** No source found reports the framework
producing wrong output. It reports the framework eating the window before the work starts, the same
shape the Spec Kit page records for that tool.

One reception datum, worth its caveat. An independent comparison logs eight Hacker News submissions
between 2025-08 and 2026-03, scoring 4, 2, 2, 2, 2, 2, 1 and 1 with no comments on any. That is
against tens of thousands of GitHub stars. Forum quality, and it measures discussion, not use.

### No durable decision record, but it fails differently

Measured against the installed tree on 2026-08-15. No skill among the 49 is an ADR command. The only
occurrence of `ADR` anywhere in the install is a row in
`bmad-advanced-elicitation/assets/methods.csv`, an elicitation technique rather than a store.

`bmad-create-architecture/SKILL.md` contains no occurrence of `docs/adr`, `decision record`,
`superseded` or `immutable`.

**Its artifacts are project-scoped, which is where it differs from the sibling page.** A PRD and an
architecture document describe the project rather than one feature. BMAD is on the right side of the
scope axis where Spec Kit's `research.md` is on the wrong one.

It is on the same side of the other two. Those documents are regenerated and edited in place, with
no id, status, supersedes or superseded-by, so nothing records that a decision was replaced rather
than revised.

| | BMAD artifact | Spec Kit artifact | A decision record |
|---|---|---|---|
| Scope | per project | per feature | per project |
| Lifecycle | regenerated | regenerated | immutable once accepted |
| Correction | edit in place | edit in place | supersede, keeping the original |

Neither framework ships the mechanism [Sequence allocation](SEQUENCE-ALLOC.md) covers: a
project-scoped store whose numbers are handed out atomically and whose index is gated.

---

## A decision rule

Stated only where measurement or a named source supports it.

**Use it** where the executable helpers earn their place: sprint status tracked in a file that
survives a crashed write, and review skills you would otherwise write yourself.

**Skip it** where 3.0MB in the repository and 49 skills on the agent's surface outweigh a convention
you could adopt by writing three documents. That trade is legible without any further research.

If you run several sessions on one repository, the state mechanics above are not an argument against
it. Fail-closed resolution and a committed state file are both better behaved than the framework the
sibling page covers.

### Whether orchestration replaces it

They are not substitutes, because they fail in opposite directions. A fan-out across subagents
returns data and leaves nothing behind: those contexts end with the run. BMAD is sequential in one
context, and its whole output is files on disk.

So the question is what has to outlive the sitting. Breadth in one campaign is orchestration's
answer. Continuity across sittings, seats, and people who never open the agent is a framework's.

**Combining them is the case where the absent lock stops being inert.** BMAD's personas never run
concurrently, so its state file has one writer by construction. Fan-out manufactures the second, in
the same directory, against the same `sprint-status.yaml`.

Subagents share a working directory unless each is given its own worktree, and that isolation is
opt-in. So the default arrangement is the one that races.

**Limit: this reasons from measured mechanics, not from an observed failure.** The absent lock and
the shared working directory are both established above. Nobody here has watched two subagents race
that file.

---

## Where the evidence runs out

| Question | Status |
|---|---|
| The documented persona order and phase boundaries | Not established. No upstream statement of a sequence was found |
| Whether the reported activation costs apply to 6.11.0 | Not established. Issue #1343 names no version, and the skill consolidation postdates it |
| The context cost of these 49 skills on Claude's own surface | Not measured. Distinct from BMAD's agent activation figures |
| Brownfield versus greenfield difficulty | Not established. The cost material found is about context, not codebase shape |
| Behaviour under a live agent session | Not measured. The scripts were run directly |
| How it interacts with `CLAUDE.md` and pre-existing skills | Not established. The same gap the Spec Kit page records |

Two rows stay thinner than their counterparts on the sibling page: the flow, which states no persona
order, and the cost figures, which are unpinned to a version. The volume of measured detail above
should not disguise either.

---

## Provenance, and how to re-check

| Element | Figure |
|---|---|
| Version measured | 6.11.0, `latest` on npm on 2026-08-15 |
| Install measured | `--tools claude-code --modules bmm`, non-interactive |
| Established by running it | Sizes, counts, state paths, resolution behaviour, the worktree case, the renamed skills shipping together |
| Established by reading installed source | `_atomic_write` semantics, the absence of a lock |
| Established by a research pass | The changelog renames, the activation-cost figures, the parallel-development skill |

The measured half came from the installed tree and `npm view`. The researched half names its source
in every case, and no claim rests on model recollection.

**The research half used a refutation harness whose kill lists are not reliable.** See
[a claim three verifiers refuted](CASE-STUDY-refuted-but-true.md). Nothing above is stated because a
verifier rejected its opposite; each researched row names a document instead.

To re-check, in descending order of reliability:

- read `_bmad/config.toml` for the version and the artifact paths;
- read `_bmad/scripts/config_utils.py` for root resolution;
- grep the Python for a locking primitive;
- run the install in a scratch repository and compare.
