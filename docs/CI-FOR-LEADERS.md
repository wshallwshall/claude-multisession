# CI for leaders: What done means when the author cannot vouch for the change

## TLDR/BLUF

**What this is.** A guide to the continuous integration this repository runs -- the checks that run
on their own when a change arrives. It is written for the people who fund that work rather than
build it. *Done* stops meaning "the author is confident" and starts meaning "a check passed".

**Why you should care.** What an AI assistant writes survives review by looking plausible, not by
looking wrong. Sessions pushing into one main branch -- the trunk -- also produce defects that merge
with no conflict marker. Not for you if you want a workflow file to copy. None is written out here.

**How to use it.** Take the five questions in
[what to ask your team for](#what-to-ask-your-team-for) to your next engineering meeting. Hand the
pipeline itself to an engineer.

---

## Why review stopped being enough

**Slop is confident, well-formed, wrong output, and it survives a read.**

A usage hook built early in this work told a session it had used 93% of its weekly allowance. The
account that session drew on sat at 5%. The number and the account name were neatly formatted,
confident and wrong. [Usage awareness](USAGE-AWARENESS.md) says why no such hook ships here.

The kinds of error have not changed. The volume of output has, and
[The CISO summary](https://secure-development-standards.pages.dev/standards/CISO-SUMMARY.html) makes
that point. Reviewer hours did not rise with it, so attention per change fell.

**This one is cited from outside, and not measured here.** On a 2022-generation model, developers
with an AI assistant wrote less secure code while being more confident that it was secure (Perry et
al., ACM CCS 2023).

Re-baseline that finding against
[Code quality](https://secure-development-standards.pages.dev/standards/CODE-QUALITY.html) before
you cite it.

The answer is not more reading. It is a check that can fail, and
[CI enforcement](https://secure-development-standards.pages.dev/standards/CI-ENFORCEMENT.html) makes
that case.

## The defect class that review cannot see

Two sessions each compute the next free identifier from their own isolated checkout. Both are
correct. The branches merge with no conflict, and no line disagrees with any other line.

**Human review cannot catch this, by construction, because each half is right on its own.** In the
repository where this tooling was built, that collision fired three separate times, and
[Sequence allocation](SEQUENCE-ALLOC.md) is the record.

Three concurrent branches claimed one identifier, and the clash showed up only after the merge.
[CI and standards](https://secure-development-standards.pages.dev/CI-AND-STANDARDS.html) states the
rule: *"Reserve globally unique identifiers from a shared registry, never by scanning"*.

Four defences are each individually blind to it:

- A separate checkout per session.
- A file lock.
- Code review.
- A green pipeline on each branch.

A central check catches this, or nothing does.

**The fix is an allocator that reserves a number by creating a file only if it does not exist.** It
produced eight distinct numbers across eight concurrent processes, with zero collisions. Rewriting
one shared list lost four of the eight writes and raised no error.

**Duplicated work fails the same way.** Two sessions fixed one defect an hour apart, and the
rebase -- replaying one branch onto the other -- reported no conflict. The doubled fix shipped with
92 tests passing.

Elsewhere, three sessions fixed one dependency advisory. Those three branches produced zero textual
conflicts, and two of the three pull requests closed as duplicates.
[Coordination](COORDINATION.md) records both incidents.

**A green branch is not a green combination.** Back in the repository where this tooling was built,
the trunk moved seven times while a single pair of pull requests was open. Two branches that are
green on their own can still break when combined, in either order.

**A check on a branch tells you about that branch alone.** A pull-request check tests a merge
against the trunk as it stood when the run started. It says nothing about the trunk once it moves,
nor about a second branch still open. A check after the merge earns its keep with parallel sessions.

## What a gate is, and what it replaces

**A gate is a check that ends in a pass or a fail, never an opinion.** It is deterministic: the same
change gets the same answer every run, reported as an exit code. A gate is never an instruction to
the assistant to be careful, and no change merges on the assistant's own assurance.

[AI-assisted development](https://secure-development-standards.pages.dev/standards/AI-ASSISTED-DEVELOPMENT.html)
states both the definition and the no-merge rule.

**A written reminder is not a control.** A session-start banner asked every session to work in its
own checkout. Measured over 30 days in the repository where this tooling was built, 44% of writes
from sessions sitting in the shared checkout landed there anyway.

Nothing in the repository can recompute that figure, and it has not been re-measured. Treat the
[README](https://claude-multisession.pages.dev/README.md) number as cited rather than current.

*Done* no longer means an author who can walk you through the change. It means a set of checks that
ran, that could have failed, and that named what they examined.

The prose gate on this documentation set caught its own authors. One editing sweep gave eighteen
pages a standard opening and wrote eight of those openings over the 30-word limit. The check named
all eight on 2026-08-10, before the work landed.

A second check found that fifteen of the eighteen rendered pages carried no summary section on
2026-08-10, and no record anywhere said they were missing one. Every page passed with or without a
summary until a test made the omission fail.

A gate closes the gap between how correct output looks and how correct it is. It does not make the
assistant better or the reviewer faster.

## What a gate answers, and what it leaves open

| What goes wrong | What answers it |
|---|---|
| Output that is plausible and over a stated limit | A ratchet against a measured baseline |
| Two sessions allocating one shared number | Creating a file only if it does not exist |
| A convention asked for in a reminder | A deterministic check on the write itself |
| A branch that was green before the trunk moved | Revalidation against the current trunk |
| The same intent implemented twice | A claim register declared before work starts, checked at commit |

A **ratchet**, in the first row, is a limit set at today's measured figure. It may fall. It never
rises.

The gate behind the third row arrived after that 44% measurement. It checks where a write is going
rather than where the session happens to be sitting: [Tips and tricks](TIPS-AND-TRICKS.md).

**The last row is the one a gate leaves open.** A register records only what a session declared, so
two sessions building the same thing under two names both pass.

A gate decides a property of one change at a time, and two changes doing the same work each look
correct alone: [Coordination](COORDINATION.md) states the limit.

## What it costs

Suppose every branch must be current with the trunk before it merges, and no merge queue lines the
branches up for you. The trunk then accepts at most one merge per pipeline cycle -- one full run of
the checks.

Three costs follow from that:

- A low-urgency merge costs every other branch in flight a full cycle.
- One broken check that blocks merges stops every session, not one.
- A changed gate makes every already-green branch unverified.

[CI and standards](https://secure-development-standards.pages.dev/CI-AND-STANDARDS.html) states the
sequencing rule, under *"Sequence the queue deliberately"*.

[CI enforcement](https://secure-development-standards.pages.dev/standards/CI-ENFORCEMENT.html) sets
out the costs a single stream of work already carries, under *"Costs"*.

**The goal.** Know how many sessions your pipeline can carry before you pay for another account
([Token accounting](TOKEN-ACCOUNTING.md) prices one).

**What to do.** Do that arithmetic with your own two numbers: pipeline cycle time, and sessions in
flight.

**What happens next.** You get your own ceiling. Nothing here measures one for you.

**False positives are the expensive failure.** In the repository where this tooling was built, a
rule that scanned for verbs denied a read-only status command. The blocklisted word it matched sat
in a line of prose. A gate that sessions learn to route around protects nothing.

**No speed claim is available here.** Nothing in either repository measures a productivity gain, and
CI enforcement refuses the benefit claims a budget usually rests on. Fund this on auditability,
continuity and reviewability.

## How to tell whether a control is real

A control that runs may have no way to go red at all. A control with a red path may never have been
driven down it. Only the third state supports an attestation, and all three look identical on a
dashboard.

| State | What you may attest | What it is worth |
|---|---|---|
| It runs | The job executed and exited zero | Nothing about the code. A check that cannot go red produces this forever |
| It can fail | The logic has a red path somewhere in it | Nobody has driven that path with a real defect |
| It has been proved able to fail | A planted defect turned it red, on this artifact, on this date | The only state an attestation can rest on |

Controls here are installed by a script and fired by hooks, so one can be:

- Missing.
- Wired to nothing.
- Wired to a dead script.
- Failing open -- waving work through when the check itself errors.

All four look like a healthy quiet run: exit zero, work proceeds, and a dashboard shows the same
green. Only the silence is optional. A control that fails open can still say so: this repository's
gate writes a receipt to stderr and to the deny log when it cannot load.

This repository's [worktree gate](WORKTREES.md) keeps each session in its own checkout. A shipped
version of it crashed on its own default value, the one it uses when a caller omits an argument.

**That gate fails open, so the crash allowed every write it exists to deny.** It ran that way for
one install, on every real tool call, with nothing on screen to say so. This page's own thesis,
measured: the control was fully off and the machine looked identical.

Every test supplied that argument explicitly, so the failing line never ran and the suite stayed
green. A test that runs the gate with no arguments now pins it.

**A pass is evidence only after the same check has been made to fail on purpose.** In the drift
audit of 2026-08-04, each shipped gate fix was proved by five mutations, applied one at a time, each
one required to go red.

An adversarial review of those fixes found three regressions, held in place by a test file of their
own. [Drift audit case study](CASE-STUDY-drift-audit.md) records the audit and the review.

## What a green pipeline does not prove

Green is a claim about what ran. Every limit below survives a clean pipeline run, and each one has a
named mechanism.

- **A green leak gate proves less than it appears to.** With no token source configured, this
  repository's CI run switches on only the detectors that match a generic shape, not the ones that
  match your private names. [The leak gate](LEAK-GATE.md) says a pass then proves nothing about
  those names.
- **A skipped job reports green having run nothing.** When steps only run if code changed, a
  documentation-only pull request skips all of them, including the step that polices documentation.
- **A dry run proves that nothing errored, not that the output is right.** Running a change without
  letting it take effect passes valid-but-wrong output, and that is the slop a pipeline is
  structurally blind to:
  [CI and standards](https://secure-development-standards.pages.dev/CI-AND-STANDARDS.html).
- **A scanner cannot see a policy judgment.** A design note can carry enough detail for someone to
  attack the system it describes and still contain no forbidden string, and
  [the leak gate](LEAK-GATE.md) states that limit.
- **The assistant's outbound queries pass no scanner.** A commit-time scan cannot intercept a query
  as the assistant sends it, so that channel is human discipline alone, as
  [AI-assisted development](https://secure-development-standards.pages.dev/standards/AI-ASSISTED-DEVELOPMENT.html)
  states.
- **A test can exercise the wrong copy.** In the repository where this tooling was built, 85 tests
  passed while enforcement ran from an installed copy days behind source.
  [Drift audit case study](CASE-STUDY-drift-audit.md) records that count, cited rather than
  re-measured, so re-derive it.

## What to ask your team for

**The goal.** Leave the meeting knowing which checks block a merge, and whether anyone has watched
one of them fail.

**What to do.** Ask these five.
[The CISO summary](https://secure-development-standards.pages.dev/standards/CISO-SUMMARY.html)
already carries the general questions for a control owner. These five are the ones that concurrency
and AI-written code add.

| Ask | What a healthy answer sounds like |
|---|---|
| Show me one required check failing on purpose. | A planted violation, the red run, and the fix, run in front of you this week rather than described. |
| How many sessions push to this repository at once, and what is the pipeline cycle time? | Two numbers, read off a coordination surface and a recent run, rather than an estimate. |
| What allocates a number two sessions could both claim? | A registry that creates a file only if it does not exist, plus a check that fails a branch carrying an unreserved number. |
| What does a green run say it examined? | A count of units scanned printed on every run, and a non-zero exit when that count is zero. |
| When four branches are ready, who decides merge order, and what revalidates each against a moved trunk? | A named person or a written rule, plus a check that a branch is current with the trunk before it lands. |

**What happens next.** A weak answer names a document rather than a command. Read today's blocking
list out of the configuration, because the server-side setting moves faster than prose describing
it.

## Related

| For | Read |
|---|---|
| The collision class git cannot report | [Sequence allocation](SEQUENCE-ALLOC.md) |
| Why a clean merge is not evidence nobody duplicated your work | [Coordination](COORDINATION.md) |
| Proving a control is live rather than installed | [Drift audit case study](CASE-STUDY-drift-audit.md) |
| Fail-open versus fail-closed -- letting work through when the check itself errors, or refusing it -- and declaring which you chose | [Hooks](HOOKS.md) |
| What a content scanner permanently cannot see | [The leak gate](LEAK-GATE.md) |
| What a pipeline buys, what it costs, and what to ask about it | [CI enforcement](https://secure-development-standards.pages.dev/standards/CI-ENFORCEMENT.html) |
| The two-page version written for a security owner | [CISO summary](https://secure-development-standards.pages.dev/standards/CISO-SUMMARY.html) |
| The practitioner record your engineers will work from | [CI and standards](https://secure-development-standards.pages.dev/CI-AND-STANDARDS.html) |
| How much AI-written code a human must actually read | [Review depth](https://secure-development-standards.pages.dev/standards/REVIEW-DEPTH.html) |
| Whether any of this reaches your team at all | [Which standards apply](https://secure-development-standards.pages.dev/standards/WHICH-STANDARDS-APPLY.html) |

Everything below this line is addressed to Claude Code. You do not need to read any of it.

---

## For Claude Code

### Audit first, then stop

**Audit before you build.** Somebody has read the half above and wants this repository gated the
same way. Establish the five rows in the table below, and report all five before you propose
anything.

**Say so if the answer is no.** A repository running one session at a time needs the receipt rules
-- each run printing what it examined -- and none of the concurrency gates. That is a real answer.

**Read the server-side configuration, never a document about it.** Branch protection moves faster
than the prose describing it, and a required-check count you recall is stale.

**Produce commands, do not run them.** Installers and branch-protection changes belong to the human.

| Establish this | How |
|---|---|
| Which checks block a merge | Read branch protection or the ruleset from the host's API for this repository |
| Whether each blocking check can fail | Plant a violation on a scratch branch and watch it go red |
| What the runner actually examines | Read the discovery configuration before trusting any total |
| How many sessions push here | Ask the human; the answer sets the cycle cost |
| What allocates shared identifiers | Read the allocator, or report that there is none |

**Stop and report.** Do not write a gate until the human has chosen one.

### Build in this order

1. **Make one existing check print how many units it scanned, and where it looked.** Until a run
   reports that count, no later green result is evidence about anything.
2. **Refuse a pass on zero units.** This repository's Tests step greps the runner output for
   `Ran [1-9][0-9]* tests` and exits `1` when that line is absent. Match the pattern to the runner
   the target repository actually uses.
3. **Plant a violation of every blocking check and watch each go red.** Do this before adding a new
   check, because an unarmed gate is cheaper to add than to find later.
4. **Add four concurrency gates.**
   - Allocation that reserves a number by creating a file only if it does not exist.
   - A check that the index row for that number lands in the same commit as the number.
   - A work-claim register, declared before work starts and checked at commit.
   - A refusal to push to protected refs.
5. **Make the server-side check the authoritative one, not the local hook.** A local hook is
   advisory once a session can remove it. A merge gate is harder to remove, not impossible to skip:
   a job that is skipped, or one nothing marks required, reports green.
6. **Add a check that runs on the trunk after merge.** A branch-level pass asserts nothing about the
   combination.

### Gate shapes, and the receipt each owes

| Gate | How it must behave | Receipt it must emit |
|---|---|---|
| Test suite | Fails the run when the runner reports no tests executed | The count of tests executed |
| Content scanner | Exits `0` when clean, `1` when a forbidden string is found, `2` on a usage error or an empty scan | What it loaded, and what it scanned |
| Control audit | Exits `0` proven, `1` red, `2` undetermined | One row per control, undetermined tagged as such |
| Identifier registry | Creates a file only if it does not exist; two-dot diff in CI mode | The allocation record for the identifier the change claims |
| Prose ratchet | Seeded at today's measured figure, never at zero | The corpus scanned, and the current figure |

Read these three shipped instances before you write a new gate:

- `.github/workflows/gates.yml` refuses a pass when the runner reports no tests executed.
- `scripts/security/scan_forbidden.py` prints what it loaded and what it scanned, and exits `2` on
  an empty scan.
- `bin/ccx-doctor.ps1` exits `0` only when every required control is installed, wired, and proved by
  refusing a planted attack. It exits `1` on any red **or any required control wired to nothing**,
  and `2` when a check could not be determined.

**Use three outcomes, not two: exit `0` proven, `1` red, `2` undetermined.** A skip that exits `0`
is a pass nobody granted.

**Seed a ratchet at the measured figure, not at zero.** A hard limit set at zero on day one ships
disabled.

The live baselines are constants in `tests/test_prose_rules_hold.py`. Read a baseline from that file
each time you need one, and never quote one from memory or from this page.

### Verify before you report success

- **Drive the artifact that enforces, not the copy in the repository.** A test bound to the source
  copy says nothing about an installed one.
- **Mutate the shipped artifact one change at a time and require each mutation to go red.** The
  2026-08-04 audit ran five mutations per fixed gate, and an adversarial review of those fixes
  surfaced three regressions. Mutate until every branch has been driven, not until you reach five.
- **Run the entry point with no arguments.** A default value is a code path no test that passes the
  argument will ever reach.
- **Pair every positive with a negative control, so a zero is worth something.** A search returning
  zero proves nothing until the same predicate returns non-zero on input that has to match.
- **Run the suite from CI's working directory, with CI's path arguments.** A run from the wrong
  directory can find nothing and still exit clean.
- **Read what your instrument defaulted to.** Latest-attempt filters, scoped discovery and page
  sizes each answer a narrower question and report no error.
- **Enumerate sibling paths for every control you add.** The other operating system, the counterpart
  destructive verb, the adjacent route: an assistant implements where it was prompted.
- **Neutralise every caller-supplied value before it reaches a refusal message.** A branch name
  accepts semicolons and pipes, and a newline in a path forges a second remediation block.

### What you must never claim

- **You cannot claim a speed or productivity gain.** None is measured in either repository. Report
  auditability, continuity and reviewability instead.
- **You cannot claim a gate can fail unless you made it fail.** Report the deny path as unproven in
  the same place you report the pass.
- **You cannot claim a control is enforcing from a green test run.** Name the copy you exercised.
- **You cannot claim coverage from a scoped run.** State the paths you scanned beside the count.
- **You cannot claim a required-check count from memory.** Read it out of the configuration on the
  day you write the sentence.
- **You cannot claim a fix is unique.** A clean merge is not evidence that no other session did the
  same work an hour earlier.
- **You cannot claim a headline percentage about AI-written code.** Percentages that did not
  reconcile with their own sources were dropped here after checking, so do not source a number from
  popular statistics.

### Where the detail lives

Read the page a row names before you act on that row's subject. Do not reconstruct any of it from
memory.

| For | Read |
|---|---|
| Every rule the handoff half above compresses, with the incident behind it | [CI and standards](https://secure-development-standards.pages.dev/CI-AND-STANDARDS.html) |
| Sorting a control set into blocking and advisory | [CI enforcement](https://secure-development-standards.pages.dev/standards/CI-ENFORCEMENT.html) |
| Controls for AI-assisted work, and what a gate is | [AI-assisted development](https://secure-development-standards.pages.dev/standards/AI-ASSISTED-DEVELOPMENT.html) |
| Adoption order, and reporting-only before blocking | [Adopting these](https://secure-development-standards.pages.dev/standards/ADOPTING-THESE.html) |
| The identifier collision and its allocator | [Sequence allocation](SEQUENCE-ALLOC.md) |
| Which hook fires when, and its failure posture | [Hooks](HOOKS.md) |
| A scanner that treats an empty scan as a refusal | [Leak gate](LEAK-GATE.md) |
| Auditing controls that only look installed | [Drift audit case study](CASE-STUDY-drift-audit.md) |
| The traps, in the order they bite | [Tips and tricks](TIPS-AND-TRICKS.md) |
