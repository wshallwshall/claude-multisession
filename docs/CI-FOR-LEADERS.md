# CI for leaders: what done means when the author cannot vouch for the change

## TLDR/BLUF

**What this is.** A leader's account of the continuous integration this repository runs, for the
person funding it rather than building it. It moves the definition of *done* off the author's
confidence and onto a check with an exit code.

**Why you should care.** Agent output defeats review by being plausible, not by looking wrong.
Sessions pushing into one trunk also produce defects that merge with no conflict marker. Not for you
if you want a workflow file to copy: none is written out here.

**How to use it.** Take the questions in [what to ask your team for](#what-to-ask-your-team-for) to
your next meeting with your team, and give the pipeline itself to an engineer.

---

## What this kind of CI is

**A gate is a deterministic check with an exit code**, never an instruction to the assistant to be
careful. No change merges on the assistant's own assurance.

Both rules belong to [AI-assisted development](https://secure-development-standards.pages.dev/standards/AI-ASSISTED-DEVELOPMENT.html).

**A written reminder is not a control, and the difference was measured.** A session-start banner
asked every session to work in an isolated checkout. Measured over 30 days on the repo this tooling
was developed in, 44% of writes from sessions sitting in the shared checkout landed there.

That figure has not been re-measured, and nothing in the repository can recompute it. Treat it as
cited rather than current: [README](https://claude-multisession.pages.dev/README.md).

So *done* stops meaning an author who can walk you through the change. It means a set of checks that
ran, that could have failed, and that named what they examined.

## Three states a control can be in

A control that runs is not a control that can fail. A control that can fail is not one anybody has
proved can fail. Only the third state supports an attestation, and all three look identical on a
dashboard.

| State | What you may attest | What it is worth |
|---|---|---|
| It runs | The job executed and exited zero | Nothing about the code. A check that cannot go red produces this forever |
| It can fail | The logic has a red path somewhere in it | Nobody has driven that path with a real defect |
| It has been proved able to fail | A planted defect turned it red, on this artifact, on this date | The only state an attestation can rest on |

In a hook-and-installer system, a control can be absent, unwired, wired to a dead script, or failing
open. All four print what a healthy quiet run prints: exit zero, no output, work proceeds. A
dashboard cannot separate them.

A shipped version of this repository's worktree gate crashed on the value it uses when a caller
omits an argument. Every test supplied that argument explicitly, so the failing line never ran. The
suite stayed green. A test that runs the gate with no arguments now pins it.

**A pass is evidence only after the same check has been made to fail on purpose.** In the drift
audit of 2026-08-04, each shipped gate fix was proved by 5 mutations, one at a time, each required
to go red.

An adversarial review of those fixes surfaced 3 regressions, pinned in their own test file:
[Drift audit case study](CASE-STUDY-drift-audit.md).

## The defect class review cannot see

Two sessions each compute the next free identifier from their own isolated checkout. Both are
correct. The branches merge with no conflict, and no line disagrees with any other line.

Human review cannot catch that by construction, because each half is right on its own. On the repo
this tooling was developed in, the collision fired 3 separate times:
[Sequence allocation](SEQUENCE-ALLOC.md).

One identifier was claimed by 3 concurrent branches and surfaced only after merge:
[CI and standards](https://secure-development-standards.pages.dev/CI-AND-STANDARDS.html), *"Reserve
globally unique identifiers from a shared registry, never by scanning"*.

A separate checkout per session, a file lock, code review and a green pipeline on each branch are
each individually blind to it. The catch has to be central or it does not happen.

An allocator that creates a file only if it does not exist produced 8 distinct numbers across 8
concurrent processes, with 0 collisions. Rewriting one shared list instead lost 4 of 8 writes and
raised no error.

Duplicated work has the same shape. Two sessions fixed one defect an hour apart, the rebase reported
no conflict, and the doubled fix shipped with 92 tests passing.

Elsewhere, 3 sessions fixed one dependency advisory: 3 branches, 0 textual conflicts, and 2 of the 3
pull requests closed as duplicates. [Coordination](COORDINATION.md) carries both.

**A green branch is not a green combination.** Measured on the repo this tooling was developed in,
the trunk moved 7 times during one pair of pull requests. Two independently green branches need not
merge cleanly in either order.

**A branch check asserts a property of the branch.** Nothing asserts a property of the combination
until it is on the trunk, so a check that runs after merge matters more with parallel sessions.

## How this reduces slop

Slop is not a defect category. It is confident, well-formed, wrong output, and it survives a read.

An early usage hook measured during this work reported 93 percent weekly into a session whose pool
sat at 5 percent. The number and the account name were formatted, confident and wrong. No such hook
ships here: [Usage awareness](USAGE-AWARENESS.md).

[The CISO summary](https://secure-development-standards.pages.dev/standards/CISO-SUMMARY.html) makes
the volume point: the categories of error have not moved, the amount of output has.

Reviewer hours did not rise with the volume, so attention per change fell. The answer is a check
that can fail rather than more reading:
[CI enforcement](https://secure-development-standards.pages.dev/standards/CI-ENFORCEMENT.html).

The prose gate on this documentation set caught its own authors. The pass that gave 18 pages a
standard opening wrote 8 of those openings over the 30-word limit, and the check named all 8 before
the work landed. Measured 2026-08-10.

A second check found 15 of the 18 rendered pages carried no summary section on 2026-08-10, with
nothing recording that they were missing it. Every page was green either way until a test pinned it.

**[external]**, not measured here. Developers with an AI assistant wrote less secure code while more
confident it was secure, on a 2022-generation model (Perry et al., ACM CCS 2023). Re-baseline it:
[Code quality](https://secure-development-standards.pages.dev/standards/CODE-QUALITY.html).

Closing that confidence gap is what a gate does. It does not make the assistant better, and it does
not make the reviewer faster.

## What a gate answers, and what it does not

| What goes wrong | What answers it |
|---|---|
| Output that is plausible and over a stated limit | A ratchet against a measured baseline |
| Two sessions allocating one shared number | Creating a file only if it does not exist |
| A convention asked for in a reminder | A deterministic check on the write itself |
| A branch that was green before the trunk moved | Revalidation against the current trunk |
| The same intent implemented twice | A claim register declared before work starts, checked at commit |

That last row is the residue. A register records what a session declared, so two sessions building
the same thing under two names still pass. A gate decides a property of one artifact, and cannot see
that two artifacts do the same work: [Coordination](COORDINATION.md).

The gate added after that measurement keys on the write's target path rather than the session's
working directory: [Tips and tricks](TIPS-AND-TRICKS.md).

## What it costs

With up-to-date-with-base enforced and no merge queue, the trunk takes at most one merge per
pipeline cycle. A low-urgency merge therefore costs every sibling branch a full cycle, and one
broken blocking check stops every session rather than one.

A changed gate also makes every already-green branch unverified. The sequencing rule is owned by
[CI and standards](https://secure-development-standards.pages.dev/CI-AND-STANDARDS.html), under
*"Sequence the queue deliberately"*.

Do that arithmetic with your own two numbers, pipeline cycle time and sessions in flight, before you
buy another seat. Nothing here measures a ceiling for you.

The costs a single stream of work already carries are set out at
[CI enforcement](https://secure-development-standards.pages.dev/standards/CI-ENFORCEMENT.html),
under *"What it buys you, and what it costs"*.

**False positives are the expensive failure.** On the repo this tooling was developed in, a
verb-scanning rule denied a read-only status command over a blocklisted word in a prose line. A gate
sessions route around protects nothing.

No speed claim is available. Nothing in either repository measures a productivity gain, and that
page refuses the benefit claims a budget usually rests on. Fund this on auditability, continuity and
reviewability.

## What a green pipeline does not prove

Green is a claim about what ran. Each limit here passes a clean pipeline, and each has a named
mechanism.

- **A green leak gate proves less than it looks.** Without a token source configured, this
  repository's CI run arms shape detectors only, and states that a pass then says nothing about
  private names: [the leak gate](LEAK-GATE.md).
- **A skipped job is not a passed job.** Where steps are gated on whether code changed, a
  documentation-only pull request skips them, including the step policing documentation.
- **A dry run proves absence of error, not correctness of output.** Valid-but-wrong output passes
  it, which is the slop class a pipeline is structurally blind to:
  [CI and standards](https://secure-development-standards.pages.dev/CI-AND-STANDARDS.html).
- **A scanner cannot see a policy judgment.** A design note detailed enough to attack the system it
  describes carries no forbidden string: [the leak gate](LEAK-GATE.md) states that limit.
- **The assistant's outbound queries pass no scanner.** A commit-time content scan is not a live
  interceptor of an outbound query, so that channel is human discipline only:
  [AI-assisted development](https://secure-development-standards.pages.dev/standards/AI-ASSISTED-DEVELOPMENT.html).
- **A test can bind the wrong copy.** On the repo this tooling was developed in, 85 tests passed
  while enforcement ran from an installed copy days behind source. That count is cited rather than
  re-measured, so re-derive it: [Drift audit case study](CASE-STUDY-drift-audit.md).

## What to ask your team for

The general control-owner questions are already written at
[The CISO summary](https://secure-development-standards.pages.dev/standards/CISO-SUMMARY.html).
These five are the ones concurrency and agent authorship add.

| Ask | What a healthy answer sounds like |
|---|---|
| Show me one required check failing on purpose. | A planted violation, the red run, and the fix, run in front of you this week rather than described. |
| How many sessions push to this repository at once, and what is the pipeline cycle time? | Two numbers, read off a coordination surface and a recent run, rather than an estimate. |
| What allocates a number two sessions could both claim? | A registry that creates a file only if it does not exist, plus a check that fails a branch carrying an unreserved number. |
| What does a green run say it examined? | A count of units scanned printed on every run, and a non-zero exit when that count is zero. |
| When four branches are ready, who decides merge order, and what revalidates each against a moved trunk? | A named person or a written rule, plus a check that a branch is current with the trunk before it lands. |

A weak answer names a document rather than a command. Read today's blocking list out of the
configuration, because the server-side setting moves faster than prose describing it.

## Related

| For | Read |
|---|---|
| The collision class git cannot report | [Sequence allocation](SEQUENCE-ALLOC.md) |
| Why a clean merge is not evidence nobody duplicated your work | [Coordination](COORDINATION.md) |
| Proving a control is live rather than installed | [Drift audit case study](CASE-STUDY-drift-audit.md) |
| Fail-open versus fail-closed, and declaring which you chose | [Hooks](HOOKS.md) |
| What a content scanner permanently cannot see | [The leak gate](LEAK-GATE.md) |
| What a pipeline buys, what it costs, and what to ask about it | [CI enforcement](https://secure-development-standards.pages.dev/standards/CI-ENFORCEMENT.html) |
| The two-page version written for a security owner | [CISO summary](https://secure-development-standards.pages.dev/standards/CISO-SUMMARY.html) |
| The practitioner record your engineers will work from | [CI and standards](https://secure-development-standards.pages.dev/CI-AND-STANDARDS.html) |
| How much AI-written code a human must actually read | [Review depth](https://secure-development-standards.pages.dev/standards/REVIEW-DEPTH.html) |
| Whether any of this reaches your team at all | [Which standards apply](https://secure-development-standards.pages.dev/standards/WHICH-STANDARDS-APPLY.html) |

You do not need to read anything below this line. It is written to Claude Code.

---

## For Claude Code

Everything from here is addressed to you, Claude Code.

## What you are being asked to do

**Audit before you build.** Somebody has read the half above and wants this in the repository you
are sitting in. Report what is there before you propose anything.

**Say so if the answer is no.** A repository running one session at a time needs the receipt rules
and none of the concurrency gates, and that is a real answer.

**Read the server-side configuration, never a document about it.** Branch protection moves faster
than the prose describing it, and a required-check count you recall is stale.

**Produce commands, do not run them.** Installers and protection changes belong to the human.

| Establish this | How |
|---|---|
| Which checks block a merge | Read branch protection or the ruleset from the host's API for this repository |
| Whether each blocking check can fail | Plant a violation on a scratch branch and watch it go red |
| What the runner actually examines | Read the discovery configuration before trusting any total |
| How many sessions push here | Ask the human; the answer sets the cycle cost |
| What allocates shared identifiers | Read the allocator, or report that there is none |

Then **STOP and report.** Do not write a gate until they have chosen one.

## Build in this order

1. **Make one existing check print what it examined.** Until a run reports how many units it
   scanned, no later green result is evidence about anything.
2. **Refuse a pass on zero units.** This repository's Tests step greps the runner output for
   `Ran [1-9][0-9]* tests` and exits 1 when that line is absent.
3. **Plant a violation of every blocking check and watch each go red.** Do this before adding a new
   check, because an unarmed gate is cheaper to add than to find later.
4. **Add the concurrency gates.** Allocation that creates a file only if it does not exist, a
   same-commit registration check, a work-claim register checked at commit, and a refusal to push to
   protected refs.
5. **Move the authoritative copy server-side.** A local hook is advisory once a session can remove
   it, and the merge gate is the one nobody can skip.
6. **Add a check that runs on the trunk after merge.** A branch-level pass asserts nothing about the
   combination.

## Gate shapes, and the receipt each owes

| Gate | Shape | Receipt it must emit |
|---|---|---|
| Test suite | Fails the run when the runner reports no tests executed | The count of tests executed |
| Content scanner | Exit 0 clean, 1 found, 2 usage error or nothing scanned | What it loaded and what it scanned |
| Control audit | Exit 0 proven, 1 red, 2 undetermined | One row per control, undetermined tagged as such |
| Identifier registry | Creates a file only if it does not exist; two-dot diff in CI mode | The allocation record the change claims |
| Prose ratchet | Seeded at today's measured figure, never at zero | The corpus scanned, and the current figure |

Shipped instances readable in this repository:

- `.github/workflows/gates.yml` refuses a pass when the runner reports no tests executed.
- `scripts/security/scan_forbidden.py` prints what it loaded and what it scanned, and exits 2 on an
  empty scan.
- `bin/ccx-doctor.ps1` exits 0 only when every required control is installed, wired and refused its
  attack, 1 on any red, and 2 when a check could not be determined.

**Use three outcomes, not two.** Exit 0 proven, 1 failed, 2 undetermined. A skip that exits 0 is a
pass nobody granted.

**Seed a ratchet at the measured figure, not at zero.** A hard limit set at zero on day one ships
disabled. The live baselines are constants in `tests/test_prose_rules_hold.py`; read them there
rather than copying them.

## Verify before you report success

- **Drive the artifact that enforces, not the copy in the repository.** A test bound to the source
  copy says nothing about an installed one.
- **Mutate the shipped artifact one change at a time and require each mutation to go red.** Five
  mutations per fixed gate, audit date 2026-08-04; an adversarial review of those fixes then
  surfaced 3 regressions.
- **Run the entry point with no arguments.** A default value is a code path no test that passes the
  argument will ever reach.
- **Pair every positive with a negative control.** A search returning zero proves nothing until the
  same predicate returns non-zero on input that has to match.
- **Run the suite the way CI runs it**, from CI's working directory and with CI's path arguments.
- **Read what your instrument defaulted to.** Latest-attempt filters, scoped discovery and page
  sizes each answer a narrower question and report no error.
- **Enumerate sibling paths for every control you add.** The other operating system, the counterpart
  destructive verb, the adjacent route: an assistant implements where it was prompted.
- **Neutralise caller-supplied values in any refusal message you write.** A branch name accepts
  semicolons and pipes, and a newline in a path forges a second remediation block.

## What you must never claim

- **You cannot claim a speed or productivity gain.** None is measured in either repository. Report
  auditability, continuity and reviewability instead.
- **You cannot claim a gate can fail** unless you made it fail. Say the deny path is unproven.
- **You cannot claim a control is enforcing** from a green test run. Name the copy you exercised.
- **You cannot claim coverage from a scoped run.** State the paths you scanned beside the count.
- **You cannot claim a required-check count from memory.** Read it out of the configuration on the
  day you write the sentence.
- **You cannot claim a fix is unique.** A clean merge is not evidence that no other session did the
  same work an hour earlier.
- **Do not source a number from popular statistics about AI-written code.** Headline percentages
  that did not reconcile with their own sources were dropped here after checking.

## Where the detail lives

Do not reconstruct these from memory. Read them when they become relevant.

| For | Read |
|---|---|
| Every rule this section compresses, with its incident | [CI and standards](https://secure-development-standards.pages.dev/CI-AND-STANDARDS.html) |
| Sorting a control set into blocking and advisory | [CI enforcement](https://secure-development-standards.pages.dev/standards/CI-ENFORCEMENT.html) |
| Controls for AI-assisted work, and what a gate is | [AI-assisted development](https://secure-development-standards.pages.dev/standards/AI-ASSISTED-DEVELOPMENT.html) |
| Adoption order, and reporting-only before blocking | [Adopting these](https://secure-development-standards.pages.dev/standards/ADOPTING-THESE.html) |
| The identifier collision and its allocator | [Sequence allocation](SEQUENCE-ALLOC.md) |
| Which hook fires when, and its failure posture | [Hooks](HOOKS.md) |
| A scanner that treats an empty scan as a refusal | [Leak gate](LEAK-GATE.md) |
| Auditing controls that only look installed | [Drift audit case study](CASE-STUDY-drift-audit.md) |
| The traps, in the order they bite | [Tips and tricks](TIPS-AND-TRICKS.md) |