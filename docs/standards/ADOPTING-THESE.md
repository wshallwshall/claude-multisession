# How to adopt these

**The rest of this section tells you what to read. This page tells you what to do with it.**

> **Take a copy:**
> [markdown](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/ADOPTING-THESE.md)
> or [Word document](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/ADOPTING-THESE.docx).
> [Every file, both formats](OVERVIEW.md#the-files).

---

## TLDR/BLUF

**The deliverable is five artifacts, not five documents read.** A marked baseline worksheet, a
deviations register, a three-item queue, a set of checks each carrying the date somebody last
watched it refuse something, and a project instruction file that references the other four. Each one
either exists or it does not, which is what lets somebody other than you check whether adoption
happened.

**Do not assume you start from zero.** A team that reviews changes, runs a linter, keeps secrets out
of the repository and pins some dependencies already satisfies parts of four of these documents.
What you have is usually a weaker form of a named rule, so the opening pass produces a short list of
upgrades rather than a build plan -- and that pass is read-only. It builds nothing, on purpose.

**Sequence by what enables what, not by risk and ease.** Two people can rank the same two controls
by risk and neither can be shown wrong, so such a ranking can only be overruled, never reviewed.
What-enables-what is checkable: you can be shown to have made a check blocking before anything
recorded what it examined, or to have written a rule about "restricted data" before anything defined
the term. It is also why instrumentation comes before ranking -- with no receipts, every severity
ranking is unfalsifiable.

Two things hold at every step. A blocking row nobody has watched refuse anything is
indistinguishable from one that cannot refuse anything. And tailoring is expected where silent
tailoring is not, because a control that quietly left the set reads exactly like a control nobody
got to.

**None of it confers anything** -- no certification and no badge, for you or for anyone adopting
your software. The deviations register records decisions you made; it is not evidence of compliance
with anything.

---

## If you only have an afternoon

Five things, all read-and-write, none of them a build. Each is somebody else's designated first step,
and each usually finds something.

1. **Classify every nominally-security job you already run as blocking or advisory**, and write the
   classification down. Zero engineering, and it narrows believed coverage on the spot, because an
   advisory job and a blocking one are indistinguishable from a green badge. [Secure
   development](SECURE-DEVELOPMENT.md), *"Scanner posture: what blocks, what advises, what may never
   be waived"*, and its subheading *"What must block, and may not be waived"*.
2. **Write the producer-versus-operator ownership split.** One table, one sitting. It is what makes
   every later claim scopeable. [Secure development](SECURE-DEVELOPMENT.md), *"Shared
   responsibility: write the split down first"*.
3. **Enumerate every dependency manifest in the repository** and note which of them has an audit.
   Ten minutes. A repository that grew a second language usually grew an unwatched dependency tree
   with it. [Dependency integrity](DEPENDENCY-INTEGRITY.md), *"Every manifest in the repository needs
   its own audit net"*.
4. **Open the deviations register with what you cannot do today.** A register written while you are
   still honest about the gaps is worth more than one written at review time. [AI-assisted
   development](AI-ASSISTED-DEVELOPMENT.md), *"The deviations register"*.
5. **Pick one gate you already have and try to make it fail.** Whatever happens, that is your first
   accurate row. [CI and standards](../CI-AND-STANDARDS.md), *"Attack the control with the failure
   class it was built to catch"*.

At the end of the afternoon you have a baseline and a register. You do not have a new control, and
that is the point: a ranking made before the baseline exists cannot be checked by anyone, including
you. Most of what follows is upgrading a control you already run into the shape the rule asks for,
rather than building one.

**Record which revision of each document you tailored from.** These are edited continuously and are
meant to be forked, and a baseline taken against a moving source cannot be re-run at step 3's next
iteration. That instruction is this page's own addition, borrowing a habit the assessment method
applies to a published standard's text ([Security standard assessment](../ASVS-ASSESSMENT.md), *"Pin
the corpus, and stamp the version on every number"*).

---

## What this page claims, and what it does not

- **Adopting these confers nothing.** No certification, no attainment, no badge, for you or for
  anyone adopting your software. The available vocabulary is built to, aligned with, and
  self-assessed against. See [What these are not](OVERVIEW.md#what-these-are-not).
- **An exception register is for your own use.** It records decisions you made. It is not evidence
  of compliance with anything, and not an attestation to anyone else.
- **The worksheet carries at least these controls, and is not a complete account.** Your setting
  will add rows nothing here mentions.
- **The "usually" column is a prior, not a finding about you.** Overwrite it with what you observe.
- **The cost bands are orders of magnitude, not schedule input.**
- **Blocking rows assume somewhere to put a blocking check.** Where merges cannot be blocked, those
  rows degrade to a checklist, and an honest worksheet says so rather than marking them built.
- **Nothing here ships from this repository.** Where a document names a control, it is describing
  something you would build.

For what to read and in what order, [the overview](OVERVIEW.md) owns that question under *"The order
to read them in"*. That section tells you what to read; this page tells you what to do with it.

---

## The five artifacts

| Step | Artifact | What it looks like | Done when |
|---|---|---|---|
| **1 -- establish your baseline** | A marked baseline worksheet | One row per control: control, the file and heading it came from, status, evidence, and the date it was last proven able to fail | Every starter row carries a status and every built row carries a pointer |
| **2 -- tailor, and document the exceptions** | A deviations register | One entry per control you do not meet, four fields, kept internal | Every control you consciously dropped or modified has an entry, and every entry has a trigger |
| **3 -- prioritize iteratively** | An ordered plan, three items deep | The next three items, each naming what it unblocks and what it waits on, above an unordered backlog | The top item's precondition is already satisfied |
| **4 -- automate wherever possible** | A set of blocking checks, each with a receipt | Per check: what it blocks, where it runs, what it prints, whether it started in audit mode, and the date somebody last watched it refuse | No check in the set has "never" in its proven-able-to-fail column |
| **5 -- put the result where Claude Code reads it** | A `CLAUDE.md` control table that references the other four | The template's three columns, extended to every control your tailored set kept | A session reading only that file would follow the rules you adopted and none you dropped |

This page is finished when those five exist. Not when the documents have been read.

---

## Step 1: establish your baseline

**Do not assume you start from zero. You do not.** A team that reviews changes, runs a linter, keeps
secrets out of the repository and pins some dependencies already satisfies parts of four of these
documents. The sharper form of that instruction: the thing you have is usually a weaker form of a
named rule, which turns the gap analysis into a short list of upgrades rather than a build plan.

The pass is read-only. It builds nothing. Two rules make the result honest:

- **A row you did not check is unverified, and unverified is not a pass.** An unscored row is an
  open question, not a quiet yes. [Code quality](CODE-QUALITY.md), *"Adapting this to your project"*.
- **A blocking row nobody has watched refuse anything is indistinguishable from one that cannot
  refuse anything.** [Secure development](SECURE-DEVELOPMENT.md), *"Three additions specific to a
  security posture"*.

Fill in the starter set. Seven rows. The afternoon list above is how the first of them get filled;
[the worksheet](#the-worksheet) at the end of this page is the backlog you work through over
releases, not a prerequisite for starting.

| Control | From | Status | Evidence | Last proven able to fail |
|---|---|---|---|---|
| Architecture and layer boundaries enforced in CI | [Code quality](CODE-QUALITY.md), *Tier 1 -- durable controls, which carry the verdict* | | | |
| Strict type checking, no blanket suppressions | [Code quality](CODE-QUALITY.md), *Tier 1 -- durable controls, which carry the verdict* | | | |
| Tests verify behavior rather than mock choreography | [Code quality](CODE-QUALITY.md), *Tier 1 -- durable controls, which carry the verdict* | | | |
| Dependencies existence-verified and hash-pinned | [Dependency integrity](DEPENDENCY-INTEGRITY.md), *Pin the resolved graph, and enforce the pin at install* | | | |
| Security scanning that blocks, plus a threat model reviewed before the code | [Secure development](SECURE-DEVELOPMENT.md), *What must block, and may not be waived*; *Threat model each trust boundary before you build it* | | | |
| Published artifact contains only what was declared | [Dependency integrity](DEPENDENCY-INTEGRITY.md), *The artifact contains only what you declared* | | | |
| Secrets and restricted data kept out of the repository and its full history, backed by a fail-closed commit-time content scan | [Secure development](SECURE-DEVELOPMENT.md), *Secrets and repository hygiene*; [the leak gate](../LEAK-GATE.md) | | | |

Two of those seven -- tests that verify behavior, and the security row entire -- are not in the
shipped project instruction template, and both carry the verdict. Step 5 returns to that.

Four cheap measurements belong in the same pass, because each commonly finds something the worksheet
alone would not:

- **Read the scanner suppression list rather than accepting it.** A suppressed rule class is a
  control somebody turned off. [Code quality](CODE-QUALITY.md), *"Confirming the control plane"*.
- **Ask what each check examined**, not whether it passed.
- **Count any convention you cite as evidence, in the actual history**, before recording it as
  built. [AI-assisted development](AI-ASSISTED-DEVELOPMENT.md), *"Provenance: record it, and count
  it before you cite it"*.
- **Enumerate every dependency manifest**, per the afternoon list above.

**The output is a marked worksheet, not a plan.** Step 2 removes rows from it.

---

## Step 2: tailor, and document the exceptions

Decide explicitly what applies. Then record every skip or modification, with the event that ends it.
These documents are starting points to edit down, and every one of them says so. Tailoring is
expected; silent tailoring is not, because a control that quietly left the set is indistinguishable
in the record from one nobody got to.

**The boundary is already drawn, per document.** Each standard closes with an *"Adapting this to
your project"* section, and the do-not-weaken items live there. Changing something that section
invites you to change is tailoring and owes no record. Striking a do-not-weaken item is a deviation
and owes all four fields below. Three of the sections carry two literal lists, *"Change freely"* and
*"Do not weaken"* -- [Code quality](CODE-QUALITY.md), [Dependency
integrity](DEPENDENCY-INTEGRITY.md) and [Secure development](SECURE-DEVELOPMENT.md). The other two
do not, and the difference matters:
[AI-assisted development](AI-ASSISTED-DEVELOPMENT.md) states its first list as *what you must
change*, so those items are obligations rather than options; [Human review of code](REVIEW-DEPTH.md)
states no split at all, and calls its do-not-weaken item out inline.

| Field | What it holds | What is lost without it |
|---|---|---|
| **The control not met, and the date accepted** | The requirement you do not satisfy, and when that was accepted | Undated, the deviation cannot be aged |
| **The compensating controls actually in force** | What stands in its place, named specifically | This is what distinguishes a decision from a gap |
| **The trigger that ends it** | The concrete event that forces the real control to be built | Without one, the deviation is permanent by default |
| **A pointer to where the intended shape is written down** | The design record for the eventual fix | The fix gets improvised later rather than designed |

The format is published in [AI-assisted development](AI-ASSISTED-DEVELOPMENT.md), *"The deviations
register"*. Keep one register, not two. Two conditions sit alongside the fields rather than inside
them: **only a dated, signed acceptance is governance**, and a release gate leaning on an unsigned
acceptance is not a gate; and **keep the register internal** -- publish the rule, not the enumeration
of which controls are currently absent. One constraint travels with every entry: a compensating
column naming something that does not implement the predicate being relied on is worse than an
admitted gap, because the next reader stops looking. [CI and standards](../CI-AND-STANDARDS.md), *"A
compensating control must not rest on a false premise"*.

### The worked example

A solo maintainer, or a team with no second reviewer available, cannot meet a requirement that every
change gets independent human review. That is a real deviation from every mainstream review
standard, and the wrong response is to redefine "reviewed" until it looks satisfied. The right one
is a register entry:

- **Control not met:** independent human review of every change, accepted on a stated date.
- **Compensating controls actually in force:** blocking static analysis and dependency audit that an
  author cannot waive; an AI-run review that a human arbitrates, explicitly not an independent
  audit; branch protection with required checks; no direct pushes to the integration branch.
- **The trigger that ends it:** a second maintainer joins.
- **A pointer to the intended shape:** where the review process you intend is written down.

The wording constraint travels with it: this is a **compensating control**, never "reviewed" in a
sense that implies an independent audit. The entry is worked out in [AI-assisted
development](AI-ASSISTED-DEVELOPMENT.md), *"When there is no second reviewer"*, in [Secure
development](SECURE-DEVELOPMENT.md), *"Self-review is a documented deviation, not a satisfied
control"*, and in [Code quality](CODE-QUALITY.md), *"When review is self-review"*. Note what it does
not do: it does not drop the practice. The requirement stays unmet, named and dated, with an event
that ends the arrangement.

### What tailoring is not

- **Can you name the outcome the practice asks for, and say how you meet it?** That is tailoring.
  Record the modification and move on.
- **Is your answer that the question no longer arises?** Look again. Concluding that a practice has
  stopped applying is the failure this step exists to prevent, and it is indistinguishable in the
  record from never having considered it.

A capability in your stack can eliminate a whole class of defect. What that changes is *which*
failures you face, and therefore *how* you satisfy a practice. It does not decide *whether* the
practice applies. At least five shapes of the same failure are named across the set, and each
produces a document that survives accuracy review while describing a practice that does not exist:
redefining the pass bar so "it can be configured" counts; widening a soft grade until it absorbs
everything ambiguous; writing scope as exclusions that grow to swallow inconvenient cases;
transferring an obligation and calling the question closed; and counting the unread as done.

---

## Step 3: prioritize iteratively

**This is a marathon, not a sprint.** A plan that assumes otherwise stalls in the middle and leaves
a half-built control plane that reads as a complete one.

**Sequence by what enables what.** Where two items sit in the same layer, take the riskier surface
first; where two are equally enabling and equally risky, take the cheaper one. Risk and ease decide
which of two available moves to make this week. They do not decide what is available.

Risk-and-ease alone is a preference. Two people can rank the same two controls differently and
neither can be shown wrong, so the ranking cannot be reviewed -- only overruled. What-enables-what is
checkable: you can be shown to have made a check blocking before anything recorded what it examined,
or to have written a rule saying "restricted data" before anything defined the term. The strongest
instance is why the rule reads this way -- with no receipts, every severity ranking is unfalsifiable,
so instrumentation comes before ranking ([Case study: a drift
audit](../CASE-STUDY-drift-audit.md), *"A control with no receipts cannot be ranked, fixed, or
defended"*). A prioritization scheme that cannot be checked is the same defect named elsewhere as a
control that cannot fail.

This is a build order, not a reading order, and the two diverge on purpose: the data-class table
sits inside the document [the overview](OVERVIEW.md) puts last, while several earlier documents
resolve against it.

### The build order

| Layer | What it is | Why it comes before the next | Where that is written |
|---|---|---|---|
| **L0 -- definitions and records** | The producer-versus-operator split, the data-class table, the blocking-versus-advisory classification, the deviations register opened. Written records, no engineering | The data-class table has the highest fan-out in the set: several later rules resolve against it, and a rule that says "restricted data" over a table with no matching row has a missing row, not a satisfied control | [Secure development](SECURE-DEVELOPMENT.md), *Shared responsibility: write the split down first*; *What "restricted data" means here, exactly once* |
| **L1 -- enumerations** | Every dependency manifest, every trust boundary, the required-check set | An enumeration converts a habit into a checkable list, and it is what makes a coverage claim quantified over something | [Dependency integrity](DEPENDENCY-INTEGRITY.md), *Every manifest in the repository needs its own audit net*; [CI and standards](../CI-AND-STANDARDS.md), *The required-check set* |
| **L2 -- baselines** | A clean lint baseline with per-line suppressions naming their rule, and a lock that records digests rather than versions | A baseline is a start condition for red-on-regression enforcement, not a result | [CI and standards](../CI-AND-STANDARDS.md), *Grandfather to a clean baseline, then ratchet*; [Dependency integrity](DEPENDENCY-INTEGRITY.md), *Pin the resolved graph, and enforce the pin at install* |
| **L3 -- enforcement** | Install-time pin enforcement, the unwaivable blocking set, branch protection, the allowlist gate placed before the irreversible upload | Nothing here can be built before the thing it enforces exists to be enforced against | [Secure development](SECURE-DEVELOPMENT.md), *What must block, and may not be waived*; [CI and standards](../CI-AND-STANDARDS.md), *Package manifests are allowlists, not sweeps* |
| **L4 -- receipts and proof of failure** | Units examined printed on every run, zero-units-examined exiting non-zero, and a date somebody watched each gate refuse something | Ranking is unfalsifiable until this exists, which is why it precedes the measurement layer rather than following it | [CI and standards](../CI-AND-STANDARDS.md), *Receipts: count what the check examined, never what it found*; *Attack the control with the failure class it was built to catch* |
| **L5 -- measurement** | Mutation on changed code, coverage visibility, duplication, complexity triage | Last, and never a gate on its own -- reversed, you get a dashboard and no controls | [The CISO summary](CISO-SUMMARY.md), *What to fund first*; [Code quality](CODE-QUALITY.md), *Tier 2 -- the measurement layer, which is guidance and triage* |

**Take each document's own adoption list when you reach that document.** [AI-assisted
development](AI-ASSISTED-DEVELOPMENT.md), [Code quality](CODE-QUALITY.md) and [Dependency
integrity](DEPENDENCY-INTEGRITY.md) each carry a *"How to adopt this"* section ordered by its own
leverage, and each opens with a measurement rather than a build. The layer table is the
cross-document order those three lists cannot express. [Secure development](SECURE-DEVELOPMENT.md)
no longer carries one; its own opening points at the two sections to start from.

Two sequencing errors are worth naming. Adopting the tier ladder and the control dials before the
floor is real produces ceremony over a hole ([AI-assisted development](AI-ASSISTED-DEVELOPMENT.md),
*"How to adopt this"*). And a cost figure quoted from before a gate was repaired is unmeasured:
placement is a derived value and must be re-derived after any repair ([CI and
standards](../CI-AND-STANDARDS.md), *"A cost model built on a broken gate is fiction"*).

**Do not report adoption as a count of controls marked built.** It is named as a non-verdict in
[Secure development](SECURE-DEVELOPMENT.md), *"The security anti-metrics"*. The queue is three deep
because a longer list is a schedule, a schedule invites a date, and the number a date would be
reported against is the one just forbidden. Everything below the top three sits in the worksheet as
an unordered backlog.

---

## Step 4: automate wherever possible, so it stays done

A rule that depends on somebody remembering it is a rule you will lose. The set's position on what
counts is narrow: **a gate is a deterministic check with an exit code** -- a hook, a deny-list, a
blocking pipeline job, a validate-and-run command. It is never an instruction to a model to be
careful, and an AI-run review is advisory input a human arbitrates, never a gate. [AI-assisted
development](AI-ASSISTED-DEVELOPMENT.md), *"Controls as dials"*.

**Only blocking checks count as coverage.** Advisory and scheduled-only jobs are useful and are not
coverage, and the two are indistinguishable from a green badge ([CI and
standards](../CI-AND-STANDARDS.md), *"Blocking and advisory are not the same coverage"*). Where a
rule cannot be automated, record it as convention-only and therefore unenforced rather than letting
it pass as covered ([CI and standards](../CI-AND-STANDARDS.md), *"Ship the guard the same day as the
rule"*).

### What a gate has to do to count

- **A receipt.** It prints units examined, never units found, and zero units examined exits
  non-zero. [CI and standards](../CI-AND-STANDARDS.md), *"Receipts: count what the check examined,
  never what it found"*.
- **A proof it can fail.** Fire the failure class at it, watch it go red, confirm the injected
  defect landed, record the date. [CI and standards](../CI-AND-STANDARDS.md), *"Attack the control
  with the failure class it was built to catch"*.
- **One check over every instance**, not a control applied where somebody remembered it.
  [AI-assisted development](AI-ASSISTED-DEVELOPMENT.md), *"Control parity is a review gate"*.
- **Audit mode first** for anything that can reject. [Dependency
  integrity](DEPENDENCY-INTEGRITY.md), *"Roll a blocking verification control out in audit mode
  first"*.
- **Its own tooling installed from a checked-in lock**, inside the machinery that regenerates your
  runtime locks. [Code quality](CODE-QUALITY.md), *"Install the gate's own tooling from a checked-in
  lock"*.

A control that exists only locally is advisory in practice regardless of intent. The ways a gate
lies while reporting green belong to [CI and standards](../CI-AND-STANDARDS.md) and [the leak
gate](../LEAK-GATE.md); read them there.

### What you cannot automate, and must therefore give to a person

At least these, and your setting will add more. Say them out loud in your own record, because a
green control plane otherwise implies coverage it does not have.

- **The risk tier decision.** No detector exists. It is a human checklist whose whole guarantee is
  that it fails closed and leaves a recorded reason.
- **The quality of a threat model.** A gate can verify one exists. Nothing verifies it is any good.
- **The explain-it floor.** [Human review of code](REVIEW-DEPTH.md), *"The floor: reject code you
  cannot explain"*.
- **The outbound channel.** A commit-time scanner sees what lands in a commit, not an outbound
  query, a tool-server call or a fetch argument. [AI-assisted
  development](AI-ASSISTED-DEVELOPMENT.md), *"A commit scanner is not a live interceptor"*.
- **Independent external review.** Among the controls an internally-run pipeline cannot substitute
  for, and its absence caps what you may honestly claim. [Secure
  development](SECURE-DEVELOPMENT.md), *"Independent external verification"*.

---

## Step 5: put the result where Claude Code reads it, and re-check it

**This is not a step zero.** You cannot write standing rules before you know which ones you keep --
steps 1 and 2 exist to remove rows, and a project instruction file written first would be
aspirational, which is worse than none because the next session acts on it. The procedure and the
mandatory stop are already published: edit the template down to what is true here, delete every rule
the target does not actually follow, then stop and get section-by-section human confirmation
([Here's what to feed to your AI coding assistant](../FEED-THIS-TO-CLAUDE-CODE.md), *"If they decide
to proceed"*).

The template's control table has exactly three columns and they are the outputs of three of the
steps: the control name is the worksheet row from step 1, the status is what survived step 2 and
where it sits in step 3's queue, and *Last proven able to fail* is step 4's receipt. See [the
template](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/CLAUDE.md.template),
*"The bar this project holds itself to"*.

Standing rules here are loaded by Claude Code at the start of every session, so a rule that is not
in that file is not in force for the actor writing most of the code. [The overview](OVERVIEW.md)
states the consequence: *"A standard that no such file references is a document, not a practice."*

**Extend the table past the five rows the template ships with.** Four of those five are Tier 1 rows
from [Code quality](CODE-QUALITY.md), *"Tier 1 -- durable controls, which carry the verdict"*
(architecture, types, dependencies, published artifact); the fifth, the secret scan, comes from
[Secure development](SECURE-DEVELOPMENT.md), *"Secrets and repository hygiene"*. So copying the
template verbatim leaves two of the six verdict-carrying Tier 1 rows out of your table altogether:
*tests verify behavior*, and *security scanning plus a threat model* in all three of its parts --
blocking scanners, a written threat model, and a human review step. The secret scan does not stand
in for the scanner part: secret scanning is one of three checks in the unwaivable blocking set, not
the whole of it ([Secure development](SECURE-DEVELOPMENT.md), *"What must block, and may not be
waived"*). Not-built rows point at their register entry. What could not be automated appears as a
standing rule rather than a table row. Alongside the table, record the revision of each source
document you tailored from and the release at which the table is next re-read.

**Then re-check it on a cadence:** at each release, in the same pass that re-runs the scorecard, and
**do not upgrade a row because a run went green** -- green is also what a check that examined nothing
produces. That re-check is what makes "a marathon, not a sprint" operational rather than
aspirational, and it returns you to step 1 with the same worksheet.

---

## Worked example: dependency integrity, end to end

Four rows of one document, through all five steps -- not the whole document, and not the required
scope of a first pass. [Dependency integrity](DEPENDENCY-INTEGRITY.md) is the example because [the
overview](OVERVIEW.md) calls its controls the most mechanical of the set and the one most likely to
be adopted close to whole, and because it holds both a clear Partial and a control that can never be
automated.

### Step 1 -- the baseline

| Control | From | Status | Evidence | Last proven able to fail |
|---|---|---|---|---|
| Every manifest has an audit | *Every manifest in the repository needs its own audit net* | **absent** | Enumeration found a second manifest -- a build tool with its own dependencies -- with no audit | never |
| The pin is enforced at install | *Pin the resolved graph, and enforce the pin at install* | **partial** | Lock records versions, not digests; install does not refuse an unpinned artifact | never |
| A blocking dependency audit | *What must block, and may not be waived* | **partial** | Audit job exists on the primary manifest and does not block | never |
| Any of the above proven able to fail | *Attack the control with the failure class it was built to catch* | **unverified** | Nobody has watched any of them refuse anything | never |

The second manifest was invisible before the enumeration, because the dashboard reported the
repository as covered. The pin row is the point of the whole step: the question is not "do you pin"
but "does install refuse". The audit row is partial because a tool inventory is not coverage. The
last row stays unverified, which is not a pass.

### Step 2 -- tailor

**A legitimate tailoring with no register entry.** Which lock format, which audit tool, which
manifest layout -- the ecosystem mechanics are on that document's *"Change freely"* list under
*"Adapting this to your project"*. Changing them is adoption, not deviation, and it leaves no record
because none is owed.

**A deviation with a register entry.** There is no second reviewer for the adoption decision on a
new dependency, and verify-before-add is on the *"Do not weaken"* list precisely because it is the
one place a human is structurally required. Control not met: independent human review of the
adoption decision, accepted on a stated date. Compensating controls actually in force: blocking
analysis and a dependency audit an author cannot waive; an AI-run review a human arbitrates,
explicitly not an independent audit; branch protection with required checks; no direct pushes to the
integration branch. Trigger: a second maintainer joins. Pointer: where the intended adoption review
is written down.

The rule the contrast teaches: touching a *"Change freely"* list is tailoring and needs no record;
striking from a *"Do not weaken"* list is a deviation and needs all four fields.

### Step 3 -- prioritize

1. **Enumerate the manifests.** Nothing can be called coverage until you know what is uncovered.
2. **Make the lock record digests.** An advisory has nothing to resolve against otherwise, and
   enforcement has nothing to enforce.
3. **Enforce the pin at install.**
4. **Make the audit blocking on every manifest.**

Ease-first would have picked "turn the existing audit blocking" first, because it is a one-line
change. What that costs: a blocking audit on one manifest reads as coverage of the repository, and
the second tree stays unwatched while the badge improves. Risk and ease do legitimately decide two
things here -- which manifest to fix first, and whether the lock work happens this week or next.

### Step 4 -- automate

- **One deterministic parity check over all instances**, failing when a manifest exists with no
  corresponding audit entry, rather than a recurring manual sweep. *Every manifest in the repository
  needs its own audit net*.
- **Audit mode first** for anything that can reject an artifact, because a control that blocks
  legitimate work on day one gets switched off permanently and the second attempt is harder to fund.
  *Roll a blocking verification control out in audit mode first*.
- **A receipt:** the check prints how many manifests it examined, and zero examined exits non-zero
  rather than green. [CI and standards](../CI-AND-STANDARDS.md), *"Receipts: count what the check
  examined, never what it found"*.
- **Proof it can fail:** add a manifest with no audit entry, watch the check go red, confirm the
  injected defect landed, record the date. [CI and standards](../CI-AND-STANDARDS.md), *"Attack the
  control with the failure class it was built to catch"*.

**The refusal.** Verify-before-add is not automatable. A package that genuinely exists, publishes
files, is years old and is served under its own canonical name can still be a different project than
the one intended, and it passes everything (*"The hallucinated package, and why an AI coding
assistant makes it routine"*). It leaves the automation column and becomes a named human obligation
in the project instruction file.

### Step 5 -- wire it in

| Control | Status here | Last proven able to fail |
|---|---|---|
| Every dependency manifest has a blocking audit | `built` | `2026-08-06` |
| Lock records digests, and install refuses an unpinned artifact | `partial` | `never` |
| Independent review of a new dependency's adoption decision | `not built` | `never` -- see deviations register, entry DR-1 |

And the human obligation, as a standing rule rather than a table row: *before adding any dependency,
confirm the package is the project intended -- not a near-miss name, not a different project under a
plausible one. This is not automated and will not be.*

At the next release those rows are re-read, and the only row that may move up is one somebody has
watched refuse something since.

---

## The worksheet

The backlog for step 1, worked through over releases. It is not a prerequisite for starting -- a
reader who filled in only the seven-row starter set above has done step 1 honestly. It carries at
least the controls these documents ask an adopter to inventory; it is not a complete account of the
set, and your own setting will add rows.

### How to read the columns

| Column | What it means |
|---|---|
| **Control** | What it is, in one line. The document it came from is the authority on the detail |
| **From** | The heading in that document. Headings, never section numbers -- numbers move and headings survive a renumber |
| **Force** | **Blocking** where the set describes a check that must stop a change; **Advisory** where the output informs a person who arbitrates; **Written** where it is a record, a definition or a decision rather than a gate. A written control adds no blocking gate. That is not a demotion -- several of the highest-leverage rows here are written ones |
| **Cost** | A band, not an estimate. **Sitting** is under an hour of writing down what you already know. **Afternoon** is half a day for one person. **Days** is pipeline or code work. **Weeks** is a project with a design decision in front of it. **Per change** means little setup and recurring attention |
| **Usually** | Whether a competent team probably already has some form of it. **Common** means you almost certainly do. **Partial** means you likely have a weaker form that does not satisfy the rule as written -- these are the cheapest wins, because the shape is already there. **New** means genuinely new work. A prior, not a finding: overwrite it with what you observe |

### AI-assisted development

From [AI-assisted development](AI-ASSISTED-DEVELOPMENT.md).

| Control | From | Force | Cost | Usually |
|---|---|---|---|---|
| Every proposed control names which of five failure modes it neutralizes | *Five failure modes, and the control for each* | Written | Sitting | New |
| Risk tier resolved before work starts, in one question, with a recorded reason | *Classify in one question first* | Written | Per change | New |
| The resolver clamps up on unknown, unresolvable or production-facing changes | *The resolver: clamp to strictest, fail closed* | Written | Sitting | New |
| A short floor that applies at every tier, including throwaway work | *The universal floor, which never scales down* | Written | Sitting | Partial |
| No restricted data or secrets reach the AI coding assistant: a path deny-list plus a fail-closed commit-time content scan | *The universal floor, which never scales down* | Blocking | Days | Partial |
| Everything the AI coding assistant reads is data, never instructions | *The universal floor, which never scales down* | Written | Sitting | New |
| Reject code you cannot explain, at every tier | *The universal floor, which never scales down* | Written | Per change | New |
| The AI coding assistant's identity and version retained as a provenance signal | *The universal floor, which never scales down* | Written | Afternoon | New |
| Any restricted-data exception written as a conjunction, and recorded as enabled or merely defined | *The sanctioned exception, written so it cannot widen* | Written | Sitting | New |
| The AI coding assistant, its skills, extensions, tool servers and agent frameworks vetted, pinned and recorded as a build-environment surface | *The build tooling is a supply-chain surface nobody scans* | Written | Afternoon | New |
| Documentation states that a commit scanner is not a live interceptor of an outbound query | *A commit scanner is not a live interceptor* | Written | Sitting | New |
| Six control families set per tier, cumulative left to right | *Controls as dials* | Written | Afternoon | New |
| A gate is a deterministic check with an exit code; an AI-run review is advisory only | *Controls as dials* | Blocking | Days | Partial |
| A maintained project instruction file, treated as an artifact that is wrong when code stops matching it | *The project instruction file is a maintained artifact* | Written | Afternoon | Partial |
| Prompts quote the real invariant lines rather than gesturing at them | *Quote the invariant, do not gesture at it* | Written | Per change | New |
| A testable written intent before prompting, with the returned diff reviewed against it | *Write a testable intent before prompting* | Written | Per change | Partial |
| Context hygiene: memory holds facts and never values, compaction targets interface shape and decisions, and degradation has a recovery procedure | *Memory holds facts, never values*; *Compaction is a choice about what to keep*; *Recovering from context degradation* | Written | Sitting | New |
| Sibling paths enumerated when a control is added or changed, encoded as one deterministic check where feasible | *Control parity is a review gate* | Blocking | Days | New |
| A provenance convention counted in the actual history before being cited as a built control | *Provenance: record it, and count it before you cite it* | Written | Afternoon | New |
| No second reviewer recorded as a deviation with a named compensating set and an end condition | *When there is no second reviewer* | Written | Sitting | New |
| A deviations register with four fields, dated and signed | *The deviations register* | Written | Afternoon | New |
| A claims register holding the exact approved wording next to its evidence | *Claims and wording* | Written | Afternoon | New |
| The attestation posture stated structurally near the top of whatever you publish, not as a footnote | *The attestation posture* | Written | Sitting | New |
| An adversarial verification pass whose verifiers did not produce the artifact and are told to refute | *The adversarial verification pass*; *The shape that keeps a pass independent* | Advisory | Days | New |
| Agent-surfaced findings reported as candidates until confirmed, separately from confirmed ones | *Findings from a sweep are candidates, not findings* | Written | Sitting | New |
| A stop rule and a scoped read-only pilot before the pass is run at width | *When the pass earns its cost, and when it is waste* | Written | Sitting | New |

### Human review of code

From [Human review of code](REVIEW-DEPTH.md).

| Control | From | Force | Cost | Usually |
|---|---|---|---|---|
| Review depth resolved per change by tier, before work starts | *Human review depth follows risk and is decided per change* | Written | Per change | Partial |
| The sensitive-data ratchet dominates size, and unknown clamps up | *Human review depth follows risk and is decided per change* | Written | Sitting | New |
| Two conditions that force a full line-by-line read regardless of tier | *Two conditions that force a full read regardless of tier* | Written | Per change | New |
| The explain-it floor, which never turns off | *The floor: reject code you cannot explain* | Written | Per change | New |
| A written, organization-wide choice on whether assisted explanation satisfies the floor, plus a record of where the looser reading was taken | *AI-assisted explanation is contested, and accepted here with guardrails* | Written | Sitting | New |
| A question set for telling a real review practice from a described one | *What to ask a team, and what a good answer sounds like* | Advisory | Sitting | New |

### Code quality

From [Code quality](CODE-QUALITY.md). The first six rows are the tier that carries the verdict.

| Control | From | Force | Cost | Usually |
|---|---|---|---|---|
| Module and layer boundaries machine-checked in the pipeline, not documented | *Tier 1 -- durable controls, which carry the verdict* | Blocking | Days | New |
| Strictest available type checking, no blanket suppressions, every suppression carrying its error code | *Tier 1 -- durable controls, which carry the verdict* | Blocking | Weeks | Partial |
| Tests assert real values and failure paths rather than mock choreography | *Tier 1 -- durable controls, which carry the verdict* | Blocking | Weeks | Partial |
| Dependency integrity present: existence-verified, hash-locked, new imports audited | *Tier 1 -- durable controls, which carry the verdict* | Blocking | Days | Partial |
| Security scanners blocking, plus a written threat model and a human review step | *Tier 1 -- durable controls, which carry the verdict* | Blocking and advisory | Days | Partial |
| A released package ships only intended content, gated before the irreversible upload | *Tier 1 -- durable controls, which carry the verdict* | Blocking | Days | New |
| Mutation on changed code, surfacing tests that assert little | *Tier 2 -- the measurement layer, which is guidance and triage* | Advisory | Days | New |
| Coverage reported on changed lines, never as a repository percentage gate | *Tier 2 -- the measurement layer, which is guidance and triage* | Advisory | Afternoon | Partial |
| New copy-paste flagged on the diff, with deliberate parity whitelisted | *Tier 2 -- the measurement layer, which is guidance and triage*; *Tell an applying tool which duplication is deliberate* | Advisory | Afternoon | New |
| A broad static-analysis ruleset enforced, widened from a clean baseline | *Tier 2 -- the measurement layer, which is guidance and triage*; *Widen a blocking lint ruleset from a clean baseline* | Blocking | Afternoon | Common |
| Genuinely large units surfaced for a human, never gated on | *Tier 2 -- the measurement layer, which is guidance and triage* | Advisory | Afternoon | Partial |
| No single gameable number certifies quality or fails a build | *The anti-metric rule (hard)* | Written | Sitting | New |
| Every control names the failure mode it neutralizes and the document that owns it | *Failure mode, control, owner* | Written | Afternoon | New |
| Gate placement by cost: cheap gates in both places, expensive ones pipeline-first but locally invocable | *Where each gate belongs: the local loop, the pipeline, or both* | Written | Afternoon | Partial |
| A tool that applies fixes runs before the local check quartet, never after | *Run an applying tool before the local check quartet, never after* | Written | Sitting | New |
| An applying tool is not a control and may not be scored as one | *An applying tool is not a control, and it may not be scored* | Written | Sitting | New |
| Gate placement re-derived from scratch after any repair to the gate | *Re-derive placement after any repair to the gate* | Written | Sitting | New |
| No row recorded as built without a receipt proving the check examined something | *Never record a row as built without a proof-of-execution receipt* | Written | Afternoon | New |
| Advisory findings computed as a delta against the merge base and annotated where the reviewer already is | *Make an advisory finding a delta against the merge base*; *Put advisory findings where the reviewer already is* | Advisory | Days | Partial |
| Gate tooling installed from a digest-recording lock, inside the same export machinery as the runtime locks | *Install the gate's own tooling from a checked-in lock* | Blocking | Days | New |
| Volatile counts kept out of narrative text | *Keep volatile counts out of the narrative* | Written | Sitting | New |
| Every file classified into a review depth tier, with the classification published and a line count per tier | *Reviewing the code: depth tiers* | Written | Per change | New |
| Review records anchored to a symbol name rather than a line number | *Anchor a review record to a stable name, not a line number* | Written | Sitting | New |
| Trust boundaries reviewed against a fixed question set rather than by reading the body | *Reviewing a trust boundary* | Written | Per boundary | New |
| The control plane confirmed -- present, blocking, green on the released commit -- before any code is read | *Confirming the control plane* | Written | Afternoon | New |
| Where review is self-review, the deviation recorded and the compensating control named | *When review is self-review* | Written | Sitting | New |

### Dependency integrity

From [Dependency integrity](DEPENDENCY-INTEGRITY.md). Its controls are the most mechanical in the
set, and the ones most likely to be adopted close to whole.

| Control | From | Force | Cost | Usually |
|---|---|---|---|---|
| Third-party code managed as a black box, with human effort concentrated at adoption and at each bump | *Third-party code is code of unknown provenance, and the discipline says so* | Written | Sitting | Partial |
| Behavior you depend on tested at your own integration boundary | *Third-party code is code of unknown provenance, and the discipline says so* | Blocking | Days | Partial |
| On a security-critical seam, the widely reviewed library chosen as the mitigation, with the reason recorded | *Choosing a widely reviewed library is the mitigation for not reading it* | Written | Per dependency | Common |
| Verify before add: a real package rather than a near-miss, maintained, acceptably licensed, actually used -- with a dated vet note | *The hallucinated package, and why an AI coding assistant makes it routine* | Written | Per dependency | Partial |
| Explaining code and reading dependencies held as different obligations | *Explaining code and reading dependencies are different obligations* | Written | Sitting | New |
| Vendored code held to first-party gates in the same change: behavior tests, a mirrors-what header, analysis scope extended | *Vendored code is owned code, not a dependency* | Blocking | Days | New |
| Every manifest enumerated, each with scheduled surveillance and a blocking install-free audit | *Every manifest in the repository needs its own audit net* | Blocking | Days | Partial |
| Build-time-only trees surveilled and triaged as a different impact class, not exempted | *Every manifest in the repository needs its own audit net* | Written | Sitting | New |
| The resolved graph pinned by digest, and the pin enforced at install rather than only at resolution | *Pin the resolved graph, and enforce the pin at install* | Blocking | Days | Partial |
| Each version bump a bounded review: changelog and lock delta, with the pipeline re-auditing and re-testing | *The version bump is a bounded review* | Written | Per bump | Partial |
| A least-privilege runtime bounding the blast radius of code nobody reviewed | *Contain what you cannot vouch for* | Written | Weeks | Partial |
| An allowlist of what the published artifact contains, gated before upload, with the published artifact verified once after release | *The artifact contains only what you declared* | Blocking | Days | New |
| Publishing credentials minted per run and workflow-bound, the trigger restricted, the publish action pinned | *Publishing credentials should be minted per run, not stored* | Blocking | Days | New |
| An attestation binding the distributed filename and its digest to the repository, workflow and commit | *Publishing identity does not cover the artifact* | Written | Days | New |
| Signature coverage and verifiability both measured before a signing control is credited | *A signing scheme nobody can verify is not a control* | Written | Afternoon | New |
| Build provenance, plus a signed digest manifest with a documented offline verification path | *Build provenance, and the lowest-tech verification path* | Written | Days | New |
| A component inventory per release, described as answering "do we ship X" and never as tamper detection | *A component inventory is not tamper detection, and saying so matters* | Written | Days | Partial |
| Each release archived with its build inputs and its inventory together | *Archive each release with its build inputs and its inventory* | Written | Days | New |
| A self-integrity check shipped with its bootstrap-trust limit stated in the same paragraph | *The self-integrity check, and the bootstrap-trust problem* | Written | Days | New |
| Operator-side hardening documented and recommended, never claimed as a control you provide | *Operator-owned hardening: document and recommend, never claim* | Written | Days | New |
| Any blocking verification control rolled out in audit mode first | *Roll a blocking verification control out in audit mode first* | Written | Sitting | New |
| The objective stated as detection rather than prevention | *State the objective honestly: detection, not prevention* | Written | Sitting | New |
| Obfuscation not counted as the integrity story for source you publish | *Obfuscation is not the integrity story for source-available code* | Written | Sitting | New |
| Ecosystem-specific mechanics separated from the universal rules when you adapt | *Which rules are universal, and which are one ecosystem's mechanics* | Written | Sitting | New |

### Secure development

From [Secure development](SECURE-DEVELOPMENT.md). This is the widest of the set and the one you
should expect to rewrite rather than adopt. It is also under active revision, so treat this table as
lagging its current headings rather than as a complete account of them.

| Control | From | Force | Cost | Usually |
|---|---|---|---|---|
| A producer-versus-operator responsibility split, written before any control is claimed | *Shared responsibility: write the split down first* | Written | Sitting | New |
| The services neither column owns, listed, with what fails if one goes away | *The third participant: services neither column owns* | Written | Sitting | New |
| One data-class table: class, the boundary it enters on, every place it rests, the protection at each, and how long it is kept | *What "restricted data" means here, exactly once* | Written | Afternoon | New |
| Each class rated against three security objectives at three impact levels | *What "restricted data" means here, exactly once* | Written | Sitting | New |
| A written threat model per trust boundary, reviewed before the code exists | *Threat model each trust boundary before you build it* | Advisory | Days | Partial |
| A named bound on resource consumption for every boundary: payload size, request rate, concurrency, total time | *Threat model each trust boundary before you build it* | Written | Afternoon | New |
| A scheduled malformed-input harness behind every ingress, classified advisory, with each crash turned into a regression test | *Threat model each trust boundary before you build it* | Advisory | Days | New |
| A longer question set applied wherever content becomes executable | *Execution boundaries need the longest look* | Written | Per boundary | New |
| A finite secure-coding list a reviewer can actually check | *Secure coding: the finite list a review can check* | Written | Sitting | Partial |
| Every change peer-reviewed against the acceptance criteria of whatever specified it | *Review, and what to do when there is no second reviewer* | Written | Per change | Common |
| Self-review recorded as a documented deviation rather than a satisfied control | *Self-review is a documented deviation, not a satisfied control* | Written | Sitting | New |
| A comprehension bar the reviewer must meet | *The comprehension bar, and two additions to it* | Written | Per change | Partial |
| Every nominally-security job classified blocking or advisory, and the classification written down | *Scanner posture: what blocks, what advises, what may never be waived* | Written | Sitting | New |
| An unwaivable blocking set: static analysis, dependency vulnerability analysis, and secret scanning over the full history | *What must block, and may not be waived* | Blocking | Days | Partial |
| Each gate fired with the failure class it exists to catch, and watched going red, before its green is credited | *Three additions specific to a security posture* | Written | Afternoon per gate | New |
| Rigor and scope recorded as two separate values against each blocking check | *Three additions specific to a security posture* | Written | Sitting | New |
| The security anti-metrics kept out of any pass-or-fail decision | *The security anti-metrics* | Written | Sitting | New |
| No secrets, keys, credentials or restricted data in the repository, with the full history clean and not only the current tree | *Secrets and repository hygiene* | Blocking | Days | Partial |
| Secure by default, with every insecure posture a named, documented, audited, fail-closed opt-in | *Secure defaults, and the opt-in that must be explicit* | Written | Weeks | Partial |
| Off-by-default and fail-closed scored and described as different states | *Secure defaults, and the opt-in that must be explicit* | Written | Sitting | New |
| Synthetic data everywhere that is not production, with any live data approved, dated and in the register | *Synthetic data by default in anything that is not production* | Written | Days | Partial |
| A collection rated by the highest class it holds, never the average and never per entry | *Rate a collection by the highest class it holds* | Written | Sitting | New |
| Machine-to-machine authentication at the strongest mechanism the peer supports, recorded per connection with weak ones as a short explicit list | *Machine-to-machine authentication* | Written | Weeks | Partial |
| No long-lived secret in a file for a service account, and no cleartext directory bind | *Service accounts: no long-lived secret in a file* | Written | Days | Partial |
| An append-only, timestamped, actor-attributed audit log with a hash chain, reads gated, and restricted data kept out of it | *Tamper-evident audit logging* | Written | Weeks | New |
| Publishing controls each carrying the limit that travels with it | *Publishing controls, and the limit each one carries* | Written | Days | New |
| A verification path an adopter can run without contacting you | *What an adopter can verify without contacting you* | Written | Days | New |
| Obfuscation not treated as a security control | *Obfuscation is not the control you are looking for* | Written | Sitting | New |
| Runtime integrity checking shipped as defense in depth, with the bootstrap-trust limit documented in the same paragraph | *Runtime tamper resistance, and the bootstrap-trust limit* | Written | Days | New |
| Operator-side hardening documented and recommended, with a concrete day-one list, never claimed | *Operator-owned hardening: document and recommend, never claim* | Written | Days | New |
| Any blocking verification control started in audit mode | *Roll out a blocking verification control in audit mode first* | Written | Sitting | New |
| A vulnerability response program with a private intake channel, banded windows, root-cause review and coordinated disclosure -- exercised end to end at least once | *Vulnerability response, exercised* | Written | Days | Partial |
| The clock start stated next to each remediation window, per finding class | *Vulnerability response, exercised* | Written | Sitting | New |
| A deviations and risk-acceptance register, dated and signed, whose rule is published and whose inventory is not | *Deviations and risk acceptance* | Written | Afternoon | New |
| Added practices marked as recommended, stating that they add no blocking gate and weaken nothing above them | *Deviations and risk acceptance* | Written | Sitting | New |
| Independent external verification status recorded plainly, with cost context, and not gating an adopter's rollout | *Independent external verification* | Written | Sitting | New |
| A release gate written as an explicit pass-or-fail list, leaning on no unsigned acceptance, with no single row as the gate | *The release gate* | Blocking | Days | Partial |
| The control plane confirmed before any code is read, and the suppression list reviewed rather than accepted | *Confirm the control plane before reading any code* | Written | Afternoon | New |
| A claim vocabulary: built to, aligned with, self-assessed against -- never certified, verified or compliant | *What you may claim* | Written | Sitting | New |
| Another document's target or score never restated; the record of record named and linked | *What you may claim* | Written | Sitting | New |
| Every borrowed source named with its release and the date its status was last checked | *Where the rules come from* | Written | Sitting | New |

### If you run a formal assessment against a published standard

From [Security standard assessment](../ASVS-ASSESSMENT.md). These apply only if you assess a codebase
against a standard with many individually verifiable requirements. Skip the whole table otherwise.

| Control | From | Force | Cost | Usually |
|---|---|---|---|---|
| The standard's own text held locally, fetched from a tagged release asset and pinned by digest | *Hold the standard's own text locally, pinned by version*; *Pin the corpus, and stamp the version on every number* | Written | Afternoon | New |
| One computed record as the authority, with the scorecard existing as data rather than prose | *One computed record is the authority* | Written | Days | New |
| A published verdict vocabulary in which unverified can never read as a pass | *A verdict vocabulary that cannot be misread*; *`unverified` must never look like a pass* | Written | Sitting | New |
| An ordered decision procedure, first match wins | *The decision procedure: ordered, first match wins* | Written | Afternoon | New |
| Scope declared positively, with one requirement scored against one declared configuration | *Declare scope positively*; *One requirement x one declared configuration is the reviewable unit* | Written | Sitting | New |
| Not applicable argued rather than assumed, and the strength of each such verdict graded | *Not applicable must be argued, never assumed* | Written | Per cell | New |
| Evidence anchored to a token a machine can re-check, with the anchor verifier running in the pipeline and watched failing on purpose | *Evidence: an anchor a machine can re-check*; *Anchor to a token, not to a line number* | Blocking | Days | New |
| No absence claim without a live positive control | *An absence claim without a live positive control is void* | Written | Per claim | New |
| Never score against a paraphrase of the requirement | *Never score against a paraphrase* | Written | Per cell | New |
| Any movement in a score reported with its cause named, and zero movement stated as a result | *How to read a movement in the numbers* | Written | Sitting | New |
| Reviewers execute the citation rather than reading it, with distinct lenses | *Make the reviewer execute the citation, not read it* | Written | Days | New |
| Impact sentences for software nobody has deployed written in the conditional tense, with no score altered | *Deployment-time controls in software nobody has deployed* | Written | Sitting | New |
| Atomic cell claims, one integrator owning every write, and a collision detector at integration | *Partitioning the work across agents* | Written | Days | New |
| The findings themselves kept private | *Checklist* | Written | Sitting | New |

---

## Adapting this page to your setting

**Change freely:**

- **The cost bands.** Calibrated for a small team. A row that is a sitting here can be a quarter
  somewhere with a change advisory board.
- **The "usually" column, entirely.** Your observed baseline replaces it on first contact.
- **The grouping of the worksheet** -- by owning team, by surface, or by release.
- **The depth of the step-3 queue.** Three is chosen so it cannot become a schedule. Two is fine.

**Do not weaken:**

- **The record left by step 2.** A tailoring decision with no date, no compensating control and no
  trigger reads later as an oversight.
- **The unverified verdict.** A row nobody checked is not a pass.
- **The proof that a gate can fail.** It is the difference between a control and a claim.
- **The dependency ordering in step 3.** Risk and ease may break a tie inside a layer. They may not
  move an item into a layer whose precondition does not exist yet.
- **The step-2 test.** Naming the outcome a practice asks for and how you meet it is tailoring;
  concluding the question no longer arises is the failure.

## Related

| For | Read |
|---|---|
| What to read, and in what order | [Standards you can start from](OVERVIEW.md) |
| The two-page version for a security executive | [The CISO summary](CISO-SUMMARY.md) |
| Where a project keeps its standing rules, and a table for what is live | [The `CLAUDE.md` template](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/CLAUDE.md.template) |
| How these sit against the mainstream frameworks | [The standards reference](STANDARDS-REFERENCE.md) |
| Gates, receipts, claim honesty, and why a check that cannot fail is not a control | [CI and standards](../CI-AND-STANDARDS.md) |
| A fail-closed content scanner and the blind spot no scanner closes | [The leak gate](../LEAK-GATE.md) |
| The same reasoning applied to one repository's own controls | [Case study: a drift audit](../CASE-STUDY-drift-audit.md) |
