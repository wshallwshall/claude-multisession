# AI-assisted development: keeping the result trustworthy

A standard for building software with an AI assistant. What can go wrong that looks like nothing
going wrong, and which control neutralises each one. How much rigor a given change actually needs.
And when to spend real money on an adversarial verification pass instead of a second opinion that is
worth almost nothing.

> **Meant to be worked with, not read straight through.** Most of this standard is a base for
> Claude Code, or another AI-assisted coding tool, to apply to your code, rather than
> prose to work through by hand.
>
> The fastest way in: give the tool the
> [markdown](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/AI-ASSISTED-DEVELOPMENT.md), ask it to
> **summarize the document against your repository**, and then ask it questions. What here
> already holds? What would have to change? What would each gap cost? That conversation is
> worth more than reading top to bottom, because the answers are about your code rather than
> about the document.
>
> Reading or circulating instead? [Word document](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/AI-ASSISTED-DEVELOPMENT.docx).
> [Every file, both formats](OVERVIEW.md#download-every-file).

## What you get

- **A rigor dial instead of an all-or-nothing process.** Two axes and a four-cell tier ladder
  resolve any change to exactly one tier, and the tier says which controls are mandatory and which
  you may skip. A one-line fix does not carry release-grade ceremony, in writing, which is what
  stops a heavy process from being ignored wholesale.
- **A classification you can do in seconds.** One question decides most changes, and the cheap
  answer errs strict rather than convenient.
- **Five named failure modes, each with a named control.** Every rule below traces to one of them,
  so you can audit your own practice with five questions -- and test any proposed new rule by asking
  which mode it neutralises. If the answer is none, it is decoration.
- **A hard line between a control and a wish.** A gate is a deterministic check with an exit code.
  The model never certifies its own output. That single rule is what most agent-assisted processes
  blur.
- **A defensible posture when there is no second reviewer.** Name the control you cannot meet, name
  the compensating set, name the event that ends the deviation -- instead of overclaiming review
  coverage or quietly having none.
- **Wording that survives a reviewer.** An approved-phrasing table with the overclaim beside each
  correct near-neighbour, so you can publish what your process buys without accidentally making a
  compliance claim.
- **An adversarial verification pass that is actually independent**, written as a technique rather
  than a product feature. Verifiers that did not produce the artefact, told to refute rather than
  review, given distinct lenses, reporting a counterexample and a command log. Plus the honest
  cases where the pass is pure waste.
- **Five habits that raise assistant output quality in the codebase you already have**, and the
  reason each one works.

## What this costs you, and where it does not apply

- **This page ships nothing.** No hooks, no prompts, no configuration, no workflow. It is a standard
  and a set of rules. Everything it references as a mechanism lives in another page of this site or
  in your own repository.
- **It confers no certification** on your product, your team, or anyone adopting your software, and
  it is not a substitute for an adopter's own assessment. It produces build-provenance evidence,
  which is an input to somebody else's review, never a replacement for it.
- **The tier resolver has no automatic detector.** It is a human-applied checklist. Its whole
  guarantee is that it fails closed and leaves a recorded reason someone can disagree with later.
- **Deliberately vendor-neutral.** No product names, mode names, command names, version thresholds,
  concurrency ceilings or per-run prices appear here. Those move faster than a documentation page
  can be revised, and every one of them was wrong within a release in the material this was drawn
  from. Where a limit matters to a design decision, the rule is to discover it with a pilot run
  rather than quote it.
- **No speed claim.** Nothing here is measured as a productivity gain, and the site's rule against
  claiming an unmeasured one applies to this document first. What the loop buys is auditability,
  continuity, reviewability and safety.
- **The adversarial pass is wrong for most work.** It earns its cost on coverage across a large
  surface. On a single-file change it adds latency and burn and improves nothing.
- **Solo and very small teams are a first-class case here, and it is a documented deviation, not a
  clean pass.** If you have real independent review available, several sections below are stricter
  than you need and one is unnecessary.

## How to adopt this

The smallest first step, then the rest in order. Each one is useful alone.

1. **Write the floor down and enforce the two halves of it that are mechanical.** No restricted data
   or secrets to the assistant, backed by a path deny-list *and* a fail-closed commit-time content
   scan, because a path rule cannot stop a paste. See
   [The leak gate](../LEAK-GATE.md) for a working scanner and its blind spots.
2. **Adopt the one-question classification.** You do not need the whole matrix on day one; you need
   the ratchet question and the habit of recording the answer.
3. **Make one gate deterministic and blocking**, and stop treating an assistant's review as a gate.
4. **Start writing a testable intent before prompting**, and review the returned diff against it.
5. **Add the tier matrix and the controls-as-dials table**, once the floor is real. Adopting the
   dials before the floor produces ceremony over a hole.
6. **Add the deviations register.** This is the step that keeps the standard honest as it grows
   stricter than your practice.
7. **Add the adversarial pass last**, and only for the task classes in *When the pass earns its
   cost*.

---

## 1. Five failure modes, and the control for each

Every rule in this document traces to one of these. That is what makes it a chain of reasoning
rather than a list of habits.

| Failure mode | What it looks like | The control |
|---|---|---|
| **Intent drift, with no auditable intent-to-code chain** | Generated code diverges from what was wanted, and there is no versioned spec to check it against | A testable written intent, approved before edits, reviewed against |
| **Context degradation** | Recall of the middle of a long or multi-session context decays; the assistant re-reads the same files and makes confidently wrong edits | Context isolation, fresh context per task, deliberate recovery |
| **Long-trajectory error accumulation** | Errors compound over an unconstrained run, and cost balloons alongside them | Decomposition into short trajectories that finish and return |
| **The fast-but-flawed paradox** | Review gets skipped because the output *looks* finished, producing people who can build but cannot debug | Deterministic gates that do not care how finished it looks |
| **Misplaced trust in output** | Self-assessed confidence rises faster than correctness | A human arbiter, and an adversarial check on whether the tests assert anything |

**Rule.** When someone proposes a new control, ask which of the five it neutralises. A control that
answers none of them is ceremony, and ceremony is what gets dropped first under pressure -- taking
the load-bearing rules beside it.

On the fifth mode specifically: assistance raises confidence faster than it raises correctness, and
this bites hardest exactly when the author reviews their own assisted output. That is the strongest
argument for keeping a review step you might otherwise drop for speed, and for the adversarial
verification pass in section 7. It is also why the site's rule *"Do not claim a speed or quality gain
you have not measured here"* in [CI and standards](../CI-AND-STANDARDS.md) applies to your own
impressions of the loop, not only to published figures.

---

## 2. The risk tier is the spine

Nothing here is always-on except a short floor. Everything else is a dial set by the tier.

### Classify in one question first

> **Does any code path in this change touch -- or protect -- regulated or otherwise restricted data
> in production, or can you not yet prove that it never will?**

If yes, or if you cannot prove it, the change is **T3**. Only on a confident no does the reach axis
become the tiebreaker between the lower tiers. Most day-to-day work in a system that carries
sensitive data resolves on this question alone; the reach axis matters mainly for code-only and
synthetic-only changes.

### The two axes

**Reach (blast radius).**

- **R0 Throwaway** -- a spike or one-off script; not on a shipping branch; no external consumer;
  a short single-session trajectory.
- **R1 Bounded module** -- one bounded module in a shipped repository, multi-session, decomposed,
  branch and review request.
- **R2 Cross-cutting or security seam** -- a change spanning several components, a schema or
  migration, or a security-relevant seam such as authentication, cryptography, or a boundary guard.
  Blast radius beyond one module. A team of a few people also reaches R2, but a solo maintainer
  reaches it by change shape alone and does not need to invent a team.
- **R3 Release others install** -- multiple teams, or a tagged release that adopters install onto
  their own systems.

*Revised.* The source material expressed this axis as **team size**, which leaves a solo maintainer
permanently in the lowest band no matter what the change touches. It is re-expressed here as blast
radius so that change shape, not headcount, sets the floor. The cell values in the matrix below were
carried over from the team-size version rather than re-derived against the new axis, so treat them
as directional: check the cells against your own work before adopting them unchanged.

**Sensitivity (the dominant ratchet).** This measures development-process data exposure *and*
production code-path sensitivity.

- **D0 None** -- no restricted data anywhere in scope; code-only assistant context; not on the
  sensitive production path.
- **D1 Synthetic in development, sensitive path in production** -- development and test use
  synthetic data only, and the production code path carries restricted data.
- **D2 The code is itself a protective control** -- encryption at rest, authentication and
  authorisation, the audit log, a redaction routine, an exposure guard. A failure here is a direct
  exposure.
- **D3 The deployed system carries restricted data** in production.

> **The sensitivity axis is about the production code path, never about restricted data on a
> development machine.** Development and test are synthetic, always, at every tier. A high
> sensitivity rating never licenses real restricted data into a prompt, a fixture, a transcript or a
> memory file.

### The matrix

Each cell resolves to exactly one tier: **T0 Exploratory**, **T1 Guarded**, **T2 Governed**,
**T3 Regulated release**.

| Reach (down) / Sensitivity (across) | **D0 none** | **D1 synthetic / sensitive path** | **D2 protective control** | **D3 restricted at runtime** |
|---|---|---|---|---|
| **R0 throwaway** | T0 | T2 | T3 | T3 |
| **R1 bounded module** | T1 | T2 | T3 | T3 |
| **R2 cross-cutting** | T2 | T2 | T3 | T3 |
| **R3 release** | T3 | T3 | T3 | T3 |

The two axes are not symmetric, and that is deliberate. **D2 and D3 force at least T3 regardless of
reach; D1 floors at T2.** Reach only scales the lower-sensitivity cells. Reading the matrix as a
lattice join guarantees monotonicity: more reach *or* more sensitivity is stricter, never laxer, so
no cell can accidentally be more permissive than a cell it dominates.

### The resolver: clamp to strictest, fail closed

Three ordered rules.

1. **The sensitivity ratchet dominates.** Touches or protects restricted data, so at least T3. Reach
   never clamps this down.
2. **Reach sets the floor** among the remaining cells.
3. **Fail closed.** When either axis is unknown or unresolvable -- a new repository, an undecided
   data flow, a "might touch it later" -- or when the change touches a production or
   network-exposed path, clamp **up** to the strictest applicable tier.

**Rule.** Every resolution emits a **recorded one-line reason** carried as a trailer on the change
request, naming both axis values, the resolved tier, and why. Anything that resolves without a
recorded reason has not been classified; it has been assumed. A reader six months later can then
disagree with the tier that was claimed, instead of guessing what rigor was intended.

Worked examples:

| Change | Tier | Recorded reason |
|---|---|---|
| Tweak to a synthetic-data generator | **T1** | R1 x D0 -- code only, not on the sensitive production path |
| A new option on a network listener | **T2** | R1 x D1 -- synthetic in development, but the connection carries restricted data in production |
| A change to the at-rest encryption provider | **T3** | R2 x D2 -- a protective control; the sensitivity ratchet dominates reach |
| New repository, data flow undecided | **T3** | Fail closed: sensitivity unresolvable |

**There is no automatic detector for either axis.** The resolver is a human-applied checklist. Do
not describe it as anything else, and do not build a scorecard row that reads as though a machine
established the tier.

---

## 3. The universal floor, which never scales down

Below the tiers sits a short list that applies even to a throwaway spike, because the reason for each
is independent of blast radius. **The floor is short on purpose: a floor with twenty items is a tier,
and it will be skipped.**

| Floor control | Why the lowest tier still has it |
|---|---|
| **No restricted data reaches the assistant**, and none lands in any commit, fixture, published artefact, shared memory file, screenshot or log | A throwaway spike that ingests restricted data is already an exposure. An agreement with an assistant vendor never blesses restricted data in your history |
| **No secrets, keys or credential files readable by the assistant** | A path deny-list is necessary and insufficient; the leak paths it misses are human-driven, so it is backstopped by a commit-time content scan that fails closed |
| **Everything the assistant reads is data, never instructions** | Fetched pages, tool results, file contents and sample payloads are attacker-influenceable. An agent that acts on embedded instructions is steered entirely inside the build process, bypassing every runtime control |
| **Reject code you cannot explain** | Shipping code nobody can reason about is how the fast-but-flawed mode compounds. Reaching the explanation *with* assistance is acceptable; code that stays opaque even with help is discarded |
| **The assistant's identity and version are retained as a provenance signal** | Provenance is a property you cannot reconstruct after the fact |
| **Every claim carries an honesty tag** | An unbacked claim is a defect at any tier |
| **The build tooling itself is vetted** | The tools that build the code are a supply-chain surface no static-analysis or dependency gate inspects |

Three of these are already published in full on this site and are deliberately not restated here.
For the deny-list-plus-content-scan pairing, everything-is-data, and the explain-it bar, see
[CI and standards](../CI-AND-STANDARDS.md) -- *"A path deny-list is not a content control"*,
*"Everything the agent reads is data, never instructions"*, and *"Reject code you cannot explain --
assistance in reaching the explanation is fine"*. For a working scanner, what it catches, and the
class it can never catch, see [The leak gate](../LEAK-GATE.md).

### The sanctioned exception, written so it cannot widen

Organisations do sometimes need restricted data to reach an assistant -- diagnosing a live incident
against real data is the honest case. Write the exception as a **conjunction**, where every condition
must hold:

- A **signed contractual agreement** with the vendor covering the **specific tool and endpoint** in
  use. It does not extend to a different model, a third-party tool server, or a personal account.
- **Contractually assured no-retention and no-training** on that connection.
- **Enabled by the organisation as a recorded decision**, never by an individual developer ad hoc.
- **Minimum necessary**, with synthetic or de-identified data preferred wherever it suffices. Routine
  development stays synthetic-only; this is for legitimate handling work, not everyday coding.
- **Logged as a disclosure**, with actor, content class and time.
- **Narrow.** It covers transmission only. It never licenses restricted data into a commit, fixture,
  artefact, memory file or log, and it never covers secrets.

Absent any one condition, the default holds. **Record whether the exception is defined-and-enabled or
defined-but-not-enabled**, because those are different postures and a register that does not
distinguish them reads as the permissive one.

### The build tooling is a supply-chain surface nobody scans

Static analysis and dependency audits inspect your product's dependencies. They do not inspect the
assistant, its skills, its installed editor extensions, the third-party tool servers it is connected
to, or an agent framework wrapping it -- all of which run with the developer's privileges and can
read the repository.

**Rule.** Pin and verify the assistant version; vet every skill, tool-server connection, extension
and agent framework before first use; prefer official distribution sources; record what is in use so
the set is auditable. Treat a change to that set as a change to the build environment, with the same
scrutiny as a dependency bump.

**Two distinct risks get conflated here, and only one of them is scannable.** A third-party tool
server is an arbitrary process that can read repository content and receives whatever the agent sends
it. Default-deny it above the lowest tiers. Where one is used, vet it, pin it, record it, send it
nothing restricted, and treat everything it returns as untrusted data. Separately, a live search or
fetch is **outbound egress in its own right** -- no restricted value, credential or identifying
string belongs in a query or a tool argument.

The asymmetry is the part worth internalising: **a commit-time content scanner catches a forbidden
string that lands in a commit, but it is not a live interceptor of an outbound query.** Nothing
mechanical stands between the agent and that channel. The discipline there is on the human, and your
documentation must say so rather than letting a green scanner imply coverage it does not have.

---

## 4. Controls as dials

Six control families, cumulative left to right: a cell inherits everything to its left. This table is
the standard; the sections after it are the footnotes.

| Control family | **T0 Exploratory** | **T1 Guarded** | **T2 Governed** | **T3 Regulated release** |
|---|---|---|---|---|
| **Spec and plan rigor** | Inline intent in the prompt | Written, testable intent, approved before any edit | Plus a durable decision record for any hard-to-reverse decision, written before the build, with a threat-model note | Plus intent-to-test traceability: each change's test names the requirement or decision it verifies |
| **Context isolation** | Single session | Curated project instruction file, fresh context per task, explicit decomposition | Plus one working tree per parallel session, single-writer shared memory, default-deny egress | Same, mandatory; committed context and memory files never carry restricted data or secrets |
| **Verification gates** | Advisory | The **full local gate must pass**, new behaviour gets a test, verify-before-add for any new dependency | Plus **blocking** static analysis, dependency audit and secret scanning in the pipeline, and an assistant-run review that a human arbitrates -- advisory, never a gate | Plus project-specific sink-aware rules, no unresolved findings, and a release gate |
| **Human review depth** | Author self-review | Self-review plus plan approval; the gates are the compensating second reviewer | Plus assistant-run review of the diff, and a second human for consequential changes where one exists | Plus a qualified human must approve **and** be able to explain every change. No merge on the assistant's own assurance |
| **Control parity** | Apply the control where you add it | Plus enumerate sibling paths when adding or changing a control, and cover them or record the gap | Plus one deterministic parity check over all instances where feasible | An asymmetric security control is a release-gate finding, not an accepted default |
| **Provenance** | None required | One coherent layer per commit; assistant identity and version recorded | Plus a link to the decision record and the approved plan | Plus a claims-register entry, and an assessment of assistant-authored code as third-party-equivalent where a regime requires it |
| **Forbidden** | *The floor, at every tier* | Plus: merging an unreviewed diff onto a shipping branch; adding a suggested dependency without verifying it exists, is reputable, and is the intended package | Plus: merging code you cannot explain even with help; skipping a blocking gate; self-certifying security by prompting; routing restricted data across a tool-server or egress boundary | Plus: an irreversible decision with no decision record; production exposure without the release gate satisfied or a dated, signed risk acceptance |

> **The non-negotiable rule of the gate row.** A gate is a **deterministic check with an exit code**
> -- a hook, a deny-list, a blocking pipeline job, a validate-and-dry-run command. It is never an
> instruction to the model to be careful. Prompt-based optimisation for security or maintainability
> is unstable and must not be relied on. **The model must not self-certify security or
> maintainability by prompting alone**, an assistant-run review is advisory input a human arbitrates,
> and no change merges on the assistant's own assurance that it is safe.

[CI and standards](../CI-AND-STANDARDS.md) owns where to place each gate, how to keep a local run
and the pipeline agreeing, and how to prove a green gate can actually fail. In particular:

- *"A green local run is not a green pipeline"*
- *"Scoped-green is not the gate"*
- *"A check that cannot fail is not a control"*
- *"Ship the guard the same day as the rule"*

Do not build a second copy of those rules beside this table.

---

## 5. Instructions an agent actually follows

The assistant is only as good as the context it can read. Three of the four things that most improve
output are things you write, not things you prompt.

### The project instruction file is a maintained artefact

The always-loaded instruction file is the anchor for every session. Treat it as an artefact under
maintenance rather than a scratchpad: **when the code stops matching it, the document is the thing
that is wrong.** A stale anchor is worse than none, because it is confidently loaded into every
session.

### Quote the invariant, do not gesture at it

**Rule.** Quote the real invariant lines the change must not break directly into the prompt, rather
than referring to them. The durable source of truth is the text, and a paraphrase of an invariant is
where drift starts.

### Write a testable intent before prompting

Name the files and seams to be touched, the test to be added, the invariants that must not break, and
the tier. Then review the returned diff **against that plan**; divergence is a review finding, not a
detail. The site owns the plan-then-diff rule in
[CI and standards](../CI-AND-STANDARDS.md) *"Approve a plan first, then review the diff against the
plan"*.

### Memory holds facts, never values

Persistent cross-session memory is for decisions, maps and conventions. Never restricted values,
never credentials. It also lives outside the repository in most setups, which means it is outside
every content gate you installed -- see [Coordination](../COORDINATION.md) for the single-writer rule
when several sessions share it.

### Compaction is a choice about what to keep

When a long session is compacted, aim the summary at **interface shape and decisions**, not at
narrative. That is what the next stretch of work needs, and it is exactly what a generic summary
loses first.

### What actually drives output quality across languages

Four properties determine how well an assistant performs in a given language:

| Property | Why it moves the result |
|---|---|
| **Corpus volume** | The volume of that language in public training material. More of it means fewer invented patterns |
| **Syntactic clarity** | Readable or rigidly formatted languages leave less ambiguity to hallucinate into |
| **Type strictness** | Declared types hand the model more of the intent, and reduce logical errors rather than only syntax errors |
| **A dominant style convention** | One prevailing formatter or style guide makes the training corpus itself more uniform, so the output is more consistent |

*Revised.* The material this came from ranked named languages against a leaderboard snapshot. That
ranking is dropped: it was a dated snapshot of a moving measurement, and a per-language rating is
stale within a release cycle. The four properties are mechanisms rather than a snapshot, and they are
the part that transfers.

The practical consequence is not a language choice -- most teams cannot change theirs -- but a set of
habits that raise output in any language:

- Keep a project context file stating architecture, conventions and constraints.
- Use declared types and docstrings; the model reads them as in-file documentation.
- Turn on the strictest type checking your toolchain offers.
- Run the formatter and linter **before** prompting, not only after.
- In a thin-corpus language or an in-house domain-specific language, treat generated code as a draft
  and budget extra review.

**The load-bearing sentence:** structure and documentation matter as much as language choice. A
well-organised codebase with types, docstrings and a context file outperforms a poorly structured one
in the same language.

### Recovering from context degradation

Symptom, then action:

| Symptom | Action |
|---|---|
| Repeating itself, re-reading the same files, confidently wrong edits | Clear the context and restart with a sharper prompt that incorporates what was learned |
| A long session approaching its limit | Compact, aiming the summary at interface shape and decisions |
| Always | Fresh context per task; keep context utilisation low; decompose into short trajectories |

The threshold for taking manual control back, and the reason grinding in a polluted context is the
expensive failure rather than a bad suggestion, are in
[CI and standards](../CI-AND-STANDARDS.md) *"Know when to take manual control back"*.
Session-level hygiene -- one logical task per session, one working tree per session, one dependency
environment per tree -- is in [Tips and tricks](../TIPS-AND-TRICKS.md) section 2.

---

## 6. Provenance, review, and saying what you actually have

### What the agent decides, and what you decide

Owned by [CI and standards](../CI-AND-STANDARDS.md) *"What the agent decides, and what you decide"*,
in a two-column table: the agent commits; you push, open, merge, release, delete and install. Nothing
about that split is restated here. The one addition this standard makes is that **the tier is part of
the plan you approve**, not something derived afterwards to justify the review depth you happened to
apply.

### Control parity is a review gate

An assistant implements a control exactly where it was prompted and misses its siblings. Make
enumerating them a review step rather than a hope, and prefer one deterministic check over all
instances to a recurring manual sweep. Full rule and the audit finding behind it:
[CI and standards](../CI-AND-STANDARDS.md) *"Enumerate sibling paths for every control"*.

### Provenance: record it, and count it before you cite it

Recording the assistant's identity and version is worth doing. The usual mechanism is a per-commit
trailer naming the assistant as a co-author. Citing that trailer as a **built control** is a
different claim, and it is the one that failed.

*Revised.* The trailer was published as a built control and as part of a retained evidence set.
Measured in one repository's own history, adoption was **zero**: many tracked files instructed that
the trailer be omitted, and a required merge check rejected it outright, because a trailer co-author
read as an unsigned contributor and turned that check red. The blocker was structural, not cultural.

**Rule.** Do not present a convention-only provenance trailer as a built control or as retained
evidence. Count it in the actual history first. If the count is zero, record it as
**designed-and-blocked**, name the structural blocker, and add a drift test that fails if the claim
is reinstated while the practice contradicts it. Before enforcing any trailer, check its form against
the merge gates that will see it; then enforce it with a commit-time hook **plus** an independent
pipeline backstop, so a local bypass does not defeat it. The general form of this --
[CI and standards](../CI-AND-STANDARDS.md) *"Measure the adoption of a convention before citing it as
evidence"* -- is on the site already; the two deltas above are the parts specific to a provenance
trailer.

Be equally precise about granularity. A commit trailer records provenance at **commit** granularity.
It does not mark which lines or hunks were assistant-authored. If a downstream process wants the
line-level distinction, that is a separate, unbuilt thing, and saying so costs nothing.

### When there is no second reviewer

Working alone, or with no reviewer available, is a real deviation from every mainstream review
standard. The honest response is to record it as one rather than to redefine the requirement.

- **The control that cannot be met:** independent human review of every change.
- **The compensating set that stands in for it:** blocking automated analysis and dependency audit
  that cannot be waived; an assistant-run review that a human arbitrates; branch protection with
  required checks; no direct pushes to the integration branch.
- **The wording constraint:** this is a **compensating control**, explicitly not an independent
  audit, and no published claim may imply otherwise.
- **The end condition:** a second maintainer joins.

The obligation that *is* achievable alone is concrete: the full gate green, the reviews run and
triaged, and every change explained-or-discarded -- where you engage with and stand behind the
explanation rather than rubber-stamping it. The obligation that is not achievable alone is
independent review, and it stays in the register as a deviation until it is.

Given that posture, the single highest-leverage control to build first is an adversarial check on
whether the tests assert anything. It earns that place because it is the only one that is independent
of the author's own confidence -- and the fifth failure mode says confidence is exactly what is
unreliable in the self-review case.

*Revised.* An earlier form of this made independent review a **precondition for production
exposure**. For software that others self-host, the producing project does not control the deployment
decision, and gating an adopter's rollout on an engagement you have not funded asserts authority you
do not have. The standard **records what has and has not been independently verified**; the adopting
organisation owns the decision to deploy.

### The deviations register

Every gap gets four fields. A deviation with no build trigger is a permanent excuse; a deviation with
no date cannot be aged.

| Field | What it holds |
|---|---|
| **Control not met, and the date accepted** | The requirement you do not currently satisfy, and when that was accepted |
| **Compensating controls** | What is actually in force instead, named specifically |
| **Build trigger** | The concrete event that forces the real control to be built -- a second reviewer joining, a first external audit, a regulated deployment, the first release someone else installs |
| **Design record** | A pointer to where the intended shape is written down |

Two rules travel with the register. **Only a dated, signed acceptance is governance** -- an unsigned
register is an un-accepted open gap wearing the costume of a decision, and a release gate that leans
on one is not a gate. And **do not publish the register's contents as a public inventory of which
controls are currently absent** if the software is security-relevant; keep the meta-rule public and
the instance internal.

### Claims and wording

Publish a two-column phrasing table, because the overclaims are systematic and each has a correct
near-neighbour.

| Use this | Not this |
|---|---|
| "Assistant-run code review as a **compensating control**" | "Reviewed", in a sense that implies an independent audit |
| "Plan **approved by a human** before implementation" | "**Autonomously** developed" |
| "Gates **enforce intent deterministically**" | "**Certified** secure" |
| "**Built with assistance** under this standard" | "Assistance **made development faster**" (unmeasured) |
| "Provenance recorded at **commit granularity**, by convention" | "**Verified secure by the model**" |

Keep a claims register holding the exact approved wording next to its evidence, and let nothing ship
that is not in it. The register mechanics, the honesty taxonomy behind it, and the aligned /
built-to / self-assessed vocabulary are all owned by
[CI and standards](../CI-AND-STANDARDS.md) *"Say which kind of claim you are making"* -- read that
before publishing anything from this document.

### The attestation posture

Say this once, structurally, near the top of whatever you publish -- not as a footnote disclaimer:

> Building under this standard produces **build-provenance evidence**. It does not confer compliance,
> certification, or fitness on the product, on the author, or on anyone adopting it, and it is not a
> substitute for an adopter's own risk assessment.

The positive form names its own scope: *the project self-attests that it builds under this standard
with the assistant governed as a tool -- explicitly not that the output is independently audited.*
Where you borrow discipline from a regime you are not subject to, say that it is adopted **by analogy
and voluntarily**, name the regime you are not subject to, and state that producing the artefacts
confers nothing.

---

## 7. The adversarial verification pass

### Why a second opinion from the same session is worth almost nothing

A single agent that writes an answer and is then asked to check it has a **structural** defect, not a
quality defect: the context that produced the answer is the context judging it, and it is biased
toward what it already decided was fine. More reasoning effort in the same context does not fix this,
because the bias is not a shortage of effort.

The fix has two parts, and both are necessary:

1. **Independence.** Hand verification to a separate agent that never saw the reasoning that produced
   the output. Keeping each verifier's task short enough that it finishes and returns also keeps its
   objective from blurring.
2. **Framing.** Tell the verifier to **refute**, not to review. A reviewer looks for defects in what
   is presented; an adversary assumes the conclusion is wrong and hunts for the counterexample that
   proves it.

This site has already measured the same effect from the other direction -- see *"The review pass"*
and *"Make the reviewer execute the citation, not read it"* in
[Running a large security-standard assessment with AI agents](../ASVS-ASSESSMENT.md).

### The shape that keeps a pass independent

Independence degrades unless it is designed in. Four rules.

- **Give the verifiers the artefact and the claim, not the author's framing.** No naming, no
  rationale, no summary of why it is right. The implementer's vocabulary contaminates the critic's
  judgment.
- **Give each verifier a distinct lens**, not the same brief repeated, so their failures are
  uncorrelated. For a code change: one hunts the correctness property most likely to be violated, one
  attacks structure and coupling, one attacks completeness and migration.
- **Fix an output contract before the run.** The strongest counterexample found, **the commands
  actually run**, and a proceed-or-hold verdict. A verdict without a counterexample and a command log
  is an opinion wearing a verdict's clothes.
- **Put a human gate after it.** The change does not advance on the panel's say-so. Scope every
  prompt explicitly -- name the files, forbid access to credentials and production data, require
  evidence before anything proceeds.

### Propose, judge, synthesise, critique

For a design decision rather than a patch, the two-lane pattern generalises to a panel:

- several independent proposals, each written from a declared lens
- each proposal scored by several adversarial judges, each with its own lens
- a synthesis pass
- then a **fresh** adversarial critique of the synthesis

Two rules make the cost worth paying.

**Score two separate things.** A quality score, and a **binary fatal-flaw verdict**. A fatal flaw
vetoes regardless of score, because an averaged score hides a disqualifying defect -- which is the
first failure mode of panel review.

**Do not treat the winner as the answer.** In the run this was drawn from, only one proposal was free
of fatal flaws, and the final design was that proposal's spine with specific ideas **grafted from
proposals that had lost**, with every fatal flaw explicitly resolved rather than averaged away.
Discarding the losers' good ideas is the second failure mode of panel review.

### Reading a split verdict

On a split, the useful output is **not a tally**. It is the strongest surviving objection. Carry it
forward and resolve it by name. Where a residual risk cannot be closed, document it honestly -- for
instance as no worse than the behaviour that already ships -- and make it visible rather than
claiming it closed. A residual risk that is named survives review; one that is quietly absorbed
resurfaces as an incident.

### Findings from a sweep are candidates, not findings

Anything an agent sweep surfaces is a candidate. Run each through independent confirmation before it
enters a register, a report or a fix queue, and expect a substantial fraction not to survive.

**Rule.** Report **candidate** and **confirmed** as separate numbers so the sweep's yield is visible,
and make the confirmation step adversarial in the same sense as the verification pass -- a confirmer
asked to agree will agree. The residual risk after confirmation is usually not a wrong finding; it is
a control implemented exactly where it was prompted and missing at its siblings, which is why control
parity is a review gate and not an afterthought.

### When the pass earns its cost, and when it is waste

| Run it when | Skip it when |
|---|---|
| **Coverage is the metric** -- a sweep over many independent sites where missing one is costly | **Single-file or single-seam scope** -- fixing one bug, writing one test, renaming a symbol |
| **The scale outgrows a single context** -- a large migration, a repository-wide refactor | **Interactive and iterative work** -- the human is already in the loop on every step |
| **The cost of a miss exceeds the compute cost** -- a hard-to-reverse architectural decision, a launch-readiness check | **The budget is tight** -- a single large sweep can consume a materially larger share of a usage allowance than a normal working day |

The reason it fails on small work is structural rather than economic: **fan-out earns its value from
coverage across a large surface, and a single-file task has no surface to fan out across.** The pass
adds latency and burn without improving the result. The corollary is that a targeted, scoped review of
a finished change is usually a better instrument than leaving a session-wide maximum-effort setting on.

### Cost posture and the stop rule

Treat a fan-out as **a permission granted for one hard task, not a quality setting left on**.

- **Pilot a scoped, read-only slice first** and watch the plan before approving any edits. Calibrate
  on a small case before committing the budget to the real one -- including discovering the
  concurrency ceiling yourself rather than quoting one.
- **Scope every prompt explicitly**, as above.
- **Stop when the lanes cycle without producing new findings.** Repeated exploration at that point is
  burn, not coverage. This is a stop condition you can observe from the run itself, rather than from a
  spend report afterwards.
- **Step back down as soon as the hard task is done.**

Deciding whether you can afford the run at all, and why a percentage without its account is
meaningless, is owned by [Usage awareness](../USAGE-AWARENESS.md).

### Put the plan in an artefact, not in the conversation

When a run spans many agents or many hours, the plan -- the dependency graph, the loops, the fan-out
-- should live in a written script or file that the run follows, not in the conversation that produced
it. A plan held in conversational context degrades with everything else in that context. A plan held
in an artefact is stable across the whole run and re-readable by every agent that joins it. The same
argument supports caching completed sub-results so a resumed run does not redo them.

If the fan-out is several *sessions* rather than several agents inside one session, the isolation and
hand-off mechanics are owned by [Worktrees](../WORKTREES.md) and
[Coordination](../COORDINATION.md), and the identifier-collision class that every other control is
blind to is owned by [Sequence allocation](../SEQUENCE-ALLOC.md).

---

## 8. In one table

| When | Rule |
|---|---|
| Proposing a control | Name which of the five failure modes it neutralises. None means decoration |
| Classifying a change | One question first: does any path touch or protect restricted data in production |
| Classifying a change | Sensitivity ratchets up and dominates reach; reach only scales the low-sensitivity cells |
| Classifying a change | Unknown, unresolvable, or production-facing: clamp up to the strictest tier |
| Classifying a change | Emit a recorded one-line reason, or it was assumed, not classified |
| Every tier | The floor never scales down, and it stays short enough to survive a prototype |
| Every tier | A path deny-list is necessary and insufficient; pair it with a fail-closed commit scan |
| Every tier | Vet the assistant, its skills, its extensions and its tool servers -- no product gate inspects them |
| Every tier | A commit-time scanner is not a live interceptor of an outbound query. That discipline is human |
| Gating | A gate is a deterministic check with an exit code. Never ask the model to be secure |
| Gating | An assistant-run review is advisory input a human arbitrates, never a gate |
| Writing prompts | Quote the real invariant lines; do not gesture at them |
| Writing prompts | Write a testable intent first, then review the diff against it |
| Context | Fresh context per task, short trajectories; compact toward interface shape and decisions |
| Context | The project instruction file is maintained. When code stops matching it, the doc is wrong |
| Provenance | Count a convention in the actual history before calling it a built control |
| Provenance | A commit trailer records commit granularity. Do not imply line-level authorship |
| Review | No second reviewer is a documented deviation with a named compensating set and an end condition |
| Review | Every deviation carries a date, compensating controls, a build trigger, and a design record |
| Claiming | Compensating control, not audit. Approved plan, not autonomous. Built with assistance, not faster |
| Claiming | Building under a standard confers no certification on you or on your adopters |
| Verifying | The context that wrote the answer cannot judge it. Independence is the mechanism |
| Verifying | Tell the verifier to refute, not to review, and give each one a distinct lens |
| Verifying | Require a counterexample and a command log. A bare verdict is an opinion |
| Verifying | Fatal flaw vetoes score; graft from the losers; on a split, carry the strongest objection forward |
| Verifying | Agent-surfaced findings are candidates. Report candidate and confirmed separately |
| Cost | Pilot a scoped read-only slice first; stop when lanes cycle without new findings; step back down |
| Cost | Skip the pass on single-file, interactive, or budget-constrained work -- there is no surface to cover |

---

## Adapting this to your project

**What you must change.**

- **The two axis definitions.** Reach and sensitivity are named generically here on purpose. Write
  the levels in your own domain's vocabulary, and make the sensitivity axis mean the thing your
  regulator, your customers or your risk register actually cares about.
- **The tier names, if they mislead.** Four tiers is enough; the labels are not load-bearing.
- **The contents of the verification-gate row.** Which analyses, which audits, which command -- those
  are yours. What is not yours to change is that they are deterministic and blocking.
- **The floor's first row.** "Restricted data" has to be defined for your context, concretely enough
  that someone can decide in seconds whether a payload qualifies.
- **The deviations register's contents.** Yours will differ. Keep the four fields.

**What you must not weaken.**

- **The gate definition.** The moment an assistant-run review counts as a gate, the whole structure is
  decorative. Advisory input a human arbitrates is the strongest form it may take.
- **The fail-closed resolver.** A resolver that resolves ambiguity downward is not a classifier, it is
  a permission slip.
- **The floor's independence from tier.** The reason each floor item exists is unrelated to blast
  radius, which is precisely why "it is only a prototype" is when they get broken.
- **The recorded reason.** A tier with no recorded reason is unreviewable, and an unreviewable
  classification is indistinguishable from no classification at all.
- **The wording table.** Softening one row of it is how a compensating control becomes an audit in
  the reader's mind, and nobody involved will notice the day it happens.
- **Independence in the verification pass.** A "second opinion" from the same context is the thing
  the pass exists to replace. If you cannot afford independence, run no pass and say so, rather than
  running a pass that cannot find anything.

**One structural note.** Where a control is already owned by another document, **point at the owner
and check only that it is present** -- do not restate the control. That is why several sections above
are three lines and a link. A standard that restates its neighbours grows two copies of every rule,
and the copy that drifts is always the one nobody is testing.

---

## Related

- [CI and standards](../CI-AND-STANDARDS.md) -- gates, receipts, claim honesty, the agent-versus-human
  split, dependency verification, and judging tests and metrics
- [The leak gate](../LEAK-GATE.md) -- a fail-closed content scanner, the three ways a scanner lies,
  and the class it can never see
- [Running a large security-standard assessment with AI agents](../ASVS-ASSESSMENT.md) -- verdict
  vocabularies, evidence anchors, and partitioning assessment work across agents
- [Tips and tricks](../TIPS-AND-TRICKS.md) -- session hygiene, writing a guardrail, and measuring
  whether it works
- [Coordination](../COORDINATION.md) and [Worktrees](../WORKTREES.md) -- isolation and hand-off when
  the fan-out is several sessions rather than several agents
- [Usage awareness](../USAGE-AWARENESS.md) -- deciding whether you can afford a run, honestly
