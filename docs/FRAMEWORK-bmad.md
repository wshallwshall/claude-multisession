---
title: "BMAD 6.11.0, evaluated"
layout: default
---

# BMAD 6.11.0, evaluated

## TLDR/BLUF

**What this is.** [BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) 6.11.0, published
2026-08-15, installed and measured the same day against Claude Code. It answers the same questions
in the same order as [Spec Kit](FRAMEWORK-spec-kit.md), so the two can be read side by side.

**Why you should care.** It puts 49 skills and 3.0MB into `.claude/skills`, and none of it is
gitignored. Its project-root resolution is fail-closed, which is the one place it is plainly better
than Spec Kit. Not for you if you want a tutorial: read the upstream docs.

**How to use it.** If you run concurrent sessions, start at
[How it holds state](#how-it-holds-state). Two rows of this page are unresearched and say so.

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
document; the Python serves the skills rather than policing the repository.

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

`{project-root}` is the working directory the skill is invoked from. `load_central_config` in
`_bmad/scripts/config_utils.py` resolves `project_root / "_bmad"` and loads `config.toml` with
`required=True`. It does not walk parent directories.

Run it from a worktree on a branch predating the scaffold, which is the case that silently mis-binds
Spec Kit to the shared primary, and it stops:

```
error: required TOML file not found: .../.worktrees/legacy/_bmad/config.toml
```

**That is the correct behaviour and it is worth naming.** The failure a reader of this site cares
about is the one that returns a confident wrong answer. This one returns an error with the path in
it, so a session that has strayed finds out immediately.

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
So two writers racing between that read and that write lose one update, which is the shape
[Sequence allocation](SEQUENCE-ALLOC.md) records: the check and the write were never one operation.

### Why the collision is loud rather than silent

`sprint-status.yaml` is not gitignored. It is committed, so it travels with the branch and each
worktree carries its own copy.

Two sessions in two worktrees therefore diverge into a merge conflict, which git reports. That is
the opposite of Spec Kit, whose pointer is gitignored and shared through a parent-directory walk, so
the divergence is invisible.

**Limit: the lost-update window is two writers in one worktree, not two worktrees.** That is the
case a worktree per session already prevents, so the residual risk is one worktree driven by two
sessions at once.

**Limit: this was measured on Linux by running the shipped scripts directly, not by driving a live
agent session.** Nothing here is a claim about what an agent does with the state, only about what
the scripts do to it.

---

## Install and initialise

```
npx bmad-method@6.11.0 install --yes --tools claude-code --modules bmm --directory .
```

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

**Not established.** The documented persona order was to come from a research pass that was stopped
before it reported, so this page does not state one.

What the installed tree shows is the skill set enumerated above, which names six agent personas
directly: analyst, architect, dev, pm, ux-designer, plus the party-mode aggregator. Artifact-shaped
skills sit beside them for PRD, architecture, epics and stories, sprint planning and retrospective.

That is an inventory, not an order. Do not infer a sequence from it: the Spec Kit page records that
upstream's own core-versus-optional grouping is not an execution order either.

---

## What failed verification

**Not established.** No verification pass ran against published BMAD material, so this page kills no
claims and should not be read as endorsing any.

The Spec Kit pass found 9 of 25 claims false, 3 of them true in an earlier release. BMAD 6.11.0
shipped the day this page was written, and its `rollback` tag points a major version back at 4.39.0.
Treat any BMAD write-up predating mid-2026 as unverified here.

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

**Practitioner criticism was not researched.** The Spec Kit page could weigh cost against
correctness because discussion threads had been read. Nothing equivalent backs this page.

---

## A decision rule

Only the part supported by measurement is stated. The rest waits on the research this page did not
get.

Use it where the executable helpers earn their place: sprint status tracked in a file that survives
a crashed write, and review skills you would otherwise write yourself.

Skip it where 3.0MB in the repository and 49 skills on the agent's surface outweigh a convention you
could adopt by writing three documents. That trade is legible without any further research.

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
| The documented persona order and phase boundaries | Not established. The research pass was stopped before reporting |
| Which published claims about BMAD are false for 6.11.0 | Not established. No verification pass ran |
| Practitioner-reported cost: context, bloat, brownfield difficulty | Not established |
| The context cost of 49 skills on an agent's surface | Not measured. The same gap the Spec Kit page records for 10 |
| Behaviour under a live agent session | Not measured. The scripts were run directly |

Four of the nine lens rows are therefore thinner than their counterparts on the sibling page. The
volume of measured install detail above should not disguise that.

---

## Provenance, and how to re-check

| Element | Figure |
|---|---|
| Version measured | 6.11.0, `latest` on npm on 2026-08-15 |
| Install measured | `--tools claude-code --modules bmm`, non-interactive |
| Established by running it | Sizes, counts, state paths, resolution behaviour, the worktree case |
| Established by reading installed source | `_atomic_write` semantics, the absence of a lock |
| Established by verification | Nothing. No pass ran |

Everything on this page came from the installed tree or from `npm view`. No blog post, tutorial or
model recollection contributed to it, which is why the unresearched rows are empty rather than
plausible.

To re-check, in descending order of reliability:

- read `_bmad/config.toml` for the version and the artifact paths;
- read `_bmad/scripts/config_utils.py` for root resolution;
- grep the Python for a locking primitive;
- run the install in a scratch repository and compare.
