# Automated compliance in CI: which of your rules can actually stop a change

**A rule that is written down and a rule that cannot be skipped are different things. Most
organizations cannot say which of theirs are which, and the answer is a setting somebody can read
this afternoon.**

> **Take a copy:**
> [markdown](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/CI-ENFORCEMENT.md)
> or [Word document](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/CI-ENFORCEMENT.docx).
> [Every file, both formats](OVERVIEW.md#the-files).

---

## In short

**One question separates a control from a report: does failing it stop the change?** A tool
inventory, a dashboard and a scan that runs overnight and emails somebody all describe work being
done. None of them is a rule being enforced. Which checks can stop a change is a setting in your
pipeline rather than a property of the tools, and it is routinely different from what the people
accountable for it believe.

Sorted that way, most of a compliance program does not automate. Of the roughly 150 controls this
document set asks for, about five in six would not stop anything: most need human judgment that no
configuration supplies, and the rest describe work a machine could decide that nobody has wired to
a block.

Three things to do, in order. None of them needs a project:

1. **Get the list of checks that can stop a change, read from today's configuration** rather than
   from anyone's memory or from a list of tools you own.
2. **Prove one of them can fail.** Plant a violation on a branch, watch the build go red, record
   the date. A gate nobody has ever seen fail is indistinguishable from no gate.
3. **Find out who can push a change through when a check is red**, whether every use is logged, and
   whether anyone reads the log. Overrides are on by default in most setups.

What automation buys is narrower than the pitch: a class of failure stops recurring without anyone
remembering to look for it, and reviewer hours move off mechanical findings onto judgment. Fund it
on those two. The cost-avoidance multiple you have heard quoted does not survive contact with its
sources, and neither does the delivery-speed claim -- [what it buys you, and what it
costs](#what-it-buys-you-and-what-it-costs).

Two ways through the rest of this page. Accountable for security: [the one
question](#the-one-question-does-failing-it-stop-the-change), then [what to
ask](#what-to-ask-and-what-a-good-answer-sounds-like). Running the team and justifying the spend:
start with the arithmetic in [what it buys you, and what it
costs](#what-it-buys-you-and-what-it-costs).

---

## The one question: does failing it stop the change?

Somebody proposes a change to the shared code. A server runs checks against it automatically. If a
check is wired to block, a failure stops the change from joining. Your team calls that CI --
continuous integration -- or the pipeline, or the build system. Which checks run, and which can
stop a change, are separate settings somebody chose.

Ask two questions of each control you are relying on, in this order:

- **Can a machine decide this without judgment?** If no, it is bucket 3, and nothing you configure
  will move it.
- **Is the check wired so that a failure stops the change?** If no, it is bucket 2, whatever the
  tool is technically capable of.

What survives both is **bucket 1**: a machine deciding, with failure stopping the change.
**Bucket 2** is a machine that could decide, wired so that nothing stops -- advisory jobs,
scheduled scans, anything that reports into a channel. **Bucket 3** is judgment, permanently.

Which bucket a control lands in is as much a fact about your configuration as about the control,
and the gap between the two is where money goes without buying enforcement. Advisory and
scheduled-only jobs never turn a proposed change red, so counting them as coverage inflates the
number without adding a gate ([CI and
standards](../CI-AND-STANDARDS.md#blocking-and-advisory-are-not-the-same-coverage)).

Three things survive the sort and still catch people:

- **A pass proves nothing until you have proved the check can see that class of problem.** A run
  that examined nothing and a run that found nothing look identical from outside, and nobody
  investigates a green check ([the leak gate](../LEAK-GATE.md#the-caveat-that-matters-most)).
- **A blocking, machine-enforced check can still be about nothing.** Requiring an approval passes
  every test above and establishes only that somebody clicked a button; whether anyone read
  anything is bucket 3. At least fifteen controls in this set have that shape.
- **Bucket 1 is not therefore handled.** A secret scan is mechanical only once a person has defined
  what counts as sensitive, and its green says nothing about that definition being right.

Bucket 3 needs people or governance instead, which makes it a hiring and process decision rather
than a tooling one. The long form of that list is in [How to adopt these, step
4](ADOPTING-THESE.md#step-4-automate-wherever-possible-so-it-stays-done).

---

## This set, sorted once

These documents ask for at least 150 separate controls. Sorted by the two questions above, 96 need
judgment that no configuration will move and 30 describe work a machine could decide but that
nothing here requires anyone to wire to a block. Twenty-four are described as stopping the change.
The table below is an example of the sorting rather than the inventory itself.

| Bucket | The control | Why it lands there |
|---|---|---|
| **1** | A scan that refuses a password or key into the code | Text matches a defined pattern or it does not |
| **1** | An installer that refuses a component whose fingerprint does not match | The fingerprint matches, or the install stops |
| **2** | The vulnerability scan that runs overnight and emails somebody | Wired to a clock, not to a change |
| **3** | Whether the threat model is any good, not whether one exists | A check confirms one exists; nothing confirms it is good |
| **3** | Whether anyone on the team can explain the code | The textbook case of what a machine cannot assess |

Read the installer row against its half-measure. Writing component fingerprints into a file, and
making the installer refuse anything that does not match, are the same control one setting apart --
and only one of them stops anything.

Take your own list, ask the two questions of each entry, and total the buckets. It is an
afternoon's work, and the answer is about your team rather than about this page.

*Sorted 2026-08-06. Split the compound rules differently and you get a different number; the ratio
transfers, not the count. No row describes any organization's pipeline.*

---

## What it buys you, and what it costs

*Marked **[external]** is published research, with its limitation attached. The rest is this page's
own reasoning.*

- **The volume rises and the review budget does not.** If an AI coding assistant writes a
  meaningful share of the code, the change arriving at review has gone up and the hours available
  to read it have not. Subtraction about your own headcount rather than a research finding, and it
  makes reviewer attention the binding constraint.
- **Your reviewers stop doing machine work.** Where mechanical findings are produced automatically
  and attached to the change, review comments move off mechanical matters and onto design and
  intent **[external]** (Sadowski et al., *Communications of the ACM*, 2018; Bacchelli and Bird,
  ICSE 2013 -- evidence that attention moves, not that review gets better).
- **Fixing it before it merges takes fewer steps than fixing it after release.** That is a claim
  about steps, not about cost: caught after release, the same problem costs a release, possibly a
  rollback, possibly a conversation with people outside your team. The ratio you have heard -- ten
  times, a hundred times -- traces to a study nobody has ever produced, and the largest attempt to
  test the effect, across 171 projects, did not find it **[external]** (Menzies, Nichols et al.,
  *Empirical Software Engineering*, 2016, measuring effort on the issue itself, not the release
  work around it).
- **It takes the decision out of the moment.** A blocking check resolves "is this good enough"
  against structure rather than against whoever argues hardest or ranks highest, and it makes no
  exception late on a Friday. That is also the argument to make to your own engineers: the check
  keeps the deadline from being negotiated out of their work. It holds only as far as the people
  who can override it -- the third question below.

What it costs:

- **Pipeline time, charged to the people it was meant to help.** Every check adds waiting between
  written and shipped, and a broken blocking check stops everyone, not only the change that broke
  it. Adopting a pipeline may not speed delivery at all: the most direct study found no quickening
  of merged changes **[external]** (Bernardo et al., preprint, 2023, across open-source projects,
  which does not transfer directly to a company).
- **The first day of a new gate is a wall of findings you already had.** A blocking check applied
  to existing code fails on everything it inherits. Run it reporting-only first, then hold only
  what the change introduced ([How to adopt these, step
  4](ADOPTING-THESE.md#step-4-automate-wherever-possible-so-it-stays-done)).
- **Attention, which is scarcer than minutes.** An advisory job nobody reads is worse than absent,
  because the scorecard still counts it (*this set's own rule, from [Code
  quality](CODE-QUALITY.md)*). One large engineering organization reached the same conclusion by
  measurement: its developers ignored non-blocking warnings, so its policy became to make a check
  stop the change or remove it **[external]** (Sadowski et al., 2018, one organization's policy,
  not a controlled study).
- **The checks are themselves software**, with versions, breakages and upgrade costs of their own.
- **A gate that cannot fail costs more than no gate**, because it spends the credibility of the
  ones that work.

Automation does not make code better. It stops a class of failure from quietly resuming and moves
human attention onto work a machine cannot do, which is the whole case for funding it. Fewer
defects overall, faster delivery, an avoided cost multiple: none of those is supported.

---

## What to ask, and what a good answer sounds like

The same five questions work from either chair -- interrogating somebody else's team, or diagnosing
your own. The bad answers are the plausible ones, which is why they are worth being able to
recognize.

| Ask | A good answer | A bad answer |
|---|---|---|
| **Which checks can stop a change, and which only report?** | The list of the ones that block, read fresh from today's setting | "Here are the tools we run." [An inventory reads as posture. Only blocking checks are a control.] |
| **Has any check moved from blocking to reporting-only, and who decided?** | A short list, with a date and a reason for each | "We would not do that." [A downgraded check looks identical on every status summary.] |
| **Who can push a change through when a check is red?** | A named short list, every use logged, and somebody reads the log | "Nobody would do that." [Overrides are on by default in most setups, and not loud. Ask whether it is rare, logged and reviewed.] |
| **Was the check green on the exact version that shipped?** | Yes, confirmed for this release rather than in general | "The badge is green." [Checks can pass on an earlier revision than the one that landed, and it still looks green.] |
| **When a check goes red, do we fix it or re-run it?** | We establish why before calling it timing, and track how often | "That one is flaky." [A test failing for being right looks identical to one failing for timing. Re-running until green ignores your own failures.] |

[The CISO summary](CISO-SUMMARY.md) carries five general questions, including how you know a gate
works at all.

---

## What your team means when they say...

| Term | What it means, and the catch |
|---|---|
| **Pipeline** (also CI, the build system) | The checks a server runs whenever somebody proposes a change. Which ones run and which can stop a change are separate settings. |
| **Build** | Strictly, assembling code into the product. "The build is green" almost always means the checks passed, not that anything works. |
| **Pull request** (also PR, merge request) | A proposed bundle of changes, offered for review and checking before it joins the shared code. Anything arriving another way got neither. |
| **Merge** | Joining an approved change into the shared code. A merged status is not proof the version reviewed is the version that landed. |
| **Gate** | A check wired so that failure stops the change. Only that makes it a gate, and one nobody has proved can fail is indistinguishable from none. |
| **Required check** | The server-side list of checks that must pass. A check can run everywhere, look important, and not be on it. A count you recall is stale. |
| **Green** | Every check that was configured passed. It says nothing about what was never configured, what was advisory, or what quietly examined nothing. |
| **Flaky** | A check that passes and fails on identical code, usually blamed on timing. A test failing for being right looks identical. The risk is the pressure to make red go away. |

---

## Where to go next

| If you need | Read |
|---|---|
| The version for the people who will build this | [CI and standards](../CI-AND-STANDARDS.md#a-check-that-cannot-fail-is-not-a-control) |
| How to actually put the gates in | [How to adopt these, step 4](ADOPTING-THESE.md#step-4-automate-wherever-possible-so-it-stays-done) |
| What to fund first, whether or not a pipeline exists | [The CISO summary](CISO-SUMMARY.md) |

**None of this certifies anything. MIT licensed** -- adapt it, put your own name on it, and delete
anything you cannot stand behind.
