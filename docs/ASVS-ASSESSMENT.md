# Running a large security-standard assessment with AI agents

**Several hundred requirements is not the hard part. The hard part is that an agent returns a
confident, well-cited verdict for every one of them, and the wrong ones are indistinguishable from
the right ones by reading.**

Written for whoever has to run one of these and then answer for the result. The worked standard is
OWASP ASVS 5.0 -- a catalog of several hundred individually verifiable security requirements for web
applications and services -- and most of what is here transfers to any standard large enough that
one person cannot read it carefully in a week.

> **Take a copy:**
> [markdown](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/ASVS-ASSESSMENT.md)
> or [Word document](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/ASVS-ASSESSMENT.docx).
> [Every file, both formats](standards/OVERVIEW.md#the-files).

---

## TLDR/BLUF

**Almost every defect this method exists to catch is an instrument answering a narrower question
than the one you asked, and looking clean while it does it.** We scored a batch of requirements
against condensed wording. A requirement carrying two conditions had become a summary carrying one,
so every cell under it was honestly reasoned and still wrong, and nothing in the output said so. A
condensed requirement, a neighbouring requirement, a search that could not have matched, a control
that ships switched off: each produces a verdict that is internally consistent, well argued, and
answering a question nobody asked.

Fluency is what makes it stick. An agent will produce on-topic, well-structured reasoning about a
requirement whether or not it read the requirement, whether or not the file it cites supports the
claim, and whether or not the search it ran could have returned anything. A person who has not done
the work usually looks like someone who has not done the work. An agent that has not done the work
looks exactly like one that has.

So what follows is not a scoring rubric. It is a set of forcing functions that make the difference
between a real verdict and a fluent one mechanically visible. The order matters, because each step
is worth little without the one above it:

1. **Build the corpus first.** Hold the standard's own text locally, pinned to a version. Score
   against a summary instead and every verdict quietly answers a narrower question than the standard
   asked.
2. **Fix the verdict vocabulary** before a single cell is scored. The standard supplies none, so two
   sessions will each invent a reasonable one and produce verdicts nobody can reconcile afterwards.
3. **Declare scope positively**, and argue every exclusion rather than assuming it. Scoping a
   requirement out does not buy you the level.
4. **Partition on both axes.** The collision that actually costs you is not two agents editing the
   same row; it is two agents applying different unwritten rules and neither recording which.
5. **Run the review pass.** This is where most of the wrong answers are actually caught, and it is
   the step that gets cut when the schedule slips.

If you take one rule from this page: **a verdict that does not quote the requirement's own words has
not been assessed**, however well it reads.

## What one scored cell looks like

Every forcing function above is a claim about record-keeping, so here is the shape itself. This is an
illustrative skeleton, not a result -- every value is a placeholder:

```toml
[cell."<chapter>.<section>.<requirement>"]
verdict   = "partial"   # local extension; defined in the vocabulary table
quoted    = "<the requirement's own description text, copied out of the pinned corpus>"
version   = "<the standard version that text was pinned at>"
rule      = "ships-off" # WHICH written rule produced this verdict
evidence  = ["<path>:<lines>", "<path>:<lines>"]
reviewer  = "<session>"
scored_at = "<timestamp>"
```

Five of those seven fields exist only so that a later reader can disagree with the verdict.
`quoted` and `version` make it re-checkable without scoring it again from scratch; `rule` names
which written rule produced it, so two sessions' verdicts can be compared rather than merely
counted; `reviewer` and `scored_at` make staleness visible. A cell carrying only a grade and a file
path is not a cheaper version of this. It is a verdict that cannot be defended.

## What this costs you, and where it does not apply

- **This document contains no results, and that is deliberate.** An assessment's findings are a map
  of where a system is weak: which control is off, which surface is uncovered, which item nobody has
  got to yet. That map belongs in a private record with the people who can act on it, not in a
  public repository. So nothing below states a verdict, a count, a percentage, or a level attainment
  for any codebase, and the same rule should govern whatever you produce. To find out where a system
  stands, run the assessment against that system -- do not read someone's published summary of
  theirs. Publishing the method invites scrutiny of the reasoning; publishing the register invites
  something else.
- **It confers no certification, and neither does ASVS.** OWASP publishes the standard; no body
  assesses you against it. Nor is a level a score: there is no partial credit and no percentage.
- **It quotes no price and no duration, on purpose.** Per-cell verification at this rigour is
  expensive enough that naive extrapolation across a full standard will shock whoever is paying for
  it, so establish your number early -- by timing a pilot section of your own, not by taking one
  from a page that has never seen your codebase. A figure printed here would be wrong for you and
  would get planned against anyway.
- **The savings are real but they come from one place: batching by shared precondition.** One
  applicability investigation can serve an entire section, and one posture question can settle a
  dozen cells. They never come from cutting rigour on a cell, because an unearned verdict is the
  whole defect this exercise exists to prevent. A cheaper assessment that produces unearned passes
  has not saved anything; it has bought a document that reads like an assessment.
- **The ASVS summary in the next section is orientation, not the thing you assess against.** If your
  level definitions come from this page rather than from the pinned text, you have already made the
  mistake this document exists to prevent.
- **No speed claim.** Nothing here is measured as a productivity gain. What the method buys is
  auditability and verdicts that survive being challenged.

---

## What ASVS is, before any of the rest

The OWASP Application Security Verification Standard is a list of security requirements for web
applications and services, written so that each one can be checked individually and answered yes or
no. It is not a scanner, not a certification, and not a process. It is a catalog of things a
reviewer can verify, grouped into chapters by subject -- authentication, session management, access
control, validation, cryptography, and so on.

Two properties make it useful and awkward at the same time. It is **large**: several hundred
individually verifiable requirements, which is far more than one person reads carefully in a week.
And it is **specific**: each requirement is written to be checkable, so a requirement either holds
for your code or it does not, and "roughly, yes" is not one of the answers.

The requirements are tiered, and the tiers are cumulative -- each level contains everything below
it.

| Level | Who it is for | What it means in practice |
|---|---|---|
| **Level 1** | Every application, as a floor | The baseline. Achievable largely from the outside, without deep access to the code |
| **Level 2** | Applications handling sensitive data | The level most applications with real users should target. Assumes a reviewer who can read the source |
| **Level 3** | The highest-value applications | The most rigorous tier, for systems where a compromise is severe. Assumes deep review and defense in depth |

The thing that catches people out: **choosing a level is a scoping decision you have to argue, not a
difficulty setting.** Claiming Level 2 means every Level 1 and Level 2 requirement in scope has been
assessed -- and scoping a requirement out does not buy you the level, it just moves the argument to
the rationale you now owe.

One version note. **ASVS 5.0 is a renumbering, not an edition bump.** It reorganized the chapters
and renumbered requirements from 4.0, and identifiers do not carry across, so a mapping, a
spreadsheet, or an internal policy built on 4.0 numbers does not survive the move. If you inherit
prior work, expect to re-anchor it rather than translate it.

---

## Build the thing you will compare against, from the exact wording

**This is the first work item, before any scoring, any partitioning, any agent. Get the standard's
own text, held locally, pinned to a version. Do not let an AI coding assistant write you a summary of
the requirements and then assess against that.**

It is a tempting shortcut precisely because it looks like preparation rather than a corner cut. The
requirements are long, and a condensed version reads faster, fits in a prompt, and feels like a
reasonable working copy. The assessment then runs smoothly, produces confident verdicts, and every
one of them answers a slightly different question than the standard asked.

### How this cost us, concretely

We scored a batch of requirements against condensed wording. The verdicts looked clean and internally
consistent, which is exactly the problem -- nothing about the output signals that the input was
narrowed. The damage surfaced later, in two shapes:

- **Requirements that lost a clause in the condensing.** A requirement with two conditions became a
  summary with one. Every cell assessed against it was answered honestly and was still wrong, because
  the question had quietly shrunk.
- **Verdicts that could not be re-checked.** With no pinned text behind a cell, there was nothing to
  re-read when a verdict was challenged. The only way to settle it was to score it again from scratch.

The cost was not the first pass. It was **re-running work that had already been marked done**, and
the slower tax of not trusting any earlier verdict once one had been shown to rest on a paraphrase.
A verdict you cannot re-check is not cheaper than no verdict; it is more expensive, because it
occupies the slot where a real one would go.

### What to build instead

Hold the requirement text locally, pinned by version, in a form a machine can read back. Then every
verdict can name the requirement it answered and be re-read against it later. The corpus is also
what lets a later pass detect that the standard moved under you, which a summary cannot do at all.

The full mechanics -- how to pin, what to stamp on every number, and why a section name in the corpus
is checkable where chapter prose is not -- are in
[Never score against a paraphrase](#never-score-against-a-paraphrase) and
[Pin the corpus](#pin-the-corpus-and-stamp-the-version-on-every-number). Read those two before
starting, not when something goes wrong.

---

## Handing this to Claude Code

**Part 1 ends here.** Everything from this point on is written to be handed to an AI coding assistant
that will do the bulk of the scoring: the vocabulary, the decision procedure, the partitioning, the
review pass, and the traps that produce clean-looking wrong answers. It is a working method, not a
description of one, which is why its register changes from here -- it is addressed to the agent, not
to you.

To start, open Claude Code in the repository you want assessed and paste this:

```text
Read https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/ASVS-ASSESSMENT.md
from the heading "The standard supplies no verdict rubric" onward, and use it as the method for
assessing this repository against OWASP ASVS 5.0. Begin at step 1, building the pinned corpus, and
score nothing until that corpus exists.
```

The first pass will not produce a score, and it should not. It builds the corpus. Anything that
hands you a percentage before that exists is the failure this document is about.

New to the rest of this repository's tooling?
[Here's what to feed to Claude Code](FEED-THIS-TO-CLAUDE-CODE.md) is the front door. For the same
reasoning applied to this repository's own controls -- including why it also publishes no status
table -- see [the drift-audit case study](CASE-STUDY-drift-audit.md).

---

## The standard supplies no verdict rubric

ASVS 5.0's assessment guidance is *deliberately non-prescriptive*. It supplies scoping advice,
evidence expectations, and a reporting obligation -- and **no verdict rubric**. It names verified,
exception, and non-applicable-with-rationale. The words most assessors actually reach for --
"partial", "not implemented" -- appear nowhere in it.

**The gap is invisible until several agents work in parallel.** Each one arrives at a cell with a
reasonable, unwritten rule in its head, and each produces a defensible verdict. The same requirement
then changes grade inside a day, because two sessions weighed the same evidence differently. Nothing
looks wrong at any point: both verdicts are argued, and both cite real code.

**An AI-assisted assessment amplifies this, because agents are fluent.** An agent will produce a
paragraph of on-topic, confident, well-structured reasoning about a control whether or not it read
the requirement, whether or not the cited file supports the claim, and whether or not the search it
ran could have returned anything.

**Fluency is not the failure mode you are used to defending against.** The whole method below is a
set of forcing functions that make the difference between a real verdict and a fluent one
mechanically visible.

### Hold the standard's own text locally, pinned by version

You need the standard's actual text, held locally, pinned by version. If your project does not hold
it, obtaining it is step zero of the assessment, not an optimization -- see
[pin the corpus](#pin-the-corpus-and-stamp-the-version-on-every-number). Everything downstream
depends on an assessor being able to quote the requirement it is judging.

---

## One computed record is the authority

**Exactly one machine-readable scorecard is the authority.** Everything else links to it. Nothing
else restates it.

**A status written into prose is a copy.** It is correct on the day it is typed and rots silently
after. Prose is also where restatement is most tempting, because it reads well: a summary here, a
remediation note there, an architecture page mentioning where things stand.

**The observable symptom is inconsistent totals.** Several documents each assert one, each defensible
at the moment it was written, with no way for a reader to tell which is current.

| Rule | Why |
|---|---|
| The scorecard is data (TOML, JSON, CSV -- anything a script can read), not a document | A document cannot be verified; data can |
| **No prose document states a count.** Counts are computed from the scorecard and rendered | A typed number is a second source of truth from the moment it is typed |
| A document that needs a status **links to the record**, never restates it | Links do not drift |
| Every verdict records **who set it and when** | Staleness becomes visible; any verdict traces back to the pass that produced it |

If a document must display a number, generate that document. The cost of a small rendering script is
far below the cost of one afternoon spent working out which of four totals is real.

### A planning document published a figure nobody measured

**The mild version is annoying but survivable.** Several dated prose documents each assert a figure,
each superseded within weeks. Readers take whichever they found first and discover the figures do
not agree.

**The expensive version: a planning document published a figure that had never been measured.** Its
entire purpose was to tell the next person what to do, and two subsequent sessions planned against
it. It was wrong by roughly a factor of five. The plan's sizing, its sequencing and its
definition-of-done all inherited the error, each of them looking perfectly reasonable on its own terms.

Hence the sharper form of the rule: **one computed record; everything else renders it.** No document
*states* a figure; documents *derive* it. The priority ordering follows from that:

> **A stale rule in a dispatch document is worse than a stale number in a data file**, because every
> future worker inherits it before doing any work of their own.

### Derived numbers get recomputed, never adjusted

Whoever writes last **recomputes every derived number from source**. Never carry a total forward,
never delta-adjust one ("this pass moved two cells, so subtract two").

Two writers each adjusting a distribution independently can produce a **correct-looking total from
two wrong sets**, because the errors cancel. A matching total does not catch it; only a
two-directional comparison of the sets themselves does.

---

## A verdict vocabulary that cannot be misread

Publish the vocabulary **before the first cell is scored**, and mark each grade as either
standard-native or your own local extension. Anything you invented needs a written definition
precisely because nobody else has one.

| Verdict | Meaning | Native to the standard? |
|---|---|---|
| `pass` | The requirement's **verb** is satisfied by a **shipped default**, or by a gate that **refuses to start** when the precondition is absent | yes (*verified*) |
| `fail` | **No implementing control exists in any configuration** | yes (*exception*) |
| `na` | The requirement does not apply on the declared scope. **A written rationale is mandatory** | yes -- and the rationale is the one hard obligation the standard imposes |
| `partial` | A control exists but ships off, warns where the requirement says refuse, or covers only part of the in-scope surface | local extension |
| `needs-review` | Examined, but genuinely contested or blocked on a decision | local extension |
| `unverified` | **Not re-derived against the requirement's own text.** The cell carries a verdict from an earlier pass that reasoned from a paraphrase | local extension |

Three of these carry most of the weight.

### `unverified` must never look like a pass

Cells carrying an inherited grade look identical to freshly derived ones in a spreadsheet -- they have
a verdict in them. Merge them into a headline and you publish an average over judgments, some of
which were never made against the actual requirement. It renders like a measurement and is not one.

So give it a **distinct verdict value** and **exclude it from any pass total**. Report *verified* and
*not-yet-re-verified* as two numbers rather than one. Report **survey progress** -- how much of the
set has been read against the pinned text -- as its own figure, and say on every verdict total that
it covers examined cells only.

**The word itself was the bug.** The state meant *"inherited from an earlier assessment and never
re-read against the standard's own text"*. It was read as *"nobody has ever looked at this"*.

Those two readings are **re-verification debt** and **unexplored surface**, and they imply completely
different work: one is a re-derivation against text you already hold, the other is an investigation.
Everything downstream -- effort estimates, sequencing, what a reader thinks the deficit is -- forks on
which one the reader assumed.

Three things that worked:

- **Never fold it into a headline.** It is its own bucket, excluded from any pass total.
- **Make the renderer say what the state means, every time it prints it, in the same sentence.** The
  label alone will be misread; the label plus its definition will not.
- **Assert that the printed components sum to the printed total.** Free to write, and it caught a real
  defect: a summary line silently omitted one state, so the components did not add up and nothing said
  so.

The renderer failures were of a piece with the naming failure: one classified a read-and-parked cell
as never-read, which is the same confusion implemented in code.

**State the debt in accurate words for the same reason.** If those cells were graded before -- just
against a restatement -- then calling them "never examined" overstates the deficit and misdescribes
what has to happen next.

The honest phrasing is *"N verified against the pinned requirement text; M carry verdicts not yet
re-verified against it."* Overstating a deficit gets corrected, and the correction costs you
credibility on everything you got right.

### "It can be configured" is never a pass

This is the single most common agent over-claim, and it survives review because the evidence is
genuine: the control exists, it is well built, it is documented, and it works when enabled.

In a codebase where most security features are opt-in, this one misreading can convert a large
fraction of the assessment into unearned passes, with real code cited under every one.

A pass requires the verb satisfied by a **shipped default**, or by a **gate that refuses to start**
when its precondition is absent. A configurable-on control, a documented recommendation, and a signed
relaxation are all not passes.

### `partial` needs a distinguishing test or it becomes a wastebasket

`partial` is the grade an assessor reaches for when the answer is uncomfortable. Undefined, it
absorbs everything ambiguous and stops carrying information: a reader cannot tell whether it means
"nearly done" or "a hook exists that nobody implemented".

Define it as the **residual of the ordered procedure below**, not as a feeling. Require the cell to
say which of three shapes it is: *ships off*, *warns instead of refusing*, or *covers part of the
surface*.

Anything with no implementing code in any configuration is not partial -- it is a fail. Anything
satisfied by a shipped default is not partial -- it is a pass.

### When uncertain, take the worse grade

**When uncertain between two grades, take the worse one.** An unearned pass is the specific failure
the whole exercise exists to prevent. Write this down; it is the rule agents most need permission to
apply.

---

## The decision procedure: ordered, first match wins

**Make the questions a numbered sequence, and let the first matching rule decide.** Weighing the
whole picture per cell feels more rigorous than a checklist. It produces results that are defensible
one at a time and unstable across the set, because identical evidence lands differently depending on
which consideration the assessor happened to weigh first.

The sequence, first match wins:

1. **Does the requirement apply on the declared scope?**
   No -> `na`, and write the rationale. No rationale, no `na`.
2. **Has this cell been read against the requirement's own text at a pinned version?**
   No -> `unverified`. *This is not a pass.*
3. **Does code implementing the requirement's verb exist anywhere in the tree, reachable by any
   configuration?**
   No -> `fail`.
4. **Is the verb satisfied by a shipped default, or by a gate that refuses to start when the
   precondition is absent?**
   Yes -> `pass`.
5. **Otherwise** -> `partial`.
6. **If two assessors following 1-5 disagree** -> `needs-review`, with the disagreement recorded.

**The ordering is load-bearing, not cosmetic.** Asking *"is the verb's subject in scope?"* before
*"does code implement the verb?"* produces a different answer than the reverse. Both orderings are
defensible right up until you pick one and write it down. A cell that has moved between grades
repeatedly is usually a cell where two people applied the same rules in different order.

**Record which rule fired on each cell.** That single field turns a later disagreement into a
one-question argument instead of a coin flip: you argue about applicability, or about defaults, not
about the verdict as a whole.

**Keep worked examples of the genuinely hard calls** in the method document, written so the next
agent reaches the same answer rather than re-litigating it from scratch. Keep the examples'
*reasoning* public and their *subject* private if the finding is sensitive; the shape of the call is
the transferable part.

---

## Declare scope positively

Scope written as a list of exclusions grows to swallow inconvenient cells, because each new exclusion
looks like a small extension of the last one.

State what **is** assessed: which artifacts, as source, at a named commit, against which requirement
set at which level. The scoping question then becomes *"is this verb's subject one of the declared
artifacts?"* -- answerable -- instead of *"is this excluded?"* -- arguable.

### One requirement x one declared configuration is the reviewable unit

Assessing "the product" invites an implicit matrix: this control holds in the hardened deployment,
that one in the default. Cells get scored under one frame and carried into another, until a verdict
exists whose frame cannot be recovered from the record at all. That is not a hypothetical failure
mode; a retired two-posture split is exactly how it happens.

**Declare one posture in prose** -- backend, network position, auth on or off, data classification,
what is bound where -- and score everything against it. Where a documented opt-in would change the
answer, record the delta as a **residual on the cell**, never as a second column.

A good unit is small enough that one agent can hold the requirement text, one implementing code path,
and one evidence pointer in a single context window.

---

## Not applicable must be argued, never assumed

`na` is the grade with the highest yield and the lowest resistance. It removes work and improves the
shape of the record at the same time, and every individual exclusion sounds sensible. Left undefined,
it eats the assessment.

**The test is on the verb's subject.** Ask what the requirement demands be true, and *of what*. If
the subject is the substrate the software is deployed onto -- host, hypervisor, CPU, firmware,
network, or the deploying organization's own controls -- rather than the artifacts you declared in
scope, `na` is defensible. Write the rationale; no rationale, no `na`.

Guard that boundary in **both** directions.

**Reporting on a property is not providing it.** Shipping code that observes, measures, or gates on
a substrate property does not make the cell in-scope. This is the trap that survives review best,
because the cited code is real, relevant, and in exactly the right area.

**The substrate merely being involved does not make the cell out-of-scope.** Neither the presence
nor the absence of surrounding code settles applicability on its own.

### Grade the strength of the `na`

All `na`s get written the same way. A cell that is out of scope by physics therefore reads
identically to one that is out of scope only because you are relying on the deploying organization to
cover it. The second kind is a **transferred obligation wearing the costume of a closed question**.

Say on the cell how strong the exclusion is. The `na` is **conditional** if the product ships a seam
it could have implemented, or if the exclusion assumes an enterprise control covers some path. Write
that assumption as an explicit **deployment requirement**, and flag the paths where the premise is
least certain.

### Building a control can create the obligation

A conditional requirement (*"when using X..."*) is correctly `na` while its precondition is false and
unreachable. Building X later makes it applicable, with nothing implementing it and no signal that
anything changed.

When a rationale depends on a precondition being unreachable, **write that dependency onto the cell**
and re-check those cells whenever the feature they depend on is proposed.

### Scoping a cell out does not buy the level claim

Once the `na`s are well-reasoned and documented it is a very short step to writing the level as
attained. The record says excluded, the summary says verified, and both authors think they are being
accurate.

Two facts make that indefensible.

**The standards body assigns each requirement to a level** and retains authority over the requirement
set. A level claim that omits requirements it places at that level is non-conformant on the
standard's own terms, however good the argument.

**Check whether the edition you are assessing against** still contains any clause preserving a
compliance claim under documented exclusions. Older editions of a standard may say things the current
one dropped, and a rationale citing dropped text is citing a superseded standard.

**Therefore:** treat scoping as a statement about *what was assessed*, never about what was achieved.
Any outward-facing statement either enumerates what was excluded or says something weaker than
"verified at level N".

---

## Deployment-time controls in software nobody has deployed

A large share of an application standard's operational requirements are about a running system.
Suppose your artifact is a beta with zero running instances: nobody has deployed it, nobody is
operating it. Two dishonest shortcuts are then available, and both are tempting.

**The first is to score it satisfied**, because the recommended deployment would satisfy it. That
assesses a hypothetical operator, not the software.

**The second is to score it `na`**, because there is no deployment. That quietly erases a real
requirement.

The rule, stated generally:

> Assess the artifact **as it ships**, under one explicitly declared reference posture. Score the
> shipped default. A control the software provides but leaves off is `partial`. A control whose
> subject is the host, network, or organization is `na` **with a written rationale and a stated
> deployment requirement**, so the obligation lands somewhere instead of evaporating.

**Zero deployments changes exactly two things, and neither is the bar.** It removes **false
urgency**: there is no exposed instance to panic about. It removes **vacuous migration cost**: there
is no installed base to migrate, so "we cannot change that now" is not available as a reason.

It **never** lowers the bar on a control, and it never converts a missing control into a
non-applicable one.

### Correct the tense of the impact sentence, never the score

Stated as an operation: **non-deployment is a correction to the tense of a cell's impact sentence,
and to nothing else.** A failing control stays failing, at the same severity. Write *"would expose X
on first deployment"*, never *"X is exposed"*.

That is not a softening. It is accuracy in both directions. The record is read as authoritative, and
a cell asserting a live exposure that does not exist is itself a false premise -- the same defect the
standard warns about when a compensating control rests on one.

Two guards keep it from becoming a dodge.

**It cuts one way only.** It removes false urgency and vacuous migration cost. It never downgrades a
finding, never justifies shipping a control off by default, never excuses skipping a gate. Drafters
will attempt all three; reverse each and record the reversal on the cell so the next pass does not
re-attempt it.

**It raises the bar rather than lowering it.** With nothing deployed, a breaking change costs
**zero**. So the most common justification for leaving a control weak -- "we cannot change this, it
would break existing installs" -- evaporates entirely. Non-deployment is the reason there is still
time to get it right, not a reason to defer.

---

## Evidence: an anchor a machine can re-check

"Implemented in the auth module" is not evidence. Neither is an evidence field that says "the system
enforces X" -- that is the requirement with the subject swapped. It is fluent, on-topic, and contains
nothing anyone can check. **If the evidence field could have been written without opening the code,
reject it.**

An **as-of commit is necessary and nowhere near sufficient**. It records what was read; it says
nothing about whether that has since changed, and it decays silently from the moment it is stamped.

Require every non-`unverified` cell to carry at least one anchor of a checkable shape:

| Anchor kind | Shape | Check |
|---|---|---|
| **Presence** | `path` + `line` + an **expected token that must occur exactly once** in the file, resolving within a window around that line | The token still resolves, exactly once, inside the window |
| **Absence** | a `pattern` that must return nothing, **plus a `positive_control` pattern that must still match**, **plus a stated reintroduction** the pattern is required to match | Negative returns nothing, positive still matches, and the reintroduction still trips the pattern |

### Anchor to a token, not to a line number

Line-numbered evidence is precise on the day it is written. Every edit above it shifts the line, the
whole anchor set thrashes, and reviewers learn to ignore anchor failures. That is strictly worse than
having no anchors at all. Path plus line plus token tolerates ordinary edits and fails on the ones
that matter.

**Exactly once** is doing real work in that table. A token that occurs several times can resolve
against the wrong occurrence after a refactor and pass forever.

An anchor that no longer resolves **invalidates the cell's verdict**, not just the pointer. Run the
check on every commit, wire it fail-closed, and **re-resolve the whole set against current mainline
on a schedule, not on demand**. On demand means the set is only ever re-checked by someone who
already suspects something.

### What only shows up once anchors are in use

**Drift is the gate working, not a defect.** The correct response to a broken anchor is to
**re-anchor by content**: find where the thing the cell actually graded now lives, and re-read the
surrounding lines. **Never nearest-match.** Re-pointing at whatever token happens to sit closest to
the old line is how a citation ends up describing code the cell never assessed.

**An anchor that must borrow an unrelated neighbour to be unique is fragile by construction.**
Suppose the on-topic token is not unique, so you reach for a nearby unrelated string to disambiguate.
An edit to code the cell does not grade then breaks the citation, and a broken citation invites
exactly the nearest-match re-pointing above. Prefer a token that is unique *and* on-topic.

If no such token exists, that is a signal about the cell, not about the anchor format: the mechanism
it claims to cite may not be as identifiable as the verdict assumes.

**A freshness gap the stamp cannot close.** A cell can be entirely honest about what was read and
silent about how *old* that reading already was, because nothing re-ran the check between the reading
and the signature. Surface "this reading is N commits behind mainline" in the rendered view, so
staleness is visible without anyone having to ask.

### Purpose-written tests count; a scanner alone does not

AI-assisted assessment drifts toward two poles: pasting a scanner's output, or asserting a control
works from having read it. The first is explicitly called insufficient by ASVS's own evidence
guidance; the second is unfalsifiable.

Prefer evidence that is **executable and specific to the requirement**: a test written to demonstrate
the verb, a check that the control *refuses* when its precondition is absent, an anchor pinned to the
line that does the refusing.

Automation is not the problem -- "testable using automation" is not the same as "ran a generic tool".
Where a control's behavior is claimed, **execute it** rather than describing it.

### An absence claim without a live positive control is void

Half of security verification is proving something is *not* there: no plaintext logging, no dangerous
call, no bypass path. A search that returns nothing is the most convincing artifact in the whole
record -- and a search naming a token that never existed also returns nothing. **The two outputs are
byte-identical.**

This fires constantly in agent work for a structural reason: the agent generates the search pattern
and the conclusion in the same breath, from the same guess about naming. A wrong guess produces a
clean result and a confident paragraph, several times in one session, with no signal anywhere.

So every absence claim ships as a **pair**: the pattern that must return nothing, and a positive
control of the same class that must still match something. If the positive control goes quiet, the
absence claim is void regardless of what the negative pattern returned.

**This repository has a worked example of the same principle applied to guardrails.**
[`bin/ccx-doctor.ps1`](https://github.com/wshallwshall/claude-multisession/blob/main/bin/ccx-doctor.ps1) does not ask whether a control is installed. It fires
crafted input at the *installed* copy and **requires it to refuse**. It also pairs every attack with
a negative control -- an ordinary action the same control must **allow** -- because a script that
refuses everything is not a working guard either.

It prints what it scanned on every run, and reports a check that could not run as `??` rather than
letting a skip read as a pass. That is the exact posture an assessment needs: *before you trust a
gate, make it fail on purpose, and prove it can see the class of thing it claims to have ruled out.*

### Confirm the instrument can represent the claim

A check that comes back clean is only evidence if a false version of the claim could have turned it
red.

If your pinned artifact holds requirement IDs, text, and levels, it holds **no chapter prose** -- no
scoping discussion, no assessment guidance, no definitions. A claim about what the standard says
*outside* a requirement's own text is therefore structurally uncheckable against it, and every check
returns clean forever. A false claim about a standard's own scoping rules can pass several
independent reviewers this way: each one verified, and each verification was vacuous.

Before running a check, **name the question and name what the instrument returns, and confirm they
are the same sentence.** To cite the standard's prose, fetch the chapter at the pinned tag and quote
it verbatim -- never from memory, never from an earlier assessment, never from another agent's
summary.

This is the same shape as several classic tooling traps: a diff on a staged file, an ancestry check
under squash-merge, an exit code read after a pipe. The tool answers a real question. It is not your
question.

**Assume the instrument is lying and make it prove otherwise.** Four surfaced inside a single day of
this work:

- a preview command that skipped the very guard it was previewing, and reported success where the real
  operation refused;
- a case-sensitive search that "proved" an amendment had not landed when it had;
- an exit code swallowed by a pipe;
- a scanner that printed detector counts but no scanned-file count, so a run that scanned **nothing**
  was byte-identical to a clean one.

Hence the two standing habits: **make every check print what it scanned**, and **make it fail on
purpose before you believe a pass**.

---

## Never score against a paraphrase

An agent reads the control ID and a one-line summary -- from an internal scorecard, a spreadsheet, or
an earlier assessment -- and then reasons about the code from that. It feels exactly like
verification: code was read, a verdict was written, a citation exists. But the verb being tested is a
**restatement**, and restatements drift toward what the project already does.

Verdicts derived this way survive multiple assessment cycles, because every later pass inherits the
same paraphrase. The failure compounds in a second way too. A paraphrase can outlive the requirement
it paraphrased, so a cell can be carefully scored against a requirement the current standard no
longer contains.

**Before judging a cell, quote the requirement's own description text out of the pinned corpus into
the cell, and reason only from that quoted verb.** If the cell does not contain the requirement's
words, it has not been assessed. Treat every verdict inherited from a pass that predates the pinned
corpus as `unverified` rather than as a starting point.

### The adjacent mechanism is the most expensive kind of wrong

A cell gets scored against a *neighbouring* requirement's verb -- same chapter, similar words,
genuinely implemented in the codebase. Every later reviewer then checks the evidence against the
mechanism rather than against the requirement, and it survives pass after pass.

Read the requirement's **subject and verb** against the cell's mechanism as the very first check,
before opening any code. Scoping errors hide from evidence review because the evidence is real.

---

## Pin the corpus, and stamp the version on every number

Standards repositories publish a rolling "latest" release whose asset filenames are identical to the
tagged release's, and the development branch carries the same names again. An unpinned fetch silently
moves versions with no error anywhere.

That matters more than it sounds, because **requirement IDs are not stable across major versions**.
The same dotted ID can name an entirely different topic in two editions -- in ASVS, a bare `1.2.5` is
*Architecture* in 4.0.3 and *Encoding and Sanitization* in 5.0.0. A corpus that shifts underneath you
re-points every ID in the scorecard at once.

| Do | Why |
|---|---|
| Fetch the **official tagged release asset**, not a branch | A branch and a rolling release publish identical filenames |
| Record its **cryptographic digest**, and recompute it on every verification run | A mismatch fails the gate and forces re-verification before any verdict is trusted |
| Record the standard's **version in the scorecard itself** | The record says what it was scored against |
| **Print the version beside any total** | A denominator change surfaces as a version change instead of as apparent progress |
| Reference requirements **version-prefixed**, not bare | `v5.0.0-1.2.5` means something; `1.2.5` does not |

---

## A score is a moving target

A scorecard with no as-of commit is undated evidence. And, as the anchor section says, an as-of
commit is **necessary and nowhere near sufficient**: it records when the reading happened, not
whether what was read has since changed.

Two independent causes keep the score moving, and only one of them involves anybody doing assessment
work:

1. **Cells get remediated.** Someone builds the control or turns it on by default. This is the cause
   everyone expects.
2. **Ordinary code changes silently invalidate cells that were already scored.** A refactor moves the
   line an anchor pointed at; a default flips; a call site moves behind a seam. The recorded verdict
   quietly stops describing the code, and **nothing about any total will tell you.**

**Cause 2 is the dangerous one**, because every reader is trained to interrogate a number that
*moved*. This class **hides in stillness**. Code changes, an evidence pointer drifts off what it was
pinned to, the recorded verdict stops being true -- and no bucket total moves at all.

Stability reads as "nothing to see". Several anchors across several cells can break in a single
ordinary refactor with zero visible signal.

**Make the anchors the change detector.** Because each anchor is a path plus a token that must still
resolve, a machine check on every commit tells you exactly which cells a change touched: the ones
whose anchors broke. Wire it fail-closed, run it in CI, and publish the drift-check result alongside
any total.

> **A stable count is not evidence of a stable posture unless the anchors were re-verified in the
> same pass.** Otherwise you are publishing the freshness of your last check, not the freshness of the
> software.

---

## How to read a movement in the numbers

Bucket totals are the most readable and most misread output of an assessment. They are what a reader
extracts, and every movement reads as the work getting better.

A fails count going from N to N-1 has **at least seven** possible causes, and exactly one of them
means the system got safer:

| The count moved because... | Did the posture improve? | What actually happened |
|---|---|---|
| A control was **built, or turned on by default** | **Yes** | The verb is now satisfied by shipped code |
| A cell was **re-verified against the requirement text** for the first time (`unverified` -> anything) | No | The survey advanced. A cell moving `unverified` -> `pass` is a *discovery*, or a paraphrase-based grade being corrected -- never an improvement |
| A **scope boundary was stated** (-> `na`) | No | The requirement left the denominator. Identical code, smaller question |
| A **rule was applied more carefully** (re-grade in either direction) | No | The assessment got more accurate. Some of these move *down* |
| **The standard moved** (a new release changes text, levels, or the requirement count) | No | The denominator changed. Zero code changed, zero assessment work happened -- and this is the cause most easily mistaken for progress |
| **The measurement was never run** | No -- and there is no measurement at all | A figure entered the record as an *unrun prediction written in the grammar of a measurement* |
| **The unit of counting changed** | No | Two counts of "the same thing" in different units diverge silently, and neither side notices the units differ |

Two of those need spelling out.

**The unrun prediction is the worst one**, because it is invisible to every downstream reader and to
CI alike. Somebody reasons "this will come out at N" and writes *"the check reports N"*. The sentence
is indistinguishable from a result: same shape, same confidence, same place in the document.

Nothing in the record marks it, and no gate can catch it, because a gate can only check figures that
claim a provenance.

> **The tell is grammatical.** A measured claim can name its command, its input tree and its exit
> code. A predicted one names a conclusion. Ask any figure which of those it can produce.

**The unit change** is quieter still: cells versus requirements, requirements versus chapters,
in-scope versus total. Both counts are correct. They are counts of different things, and the movement
between them is arithmetic, not progress.

**And the case people miss entirely: a count that does not move at all can hide real improvement and
real regression canceling out** -- or, worse, can hide the silent-invalidation class above, where
nothing moved because nothing was looking.

### Zero movement can be the most honest thing you report

The most honest outcome one full day of this work produced was **no movement at all** -- every verdict
identical at the end of it.

The pressure to avoid saying that is enormous, and the substitution is always available: report *the
instrument* getting greener as *the system* getting safer. "The checker went from many failures to
none" is a true sentence that says nothing whatsoever about security. It is also the sentence that
will suggest itself at the end of a long day of anchor repair.

**Say explicitly when nothing moved, and say why.** A number that did not move because the day's work
was record integrity is a **result**. It is not a null result, and reporting it as one teaches the
next reader that days like that were wasted.

**A count is not a posture.** Three obligations follow, and all three are cheap:

1. **Never report a total as a trend without naming which cause moved it.** "Fails went from N to
   N-1" is not a finding. "One cell was scoped out; no code changed" is.
2. **When a count improves, state what would have had to happen for it to mean an improvement, and
   whether that happened.** Same discipline as a negative control: a number that can only move one way
   is not measuring anything.
3. **Publish the pinned standard version and the drift-check result alongside any total.**

**Pre-announce that an honest sweep gets worse before it gets better.** As inherited grades resolve
into real verdicts, the aggregate degrades. That is the survey working, and it should be reported as
such rather than defended against. An assessment whose numbers only ever improve is not measuring the
software.

---

## Partitioning the work across agents

Splitting a large standard across parallel sessions feels like a scheduling problem, so it gets
solved with a chapter split and nothing else.

But the collision that actually costs you is not two agents editing the same row. It is **two agents
applying different unwritten rules** and producing verdicts that cannot be reconciled later, because
neither recorded which rule it applied. So partition on both axes.

**One integrator owns every write to the record.** This is the part that held up best under real
concurrency, and it is worth adopting before anything else here. Workers **read** the record and
produce **structured verdict files**; they never edit the record itself. A single large record that
every session wants to edit does not survive parallel work, whatever the merge tooling promises.

**Disjoint cells, enforced.** Give each session a set of cells nobody else holds, and make the claim
atomic rather than advisory-by-convention.

This repository's
[`scripts/coord/claim.ps1`](https://github.com/wshallwshall/claude-multisession/blob/main/scripts/coord/claim.ps1) is the working pattern. A claim is taken by
**exclusively creating** a file, which is an atomic filesystem operation, so two sessions cannot both
believe they hold the same key. Its free-text key form exists for exactly the case an assessment
generates: work that has no ticket number and that nobody thought to coordinate.

Claims do not expire, because an auto-expiring claim silently re-opens the race it exists to prevent.
`-List` reports each holder's **liveness** rather than the claim's age. The numbered form is
enforced at commit time by
[`scripts/hooks/claim_check.py`](https://github.com/wshallwshall/claude-multisession/blob/main/scripts/hooks/claim_check.py). The sequence-number analogue,
for allocating identifiers atomically instead of by grepping for the next free one, is
[`scripts/coord/alloc.ps1`](https://github.com/wshallwshall/claude-multisession/blob/main/scripts/coord/alloc.ps1).

**Identical inputs, written down.** Every session gets the same three things, and gets them as files
rather than as instructions in a prompt:

1. the **ordered decision procedure**,
2. the **positively-declared scope** and the single declared posture,
3. the **pinned requirement text**.

**Every verdict records which rule produced it**, plus reviewer and timestamp. Without that field, a
later disagreement is unresolvable and gets settled by whoever argues last.

### What cell partitioning does not buy you

Partitioning by cell prevents two sessions scoring the same cell **differently in the same pass**.
That is the collision everyone designs for, and it is not the one that bites.

**The one that bites: two sessions in different workstreams drafting replacements for the same cell
and disagreeing in opposite directions** -- one removing it, one keeping and rewriting it. Neither
session is scoring; neither holds a claim on the cell as a cell; each is doing legitimate work in its
own lane.

Both changes are individually correct. Applied together they are incoherent, and applied in sequence
the second silently overwrites the first's reasoning.

So partition by cell **and** run a **collision detector at integration** over the question *"which
cells does each pending change touch?"* -- across all pending changes, regardless of which workstream
produced them. The instance above was caught by a human reading at assembly time, which is not a
control; it is luck with a job title.

### Contested cells get parked, not forced

An unresolved cell feels like an unfinished job, so somebody picks the more defensible-sounding grade
to close it out -- and it flips on the next pass, and the one after. Each flip consumes a full
re-derivation and leaves the record looking unstable in a way that discredits the cells that *are*
settled.

Use the `needs-review` grade, record the disagreement itself, and let the owner close genuinely
contested cells **by decision**, marked do-not-re-derive with the reasoning preserved. Closure by
decision is not amnesia; repeated re-litigation of the same cell is not diligence.

---

## The review pass

**Do not start review at the cited code.** Review naturally starts there, and that is where a bad
cell is *strongest*: the code is real and relevant, so the cell survives.

Run a fixed, cheap pass in this order instead. Most bad cells die at step 2 or 3, before any code is
opened.

| # | Check | Kills |
|---|---|---|
| 1 | Does the cell **quote the requirement's own text**? | Paraphrase scoring |
| 2 | Does the cited mechanism's **verb and subject** match the requirement's? | The adjacent mechanism; reporting-vs-providing |
| 3 | Is the mechanism **on by default**, or does it refuse when its precondition is missing? | "It can be configured" |
| 4 | Open the anchor and **read the line**. Does the token resolve, and does that line support the claim? | Decorative citations |
| 5 | For any absence claim, **run its positive control first** | Vacuous greps |
| 6 | If `na`: is there a **written rationale about the verb's subject**, and is its strength graded? | `na` as a work-avoidance grade |
| 7 | Does the cell record **which rule fired**, and **who** set it **when**? | Unresolvable later disputes |

Budget roughly a minute per cell for this. It is the highest-yield activity in the entire exercise.

### Make the reviewer execute the citation, not read it

If you take one thing from the review pass, take this. It is the cheapest move available by a
distance, and the evidence for it is unambiguous:

> Every drafting pass produced confident, well-cited, partly-wrong output. Every reviewing pass that
> merely **read** that output agreed with it. Every reviewing pass that **ran** it found defects.

A read-only review shares the drafter's failure mode. What makes a bad cell persuasive on paper --
fluent prose, a real path, a plausible token -- is exactly what a reader checks against.

Running the anchor, running the grep, running the positive control is a different instrument
entirely. Step 4 and step 5 of the table above are the whole point of the table; the rest is triage
that gets you to them faster.

**Second cheapest: give each reviewer a distinct lens** rather than running N reviewers over the same
read. Three lenses that pull apart cleanly:

1. *Does the requirement's verb actually say this?* (text against cell)
2. *Do the artifacts resolve, and do they say what the cell claims?* (execute the citations)
3. *Is the prose over-claiming?* (absolutes, completeness, tense)

Reviewers given the same instruction converge on the same subset of defects and leave the rest
untouched no matter how many of them you add.

### Say the per-cell cost early

Per-cell verification at this rigour is expensive enough that naive extrapolation across a full
standard will shock whoever is paying for it. Say the number early.

Savings come from **batching by shared precondition**: one applicability investigation can serve an
entire section, and one posture question can settle a dozen cells.

They **never** come from cutting rigour on a cell, because an unearned verdict is the entire defect
the exercise exists to prevent. A cheaper assessment that produces unearned passes has not saved
anything; it has bought a document that reads like an assessment.

### The recurring agent failure modes, in one table

Ordered roughly by cost. The first is the most common defect of the lot.

| Failure mode | What it looks like | The forcing function |
|---|---|---|
| **The completeness claim** | "The only", "all", "never", "nothing" -- refutable by opening one file | Treat every absolute as an unproven claim by default; either prove it or write "at least" |
| **A control that does nothing, certified into the record** | A green, well-formed, structurally valid non-control | The checker must be shown to bite, not merely to match (below) |
| Over-claiming | A well-built, documented, opt-in control scored as satisfied | Pass requires a shipped default or a refusing gate |
| **A citation whose meaning inverted** | Token still present, still unique -- surrounding code now means the opposite | Re-anchor by content and re-read the surrounding lines; never mechanically |
| Restating the requirement as evidence | "The system enforces X" in the evidence field | Evidence must be a resolvable path + token |
| Citing a file that does not support the claim | Real code, right area, wrong verb | Verb-and-subject check before opening code |
| Scoring a paraphrase | Confident reasoning, requirement text never quoted | Quote the pinned text into the cell |
| Vacuous absence proof | A grep that returns nothing because the token never existed | Mandatory positive control |
| Vacuous verification | A green check against an instrument blind to the claim | Name the question and what the tool returns |
| Silent `na` creep | Sensible-sounding exclusions accumulating | Mandatory rationale on the verb's subject; graded strength |
| Inherited verdicts laundered into passes | A total that merges derived and inherited grades | `unverified` is its own bucket, excluded from pass |
| **Stale-by-landing** | A cell asserting a defect as current, closed by the author's own fix minutes later | Re-resolve on a schedule; cells outlive their findings faster than anyone expects |

Four of those repay a longer look.

**The completeness claim is the single most common defect, and the most dangerous**, precisely because
the paragraph around it is usually correct. "X is the only place that does Y" sits inside two hundred
words of accurate description. The reader's confidence in the paragraph transfers to the absolute.
One file, opened, refutes it -- and nobody opens the file, because the paragraph reads true.

**A control that does nothing** is the sharpest instance of the whole document's theme. An absence
claim was well-formed. It carried a positive control. It carried a stated reintroduction, and it
matched it. It passed.

And it was describing a mutation that a broad exception handler downstream would have swallowed whole,
changing no behavior at all. **The checker asserted that the pattern matched the mutation string. It
could not ask whether the mutation would bite.** Everything about the control was valid except the
thing it was for. When you design a reintroduction, ask not only "does the pattern match this?" but
"if this landed, would anything actually break?"

**An inverted citation** is what a mechanical re-anchor buys you. A fix lands; the cited token still
exists; it is still unique; the anchor resolves and the checker goes green. But the surrounding code
now means the opposite of what it meant, so the cell cites a line that sits safely behind the new
control -- as proof of a weakness. This is why re-anchoring is a content operation, not a
search-and-fix.

**Stale-by-landing** is the mildest and the most frequent: a cell asserts a defect as present, and the
author fixes it in the same session. The record is wrong within the hour. It is only cheap because it
is caught easily; it is worth naming because it makes the case for scheduled re-resolution better than
any argument about drift.

---

## Keeping the sweep scoped

A standards sweep touches everything, which makes it the repository's most attractive carrier for
unrelated improvements. The tree is already open, the tests are already running, and the change is
small and obviously good.

**Every change in the sweep names the requirement it closes.** A change that cannot name one does not
belong in the sweep -- file it and move on.

This is not bureaucratic. A "while I was in there" edit riding in a compliance batch is a change
nobody reviewed against any criterion at all, in the one batch a reviewer is least likely to read
line by line.

Cut the work into **phases with a stated character**, lowest-risk batch first. Split each batch's
write-up into two parts for the reader: **behavior changes that need operator action**, and **purely
additive changes** that need none. Anything that converts a warning into a refusal belongs in the
first part, with its escape hatch named explicitly.

### Two habits that keep the sweep's own artifacts honest

**Back every enumeration with a build-failing guard, or do not enumerate.** An inventory written to
satisfy a "document all X" requirement is complete the day it ships. A month later it is silently
wrong, and still reading as authoritative.

Enumerate from the code's own registry wherever one exists, so a new module with no row **fails the
build**. Where no registry exists, curate the set explicitly, check against the curated list, and
state exclusions as *enforced* exclusions rather than assumptions. Prefer "at least" phrasing anywhere
the guard does not reach.

Widen the guard's trigger set when a mechanism moves behind a seam: a check that looks for direct use
of known libraries goes blind the moment the work is delegated to an internal wrapper or a network
call.

**A forward commitment without a dated trigger and a named owner is a wish.** Migration plans,
algorithm-change plans, and review cadences all read as plans while containing no mechanism by which
anyone would notice they slipped.

Give each one a trigger condition, a dated review, and a named owner role. Then put the plan itself
under a test that fails when a row loses its date or its owner.

---

## Fixing the defect breaks the citation

A well-anchored record has a property nobody anticipates until it fires: **if a cell cites the
defective text as its evidence, remediating the defect invalidates the cell by construction.** The
better your anchors, the more reliably this happens. It is not a flaw in the anchoring; it is the
anchoring doing its job on the one change you actually wanted.

Inside one repository it is an ordinary same-commit edit. When the record and the code live in
**different repositories** it is a genuinely coupled change. Land either half alone and the checker
goes red against the other, for as long as the gap lasts.

The protocol that worked:

1. **Build both halves before landing either.** The code fix, and the cell's replacement text and
   replacement anchor.
2. **Verify against a working tree carrying the un-committed fix** -- not against the current mainline,
   which still contains the defect and will happily agree with the old cell.
3. **Run the published record against the changed tree and confirm it FAILS on the specific
   citation.** This is the step that is easy to skip and is the whole point: if it does *not* fail, the
   two halves were never coupled and you have invented a dependency between them. Find out which
   assumption was wrong before landing anything.
4. **Land the code, then the record**, gating the second push on "my change is the only thing pending"
   so the window cannot widen underneath you.

### Green is not the finish line

A mechanical re-anchor turns the checker green while leaving a false claim standing -- see the
inverted citation above. The bar is a **true residual**: the cell says something accurate about the
code as it now stands. No checker can see that, and none ever will. Green means the citations resolve;
it does not mean the sentences around them are true.

---

## What this method is not

A rigorous, well-anchored, machine-checked self-assessment starts to feel like a certification, and
downstream readers will treat it as one unless you tell them otherwise. Write the negative claims into
the method document itself:

- **Not a certification.** OWASP certifies nobody, and its assessment guidance is written for a
  third-party certifying organization producing a certification report. Applying it to an in-repo
  self-assessment is a defensible extension, not a mandate.
- **Not externally validated.** No independent review, penetration test, or dynamic scan has assessed
  the record.
- **Not a penetration test.** Source review answers a different question than attacking a running
  system.
- **Not a guarantee of correctness.** This method makes verdicts *consistent, derived, and
  drift-detecting*. **A wrong verdict recorded carefully is still wrong**, and adversarial
  re-verification is the only cure for that.

---

## Checklist

Before the first cell is scored:

- [ ] The standard's text is held locally, fetched from a **tagged release asset**, pinned by digest.
- [ ] The **verdict vocabulary** is published, with local extensions defined.
- [ ] The **ordered decision procedure** is written, first-match-wins.
- [ ] **Scope is declared positively**, and exactly **one posture** is described in prose.
- [ ] The **scorecard exists as data**, with `rule_fired`, `reviewed_by`, `reviewed_at` fields.
- [ ] The **anchor verifier** runs in CI and fails the build -- and you have watched it fail on purpose.
- [ ] Cell **claims are atomic**, so two sessions cannot score the same cell.
- [ ] **One integrator** owns every write to the record; workers emit structured verdict files.
- [ ] A **collision detector** runs at integration over "which cells does each pending change touch".

Before anything is published:

- [ ] Every count is **computed**, not typed -- and every figure can name its command, input tree and
      exit code, not just a conclusion.
- [ ] Derived numbers were **recomputed from source** by whoever wrote last, not delta-adjusted.
- [ ] Printed components are asserted to **sum to the printed total**.
- [ ] `unverified` is **reported separately** and excluded from any pass total, and the renderer states
      what the label means wherever it prints it.
- [ ] Every reviewer **executed** the citations rather than reading them, and reviewers had **distinct
      lenses**.
- [ ] Every absolute ("the only", "all", "never") was either proved or weakened to "at least".
- [ ] Impact sentences for undeployed software are in the **conditional tense**, with no score altered.
- [ ] **Every requirement is reported**, not exceptions only -- an exceptions-only report hides the
      denominator, and a reader cannot distinguish a thorough assessment from a shallow one.
- [ ] Every total carries the **pinned standard version** and the **drift-check result**.
- [ ] Any movement is reported **with its cause named** -- and if nothing moved, that is **stated as a
      result**, with the reason.
- [ ] Any level claim either **enumerates the exclusions** or says something weaker than "verified".
- [ ] The findings themselves are going **somewhere private**.

---

## See also

- [`docs/CASE-STUDY-drift-audit.md`](CASE-STUDY-drift-audit.md) -- the same reasoning applied to this
  repository's own controls: why an installed copy, not a source file, is the unit of audit, and why
  that document deliberately contains no status table either.
- [`bin/ccx-doctor.ps1`](https://github.com/wshallwshall/claude-multisession/blob/main/bin/ccx-doctor.ps1) -- prove the control can refuse; never infer that it is
  live.
- [`docs/COORDINATION.md`](COORDINATION.md) -- claims, locks, presence, and overlap for parallel
  sessions.
