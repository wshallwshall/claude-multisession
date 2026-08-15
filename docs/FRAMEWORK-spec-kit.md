---
title: "Spec Kit 0.16.4, evaluated"
layout: default
---

# Spec Kit 0.16.4, evaluated

## TLDR/BLUF

**What this is.** [Spec Kit](https://github.com/github/spec-kit) 0.16.4, released 2026-08-14,
evaluated on 2026-08-15 against a real installation and by adversarial verification of published
sources. Claims went to a 3-vote refutation panel, and the 9 it killed are listed in full below.

**Why you should care.** It installs a skill prompt per command into `.claude/skills/`, and its
state resolver never calls git. On a worktree per session that resolver can bind two sessions to one
feature pointer, measured below. Not for you if you want a tutorial: read the upstream quickstart.

**How to use it.** If you run concurrent sessions, start at
[Feature state is a file, not a branch](#feature-state-is-a-file-not-a-branch). Everything else here
is background you can take or leave.

---

## How the claims were graded

| Element | What it means |
|---|---|
| `3-0` | 3 verifiers were asked to refute the claim; none could |
| `0-3` | All 3 refuted it. The claim is dead |
| `1-2` | Split. The surviving wording is narrower than the claim as written |
| Measured | Established by running the thing on 2026-08-15, not by reading about it |

Verifiers were prompted to refute rather than confirm, and a majority refutation kills a claim. One
ran a leading-the-witness control: it re-fetched a source under a deliberately neutral prompt and
compared, to catch a summariser agreeing with whatever it was asked.

---

## What it is, measured

Measured against an installation of `specify-cli` 0.16.4 on 2026-08-15:

| Component | What it is | Size |
|---|---|---|
| 10 skill prompts | `.claude/skills/speckit-<name>/SKILL.md` | 134,365 bytes of markdown |
| 5 templates | `.specify/templates/*.md` | copyable text |
| 6 PowerShell scripts | `.specify/scripts/powershell/` | 60,677 bytes |
| Directory convention | `specs/<NNN-slug>/` holding `spec.md`, `plan.md`, `tasks.md` | n/a |

`common.ps1` is 34,245 of those 60,677 bytes and is mostly path resolution. The other five scripts
create a directory, write a JSON pointer, and resolve template layers.

**There is no compiled logic, no analyzer, and no gate.** Nothing it installs can fail a build,
block a commit, or reject a document. That fact sizes what the tool buys, and upstream does not
state it plainly.

`/speckit.converge` is the most mechanical-sounding command in the set. It is a 12,702-byte markdown
prompt telling the model to read three files and append findings to a fourth.

---

## Feature state is a file, not a branch

2 of the 9 claims killed below get this mechanic wrong, because it changed. It is also the one that
matters for running several sessions on one repository.

- The active feature resolves from `.specify/feature.json`, key `feature_directory`.
- `SPECIFY_FEATURE_DIRECTORY` overrides it. `Get-FeaturePathsEnv` documents its priority as the
  environment variable, then `feature.json`, then an error.
- It does **not** resolve from the checked-out branch. `git checkout` alone does not retarget the
  commands, and `Get-CurrentBranch` invokes no git command.
- `create-new-feature` creates `specs/<NNN-slug>/` and `spec.md`, then saves that state. It runs no
  `git checkout -b`.
- Branch creation happens only through an optional `before_specify` hook or the opt-in git
  extension, and the branch name does not dictate the spec directory name.

Three variables must not be conflated: `SPECIFY_FEATURE` is a name label,
`SPECIFY_FEATURE_DIRECTORY` is the directory, and `SPECIFY_INIT_DIR` is the project.

**Exactly one feature is active at a time.** The directory scheme supports `specs/001-*` beside
`specs/002-*`, but each run targets one, and switching is a state-file edit rather than a checkout.

### It resolves per worktree, until the worktree has no `.specify/`

Measured on 2026-08-15 against `specify-cli` 0.16.4, using the shipped resolver in a real repository
with git worktrees. The PowerShell and bash parities implement the same walk.

`Get-RepoRoot` tries `SPECIFY_INIT_DIR`, then `Find-SpecifyRoot`, then falls back to the script's own
location. `Find-SpecifyRoot` walks parent directories from the current one until it finds a
`.specify/` directory. Nothing in that chain consults git.

| Case | Measured result |
|---|---|
| Worktree whose branch carries the scaffold | Resolves to itself. Its own `feature.json`, no sharing |
| Worktree on a branch predating `specify init` | Resolves to the first ancestor holding `.specify/` |
| Two such worktrees nested under the primary | Both resolve to the primary and share one `feature.json` |

So the answer is per worktree, conditionally. `.specify/` is committed, so any worktree whose branch
includes the scaffold commit gets its own copy, and `feature.json` is gitignored and stays local to
that checkout. Sessions do not collide.

**A branch that predates the scaffold has no `.specify/`, and the walk escapes the worktree.** Two
sessions in that state both bound to the primary's pointer. The second overwrote the first, and the
first was never told.

`git status` was clean in both worktrees throughout, because the pointer is gitignored and lives
outside their trees. This is the collision class the [landing page](index.md) opens on: no shared
bytes, so every branch merges clean, and the loss lands later.

**Limit: this was measured on Linux with the bash parity, and the PowerShell walk was read rather
than run.** Nothing here is a claim about a live agent session, only about the resolver those
commands call.

The mitigation is the branch, not a setting. A worktree cut from a branch that carries `.specify/`
resolves to itself, which was the control case above. Sequence allocation has the same shape and is
covered in [Sequence allocation](SEQUENCE-ALLOC.md).

---

## Install and initialise

```
uv tool install specify-cli
specify init <project> --integration claude --script ps
```

| Fact | Detail |
|---|---|
| Agent selection | `--integration <key>`. The Claude Code key is `claude` |
| The flag that is gone | `--ai` was deprecated at v0.8.1 and removed at v0.10.0 |
| `--script` values | `sh`, `ps`, `py`. `init.py` sets `default_script = "ps" if os.name == "nt" else "sh"` |
| `--script ps` on Windows | Redundant for behaviour. Useful for reproducibility, and for non-interactive runs, which take the OS default silently |
| Changing it later | `--script` is also accepted by `specify integration install`, `switch` and `upgrade` |
| Where the commands land | `.claude/skills/speckit-<name>/SKILL.md`, one directory per command |
| Reproducible install | `--from git+https://github.com/github/spec-kit.git@vX.Y.Z` is upstream's pin |

**Install trap, found by running it.** `uv` can already exist as a Python package while missing from
`PATH`, and `uv tool install` puts its shim somewhere that may also be missing from `PATH`. Check
both before concluding either is absent.

### Things only visible by running it

None of these appear in the upstream documentation. All were measured on 2026-08-15.

| Finding | What follows from it |
|---|---|
| `specify init` does not run `git init` | Version the project yourself. Do not assume the scaffold did |
| It needs no git at all | A search for git across the 6 installed PowerShell scripts returns 2 comment lines |
| New skills are not registered until the agent restarts | The commands are absent from the slash list in the session that ran `specify init` |
| The skills carry `disable-model-invocation: false` | The agent can drive the flow itself. The commands need not be typed |
| `.specify/integration.json` records `"invoke_separator": "-"` | Read that file when the invocation form is in doubt, rather than any write-up |
| Post-install output prints the hyphenated form | `/speckit-constitution`, while the docs use the dotted form throughout |
| `.specify/.gitignore` ignores `feature.json` | Upstream calls it "per-checkout state rather than something to share" |

---

## The command flow

Two sequences are documented. Verified against `main`, against the tag `v0.16.0`, and against that
tag's `templates/commands` tree.

| Path | Sequence |
|---|---|
| Short, for smaller features | specify, plan, tasks, implement, converge |
| Full, for production work | constitution, specify, clarify, plan, checklist, tasks, analyze, implement, converge |

Placements, verbatim from upstream: `clarify` runs before `plan`, `checklist` runs after `plan`, and
`analyze` runs after `tasks` and before `implement`.

Those 9, plus `taskstoissues`, are the whole command set and the 10 installed skill directories.

**The README's core-versus-optional grouping is not an execution order.** Neither of its two tables
states an order. `taskstoissues` is grouped core and appears in neither sequence, while clarify,
checklist and analyze are grouped optional and are interleaved into the full path.

### What each artifact carries

| Artifact | Contents | Written by |
|---|---|---|
| `.specify/memory/constitution.md` | Project-wide non-negotiables. Upstream of every feature | `constitution` |
| `specs/NNN-slug/spec.md` | WHAT and WHY. No tech stack, no APIs, no code structure | `specify` |
| `specs/NNN-slug/plan.md` | HOW. A `Technical Context` section holds language, storage and testing | `plan` |
| `specs/NNN-slug/tasks.md` | Ordered work items. `converge` appends a `Convergence` section | `tasks`, then `converge` |

**The spec/plan division is enforced by a self-check inside the skill prompt, not by CI.** A leaky
spec produces an over-constrained document, not an error. Do not describe it as something the tool
prevents.

Two qualifications survived verification. The `specify` skill legitimately records
technology-flavoured defaults in an Assumptions section, and project-wide technical non-negotiables
legitimately live in the constitution.

### converge is a loop with a termination condition

`converge` reads `spec.md`, `plan.md` and `tasks.md` as the sole source of intent, assesses the
code, and appends unmet work to `tasks.md`. It never edits or deletes code.

Outcomes are binary. Either it reports converged with `tasks.md` byte-for-byte unchanged, or it
appends N tasks and you run `implement` then `converge` again. That termination condition is the
mechanical difference between this and ad-hoc prompting.

---

## The nine claims that failed verification

Each appears in currently published material. 3 of the 9 were true in an earlier release, which is
why a stale guide does not read as stale.

| Vote | The published claim | Why it is wrong |
|---|---|---|
| `0-3` | `specify init --ai claude` selects the agent | Removed at v0.10.0. Verifiers enumerated the full option list; absent even as a hidden alias |
| `0-3` | Skills mode is opt-in via `--integration-options="--skills"` | For `claude` it is the documented native layout |
| `0-3` | Skills mode requires `/speckit-<command>`, and the dotted form is legacy | Both forms ship. Docs use dotted, skill directories are hyphenated |
| `0-3` | v0.16.0 notes document the skills default only for copilot | The claude layout is documented as native on the integrations page |
| `0-3` | Windows users must pin v0.16.4 for PowerShell output fixes | Those fixes could not be confirmed to exist. Pin for reproducibility, not for this |
| `0-3` | `/speckit.specify` creates the git branch automatically | It creates the directory only |
| `0-3` | The spec template mandates `[NEEDS CLARIFICATION: question]` markers | Not established for this version. It describes older upstream material |
| `0-3` | The constitution enforces hard gates: Article III test-first, Article VII a 3-project cap | Describes an older document. MVP-scoping advice built on that numbering is unsupported |
| `1-2` | Numbered feature branches come from an opt-in git extension | The vote split on wording. The mechanic appears verbatim in quickstart text two unanimous claims quoted |

### Real defects, scoped

| Issue | What it is |
|---|---|
| [1946](https://github.com/github/spec-kit/issues/1946) | Offline scaffolding ignores its arguments: a helper declares `param([string]$Input)` and collides with PowerShell's automatic `$input`. Scoped to release-package generation |
| [3025](https://github.com/github/spec-kit/issues/3025) | `check-prerequisites -PathsOnly` passes `-NoPersist`, so read-only resolution will not write `feature.json` |
| [3026](https://github.com/github/spec-kit/issues/3026) | `CURRENT_BRANCH` falls back to the feature-directory basename |
| [842](https://github.com/github/spec-kit/issues/842) | An agent generating non-working PowerShell. An output-quality issue, not a CLI defect |

---

## What it does not give you

No capability here is unavailable to someone who adopts the practices instead. The templates are
copyable files, the commands are prompts, and the scripts create directories.

What survives that:

| Benefit | Weight |
|---|---|
| Someone else maintains 134KB of prompt engineering, and patches it | Real, modest |
| A vocabulary legible to another session, another seat, or a person who never opens the agent | The strongest |
| Resistance to the agent's own drift, since a prompt file does not degrade as context fills | Strongest on long builds |

Against those, one measured cost: 134KB of skill prompts whose interaction with `CLAUDE.md`, whose
precedence against it, and whose context cost were all unverifiable.

The documented criticism is about cost rather than correctness. It reports specs bloated with
generated text that reads as progress, and hours spent correcting generated specs on brownfield
multi-module systems. None of it disputes a mechanical fact above.

---

## A decision rule

Use it when at least one holds:

- The work will be handed to another session, another seat, or a different agent.
- The build is long enough that guidance given in conversation will decay before it ends.
- The thing being built tends to sprawl, and a what-before-how gate is the guard.
- The specification must be read by people who will never open the agent.

Skip it when all hold:

- One session, end to end.
- Small enough that the artifacts would outweigh the code.
- You were going to review at each phase anyway, so your review is already the gate.

If skipping, the practices worth keeping are the three filenames, the what-before-how ordering, and
a constitution whose principles each carry the test that would falsify them.

**If using it, a defensible cut.** For an MVP: constitution, specify, clarify, plan, tasks,
implement, converge. Drop `checklist` and `analyze`, which are sized for production features, and
drop `taskstoissues` unless an issue tracker is in the loop.

Set an exit condition when you start. If `specify` and `clarify` produce a document that reads as
padding rather than as decisions you would defend, stop and build directly. A commitment with no
exit condition becomes permanent by default.

---

## Where the evidence runs out

3 parts of the question produced no claim that survived verification.

| Question | Status |
|---|---|
| How it interacts with `CLAUDE.md`, with pre-existing skills, and with subagents | Nothing verified. No source addresses name collisions, precedence between a `CLAUDE.md` instruction and a `SKILL.md` prompt, or delegation to subagents |
| Whether an MVP should be one feature or several | Nothing verified. The one candidate answer was the 3-project cap, which was killed |
| When it beats plain agent use | Nothing verified. The two sections above reason from measured mechanics, not from evidence |

---

## Provenance, and how to re-check

| Element | Figure |
|---|---|
| Search angles run | 5 |
| Sources fetched | 21 |
| Claims extracted | 105 |
| Claims verified by 3-vote refutation | 25 |
| Survived / killed | 16 / 9 |

Install mechanics, flow sequences, artifact division and feature-state resolution rest on primary
sources or on the installed code. Failure-mode material rests on discussion threads, which is forum
quality. A retrieval that passed through a summarising fetcher may be quoting a paraphrase.

**The caveat that outranks the findings.** The release under test shipped 1 day before the pass ran,
and documentation was read from `main` rather than from a pinned tag. Assume any tutorial or model
recollection predating mid-2026 is wrong on flags and on branch behaviour.

To re-check a claim here, in descending order of reliability: run `specify --version`; read the
installed `.claude/skills/*/SKILL.md` and `.specify/scripts/`; read `.specify/integration.json` and
`.specify/init-options.json`; then consult an external write-up.
