# Judging code quality, whoever or whatever wrote it

A rubric for answering one question about a body of code: **is this good, or is it filler that
looks finished?** It is written for a repository where much of the code was produced by Claude Code, or another AI-assisted coding tool
across parallel sessions, but nothing in it depends on who typed the lines. The rubric judges the
artifact.

> **This one is dense.** Reading it end to end works, and you will need to eventually -- it
> becomes your rubric once you adopt it. It is usually faster to hand the
> [markdown](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/CODE-QUALITY.md) to Claude Code, or
> another AI-assisted coding tool, and ask it to summarize this against your repository,
> rewrite a section in plainer terms, or answer what already holds here and what would have to
> change.
>
> Reading or circulating instead? [Word document](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/CODE-QUALITY.docx).
> [Every file, both formats](OVERVIEW.md#the-files).

---

## What you get

- **A scorecard you can run each release**, split into rows that are allowed to decide a verdict
  and rows that are only allowed to start a conversation. An argument about "is this good enough"
  then resolves against structure instead of against whoever quotes the largest number.
- **One sentence to point at** when somebody proposes a coverage floor or a complexity gate, plus
  the published evidence that makes it a defect rather than a matter of taste.
- **The bibliography and the hedge for each of those findings**, so a decision not to gate on a
  number survives review by someone who has read the underlying paper.
- **A map from each way machine-written code goes wrong to the control that neutralizes it**, with
  a tag naming which of your documents owns that control -- so adopting this adds gates rather than
  a second copy of rules you already enforce.
- **A placement rule for every gate**: which run in the local loop, which are pipeline-first, and
  the one condition under which that decision must be re-derived from scratch.
- **A review method that makes a large diff finite**: depth tiers, so the line-by-line read is
  aimed at the small fraction that earns it and every other file carries a named cheaper
  obligation instead of being either skipped in silence or read at ruinous cost.
- **A question set for the hardest review in any codebase** -- the seam where content of unknown
  provenance becomes running code -- including the two questions almost always missed.
- **The widely repeated figures about machine-written code that did not survive verification**,
  named so you can stop repeating them, and as a worked demonstration that this document's own
  filter has teeth.

---

## What this costs you, and where it does not apply

- **It confers no certification.** There is no badge, no pass mark, and no grade. A completed
  scorecard is an argued position with pointers, nothing more.
- **It supplies no thresholds.** The evidence validates that single metrics fail; it supplies no
  validated cutoff for a combined scorecard. Any number you use is one you set and must defend.
  See [There is no validated universal threshold](../CI-AND-STANDARDS.md#there-is-no-validated-universal-threshold).
- **It ships no configuration.** No workflow, no tool selection, no lint ruleset. Every gate named
  below is described by what it must prove, not by the product that proves it.
- **Three of the eleven rows are owned by a companion document** -- your security standard, your
  dependency standard, your test standard. This document checks that the control is present; it
  does not restate it. If you have no such companion, the rubric will tell you a row is missing and
  will not tell you how to build it.
- **The measurement layer costs pipeline minutes and produces advisory output nobody is obliged to
  act on.** Budget the attention, not only the runtime. An advisory job nobody reads is worse than
  absent, because the scorecard still counts it.
- **Several rows assume a pipeline that can block a merge.** Where merges cannot be blocked, Tier 1
  degrades from a control to a checklist, and the honest scorecard says so.
- **Figures come from two places, and the difference is marked at the point of use.** Every
  published-research figure carries an explicit **[external]** tag and its own limitation in the
  same sentence. The remaining figures were measured in one project's practice and are stated to
  justify a rule, never as constants you should expect to reproduce. Where a rule came from a
  specific failure, the failure is described without its setting.

---

## How to adopt this

1. **Score Tier 1 as a read-only audit, once.** Answer the six Tier 1 questions about your
   repository and write a pointer to the evidence for each. Anything you did not check is
   **unverified**, and unverified is not a pass. This takes an afternoon and is the whole minimum
   viable adoption.
2. **Close the cheapest Tier 1 gap.** Tier 1 carries the verdict, so a missing durable control
   outranks every measurement gate you could add instead.
3. **Add one Tier 2 gate, with a receipt.** Pick the one that answers a question you currently
   cannot answer. Make it print what it examined before you believe its green. See
   [Receipts: count what the check examined, never what it found](../CI-AND-STANDARDS.md#receipts-count-what-the-check-examined-never-what-it-found).
4. **Attack it with the failure class it was built to catch**, before you record it as built.
5. **Record your thresholds in your own appendix**, labeled project-set rather than
   evidence-certified, and revisit them as data accumulates.
6. **Re-run the scorecard each release.** The rows do not move; the answers do.

---

## The rubric: two tiers, weighted unequally

The structural scaffold is a recognized product-quality model rather than invented categories:
**[external]** ISO/IEC 25010:2023 decomposes maintainability into modularity, reusability,
analyzability, modifiability and testability -- in other words low coupling plus information hiding
-- which is a structural property and not a metric score. Tier 1 is that property enforced as
machine-checked architectural rules.

**Tier 1 -- durable controls. These carry the verdict.** Structural, machine-enforceable
properties where quality is hard to fake.

| # | Signal | What it asks | Gate type | Owner |
|---|---|---|---|---|
| 1 | Enforced architecture boundaries | Are module and layer rules machine-checked in the pipeline, rather than documented? | Deterministic | Here |
| 2 | Strict type checking | Is the strictest available mode on, with no blanket suppressions -- every suppression carrying its error code? | Deterministic | Here |
| 3 | Tests verify behavior | Do tests assert real values and failure paths, rather than mock choreography? | Deterministic | Your test standard; checked here |
| 4 | Dependency integrity | Is every dependency existence-verified, hash-locked, and is a new import audited? | Deterministic | Your dependency standard; pointer only |
| 5 | Security scanning plus a threat model | Are the scanners blocking, and is there a written threat model and a human review step? | Deterministic plus advisory | Your security standard; pointer only |
| 6 | Published-artifact integrity | Does a released package ship only intended content, gated before the irreversible upload? | Deterministic | Here |

Row 6 is the outbound direction of the supply chain and is distinct from row 4's inbound direction.
The rule and its failure shape are already published: see
[Package manifests are allowlists, not sweeps](../CI-AND-STANDARDS.md#package-manifests-are-allowlists-not-sweeps).
The case worth naming as an instance is that material a project treats as withheld can travel
inside a published distribution without anyone reviewing the packaging list.

**Tier 2 -- the measurement layer. Guidance and triage, never a gate on its own.** Each of these is
a weak or gameable predictor in isolation, so they inform review; they do not certify anything.

| # | Signal | What it asks | Gate type | Owner |
|---|---|---|---|---|
| 7 | Test-signal proof | Does mutation on changed code expose tests that assert little? | Advisory | Here |
| 8 | Coverage visibility | Is coverage reported on the changed lines, as guidance, never as a repository percentage gate? | Advisory | Here |
| 9 | Duplication and reuse | Is new copy-paste flagged on the diff, with justified parity whitelisted? | Advisory | Here |
| 10 | Lint breadth | Is a broad static-analysis ruleset enforced, from a clean baseline? | Deterministic | Here |
| 11 | Complexity triage | Are genuinely large units surfaced for a human to look at? | Advisory | Here |

**Rule.** A codebase is judged by the **composite**, never by any single row. Tier 1 decides;
Tier 2 starts conversations. A strong Tier 2 does not compensate for a missing Tier 1 row, and a
weak Tier 2 row is not a finding on its own.

### The anti-metric rule (hard)

**Do not certify quality -- or fail a build -- on any single one of:** line-coverage percentage,
lines of code, raw or vendor "cognitive" cyclomatic complexity, or static-analysis severity counts.
Each may be surfaced as advisory triage a human arbitrates; none may ever be the quality gate.

This is the quality-side analogue of *gates are deterministic checks, never ask the model to be
secure*: **a scoreboard is never the verdict.**

The evidence table behind this rule already lives on this site, with each row tagged [external]:
[Never gate on a single gameable number](../CI-AND-STANDARDS.md#never-gate-on-a-single-gameable-number).
So does the rule on judging tests:
[Judge tests by their assertions, not their presence or their coverage](../CI-AND-STANDARDS.md#judge-tests-by-their-assertions-not-their-presence-or-their-coverage).
The rule and its reasoning stay on that page. What follows is the bibliography behind it -- the part
you need when somebody who disagrees asks where a number came from -- with each claim restated only
far enough to attach its citation to it.

### Delivery-outcome metrics are a context caveat, not a signal

Keep change-failure rate, lead time and their siblings out of a code-quality rubric. They measure
delivery, not whether a given change is filler -- a different altitude from the artifact signals
above -- and the evidence for the machine-authorship link is weaker than for the metric-validity
findings. The actionable part is already covered by small batches and
[One coherent layer per commit](../CI-AND-STANDARDS.md#one-coherent-layer-per-commit). Record the
concern as a failure mode with a remedy; do not promote it to a peer signal.

The reason generalizes: **when someone proposes adding an outcome metric to an artifact rubric,
the objection is altitude, not distaste.**

---

## The evidence, and the hedge each citation must carry

Every row is **[external]**. Attach the limitation to the claim at the point of use, never in a
footnote a reader can skip.

| Claim | What the evidence says | Citation | The hedge that travels with it |
|---|---|---|---|
| Raw cyclomatic complexity is a weak defect predictor | Correlation with real bugs of about **0.06** (Kendall); "adds little if any" beyond executable-line counts | Chen, C. (2019). *An Empirical Investigation of Correlation between Code Complexity and Bugs.* arXiv:1912.01142 [cs.SE]. https://arxiv.org/abs/1912.01142 | Argues against a single-number gate, not against measuring. Complexity is still a useful local triage smell |
| Vendor "cognitive complexity" adds nothing | No incremental predictive value over traditional measures; the peer-reviewed evaluation concludes it "does not appear to fulfill the promise" | Lavazza, L., Abualkishik, A. Z., Liu, G., & Morasca, S. (2023). *An Empirical Evaluation of the "Cognitive Complexity" Measure as a Predictor of Code Understandability.* Journal of Systems and Software, 197, 111561. https://doi.org/10.1016/j.jss.2022.111561 | Replacing a cyclomatic gate with a cognitive one buys nothing. The finding is about predictive value, and says nothing about how often the measure is sold or adopted |
| Static-analysis severity counts are weak, inconsistent, sometimes inverted | Across 33 large projects and roughly 27,000 faults, flagged "dirty" classes were no more fault-prone than clean ones | Lenarduzzi, V., Saarimaki, N., & Taibi, D. (2020). *Some SonarQube issues have a significant but small effect on faults and changes: A large-scale empirical study.* Journal of Systems and Software, 170, 110750. https://arxiv.org/abs/1908.11590 | Effects are small and sometimes inverted. Useful as a cheap filter; not a quality score |
| Mutation score is a poor single number, but mutation testing is high-value guidance | Mostly a test-suite-size artifact as a linear proxy; top-decile suites catch **8 to 46 percent** more real faults | Papadakis, M., Shin, D., Yoo, S., & Bae, D.-H. (2018). *Are Mutation Scores Correlated with Real Fault Detection? A Large Scale Empirical Study on the Relationship Between Mutants and Real Faults.* ICSE 2018. https://doi.org/10.1145/3180155.3180183 | Read the survivors; never publish the score as a grade |
| High line coverage is where weak assertions hide | Coverage is gameable: high coverage with weak assertions is the canonical hiding place, and line count measures size, not quality | Corollary of the mutation and complexity findings above, not an independent study -- carry that hedge | The replacement is diff-scoped visibility, not a repository percentage |
| Assisted authors write less secure code while feeling more confident | A controlled study found assisted developers wrote less secure code yet were more confident it was secure | Perry, N., Srivastava, M., Kumar, D., & Boneh, D. (2023). *Do Users Write More Insecure Code with AI Assistants?* ACM CCS 2023. arXiv:2211.03622. https://arxiv.org/abs/2211.03622 | Model-era-specific: the study used a 2022-generation model. Frontier models plausibly perform better -- re-baseline rather than quoting it as a constant |
| Copy-instead-of-abstract is a measurable trend | 2024 was the first year copy-pasted lines (12.3 percent) exceeded "moved" or refactored lines (9.5 percent) in one commercial telemetry set | GitClear (2025). *AI Copilot Code Quality 2025.* https://www.gitclear.com/ai_assistant_code_quality_2025_research | Descriptively solid; the machine-authorship attribution is correlational, from a commercial vendor using a proprietary "moved" heuristic, and confounded by hiring cycles. Treat the trend as real and the attribution as interpretation |
| Delivery stability moved with adoption | Adoption associated with roughly 7.2 percent lower delivery stability per 25 percent adoption | Google Cloud / DORA (2024). *Accelerate State of DevOps Report 2024.* https://dora.dev/research/2024/ | Associational, and partly revised the following year. This is why it is a context caveat and not a signal |

The published-research figure on package hallucination, and the controlled trial on developer
speed, are already carried on this site with their hedges. Do not restate either; link to
[Verify a dependency before adding it, and know what verification cannot see](../CI-AND-STANDARDS.md#verify-a-dependency-before-adding-it-and-know-what-verification-cannot-see)
and to the section on not claiming an unmeasured gain.

### The six caveats, as one carried set

1. The metric-invalidation findings are robust peer-reviewed results, but they are
   "this-metric-is-weak-**alone**" results. They argue against single-number gates, not against
   measurement.
2. The duplication trend is descriptively solid; the causal attribution is correlational,
   vendor-sourced and confounded.
3. Several findings about machine-authored code are model-era-specific. Re-baseline them rather
   than quoting them as constants.
4. A share-of-distinct-items figure is not a per-occurrence rate. The per-occurrence rate is far
   lower, because the common cases are never the failing ones.
5. The delivery-outcome finding is associational and was partly revised the following year.
6. No source supplies a validated single-metric certification threshold.

### What was refuted, published next to what survived

These widely circulated figures about machine-authored code were checked and dropped. Naming them is
part of the basis, because a reader can then check that the filter actually ran.

- **"About 40 percent of assistant-generated programs contain security vulnerabilities."** An
  over-simplified reading of a real study (Pearce et al., *Asleep at the Keyboard*, IEEE S&P 2022,
  arXiv:2108.09293). The study stands; the headline framing does not.
- **A "ten-fold surge in duplicate blocks" over two years.** Refuted unanimously.
- **"Copy-pasted lines rose 8.3 to 12.3 percent, about 48 percent."** Refuted unanimously.
- **"Moved operations fell 17 percent over two years."** Refuted unanimously; did not reconcile with
  its own source.

Because the refuted claims came mostly from the trend-and-telemetry angle -- vendor material and
secondary blogs -- the rubric leans hardest on the peer-reviewed metric-validity studies and treats
the trend data as caveated context.

### How to derive a rubric so it survives challenge

The method matters more than this particular rubric, because you will need your own.

1. **Decompose the question into distinct search angles** rather than one broad query: metric
   validity; quality frameworks and delivery metrics; empirical trends; security and correctness
   studies; practitioner controls.
2. **Fan out in parallel**, then put every load-bearing claim through **multi-reviewer refutation**
   where each reviewer tries to kill the claim and a majority of refutations does kill it. Only
   survivors enter the rubric. In the pass behind this document, a few dozen sources produced a
   large candidate set; every load-bearing claim went to three-vote adversarial verification, and
   the ones that could be killed were killed. The survivors are the citation table above; the
   casualties are listed below.
3. **Anchor the structure to a recognized model** rather than inventing categories.
4. **Score the reference project from a separate read-only audit**, so the scorecard is evidence
   rather than estimate.
5. **Label every claim with its limitation as you carry it.**

The general form of step 2 is already on this site as
[Run a refutation pass on any number you are about to build a rule on](../CI-AND-STANDARDS.md#run-a-refutation-pass-on-any-number-you-are-about-to-build-a-rule-on).
What is worth adding here is the payoff: the claims that could be killed were killed **before**
publication, not after somebody challenged them, and that is what makes the survivors worth citing.

---

## Failure mode, control, owner

Write the rubric as a map from a failure mode to the specific machine-enforced control that
neutralizes it, and tag each control with which document owns it. Where a companion already owns a
control, **point at it and check only that it is present.** That leaves this document owning
exactly the gates nothing else carries.

The failure modes worth mapping include at least these.

| Failure mode | The control | Owner |
|---|---|---|
| Insecure output plus author overconfidence | A human review step that cannot be waived, plus blocking static analysis | Your security standard. Checked here |
| Hallucinated or typosquatted dependencies | Verify-before-add, hash-locked pins, and an audit of every new import | Your dependency standard. Checked here |
| Silent duplication in place of reuse | Clone detection on the diff, plus a "moved versus copied" review lens with justified parity whitelisted | Here, signal 9 |
| Shallow tests that assert little | Mutation on changed code, as guidance a human reads | Here, signal 7 |
| Unbounded complexity and over-abstraction | Advisory complexity triage: surface, never gate | Here, signal 11 |
| Conventions drifting across a codebase written in many parallel sessions | A broad lint ruleset, plus the always-loaded project instruction file as the standing convention anchor | Here, signal 10, plus your working agreement |
| A control implemented on one path and missed on its siblings | Enumerate sibling paths for every control and encode the enumeration as one deterministic check where feasible | [Enumerate sibling paths for every control](../CI-AND-STANDARDS.md#enumerate-sibling-paths-for-every-control). Here, this is what signal 6 exists to catch |
| Velocity mistaken for delivered quality | Small batches, one coherent layer per change | Your working agreement. A context caveat, not a signal |

**Rule.** When a new control is proposed, ask which failure mode it neutralizes. If the answer is
none, it is decoration. When a control is missing, the owner tag tells you which document to fix.

---

## Where each gate belongs: the local loop, the pipeline, or both

Place a measurement gate by **cost**, not by importance.

| Gate class | Cost | Placement | Blocking |
|---|---|---|---|
| Complexity triage | Cheap | Local hook and pipeline | Advisory only, never a hard gate |
| Broad lint ruleset | Cheap | Local hook and the required pipeline leg | Blocking, from a clean baseline |
| Clone detection | Cheap | Pipeline advisory job | Advisory: a finding, not a failure |
| Diff-scoped coverage | Moderate | Pipeline, reporting on changed lines | Advisory |
| Mutation on changed code | Depends entirely on scope and on the tool actually running | Pipeline, plus an opt-in local command | Advisory guidance |

**Rule.** Cheap checks run in both places. Expensive, diff-scoped analysis is pipeline-first because
it is too slow for the inner loop -- but each one must also be exposed as an opt-in local command a
maintainer can run on demand. **The pipeline is authoritative in every case**; local runs exist for
fast feedback. The mechanics of keeping those two invocations identical are already published:
[One gate command, three call sites](../CI-AND-STANDARDS.md#one-gate-command-three-call-sites).

### Review tools that apply their own edits

Some review tools report findings for a person to arbitrate. Others apply their fixes directly. That
difference is not a matter of taste -- it decides where the tool belongs in your sequence, and
whether it is allowed to count for anything.

**Run an applying tool before the local check quartet, never after.** A tool that rewrites code and
runs after your lint, type and test run mutates the tree that run just certified. Whatever the
quartet told you is then true of code that no longer exists. Tools that only report are safe after
the quartet, because they change nothing. The ordering is a consequence of what the tool does, not a
convention you could reasonably invert.

**An applying tool is not a control, and it may not be scored.** If no pipeline leg runs it and
nothing reads its output, it is not a gate and not a signal. Be precise about why the liveness rule
above -- the requirement that a gate be proven able to fail -- does not reach it: not because it is
advisory, but because **there is no green check to trust in the first place**. State it loosely and a
reader concludes advisory things are exempt from liveness, which is the opposite of the rule.

**A tool that ships with the AI coding tool leaves nothing in your repository to score.** When the
tool arrives with the AI coding tool rather than with the project, no artifact under version
control records its presence. A status claim about it can therefore be neither verified nor
falsified from the repository, so the honest entry is no status at all -- not "built", not
"enabled". This one is easy to get wrong by accident, because the tool is plainly doing useful
work.

**Tell it which duplication is deliberate.** A tool that rewrites for reuse will collapse repetition
that exists on purpose, and collapsing it undoes a decision someone made for reasons. Carry the
exclusions as an open class -- **at least** these, never a closed list -- because the closed form is
what fails: a list of exactly two cases went to review and a third was found that it had missed. A
starting set worth naming:

- A parallel implementation kept deliberately similar across backends and pinned by a parity test.
  The duplication is the point, and the parity test is what protects it.
- A vendored copy of an internal library, pinned by a test proving the copy matches its source.
- Defensive branches in tolerant input parsing. These are not a duplication concern at all -- they
  belong to the complexity signal, and filing them under duplication produces the wrong fix.

Every applied edit stays the maintainer's, kept or discarded one at a time, under the floor that you
reject code you cannot explain. A tool that edits your tree has not certified anything: it is a
review you asked for, and the verdict is still yours.

### Re-derive placement after any repair to the gate

A cost figure produced by a tool that crashed before doing any work is not a measurement. One gate
here was classified expensive and pushed onto a nightly schedule on exactly that basis; once the
tool was pinned to a working version, the same bounded scope finished in seconds and the gate moved
onto every proposed change. The general rule is already stated as
[A cost model built on a broken gate is fiction](../CI-AND-STANDARDS.md#a-cost-model-built-on-a-broken-gate-is-fiction).
The rubric-level consequence: **placement is a derived value, so re-derive it after any repair.**

### Never record a row as built without a proof-of-execution receipt

A status of "built" records a gate's existence, not its execution. In one later review, three
defects were found across two of five measurement gates, all green throughout: two gates measuring
nothing, and one measuring correctly while publishing a wrong derived number. One of them had been
scored built across two published versions of the rubric while producing zero units of work.

The liveness rules that came out of that are published in full under
[A check that cannot fail is not a control](../CI-AND-STANDARDS.md#a-check-that-cannot-fail-is-not-a-control):

- count units examined and never units found
- "nothing to measure" passes only when stated and reasoned
- a reconciliation containing a derived term is blind to that term
- attack the control with the failure class it was built to catch
- the advisory layer needs exactly one job permitted to go red

**Rule for this rubric specifically: a scorecard row cites the receipt, not the workflow file.**

Three mechanics make that receipt trustworthy, and each was learned by losing it:

- **Pin the exact version of any tool a gate depends on.** An open upper bound resolved to a release
  that crashed on the project's runtime before generating any work.
- **Remove failure-swallowing operators from gate scripts.** A trailing ignore-failures operator
  turned that crash into a passing job in well under a minute.
- **Require a non-zero units-examined count**, so a resolution change cannot read as a clean sweep.

### Make an advisory finding a delta against the merge base

A raw advisory list over a whole repository is not usable on a change: every finding anchors on the
same declaration line, so nothing distinguishes what the change introduced from what it inherited.

**Rule.** Compute the finding set at the merge base and at the change head, and report only what the
change introduced or made worse.

### Put advisory findings where the reviewer already is

An advisory measurement that prints to a job log is read by nobody.

**Rule.** Emit it as an inline annotation on the changed lines of the proposal, coalescing adjacent
findings into ranges so the annotation set stays legible.

### Install the gate's own tooling from a checked-in lock

Advisory tooling installed ephemerally on a runner is still a dependency of a control. A version
pin does not satisfy a supply-chain scorer's pinned-dependency requirement, and a hash-pinned
toolchain kept **outside** your existing export-and-diff machinery rots into a pinned, stale and
unpatched one -- a worse posture than floating.

**Rule.** Install gate tooling from a lock that records digests, kept inside the same
regenerate-and-diff machinery as your runtime locks, and assert that it cannot leak into the runtime
install set. *The declaration mechanism -- a non-default dependency group, an optional extra, a
separate lock file -- is ecosystem-specific; check what yours actually guarantees rather than
assuming a version pin is a digest pin.* The general rule is
[Constrain every install site from a checked-in lock](../CI-AND-STANDARDS.md#constrain-every-install-site-from-a-checked-in-lock);
the two deltas above are the additions.

### Rolling out a blocking lint expansion

Widening a ruleset on an existing codebase produces a wall of violations that will either be
suppressed wholesale or ignored.

**Rule.** Auto-fix what is mechanically fixable, grandfather the remainder with per-line
suppressions that each name the rule, and enforce on new code from that clean baseline. See
[Grandfather to a clean baseline, then ratchet](../CI-AND-STANDARDS.md#grandfather-to-a-clean-baseline-then-ratchet).

### Keep volatile counts out of the narrative

One complexity sweep found a certain number of functions over threshold. Two weeks later, with no
change to the rule, the same sweep found substantially more. The count in prose went stale faster
than the document's own revision cycle, and both figures described one repository -- which is why
neither appears here.

**Rule.** A volatile count lives in one machine-readable record the prose links to, never in the
narrative. State the rule; let the record hold the number.

---

## Reviewing the code: depth tiers

Before reviewing, classify every file into a depth tier and review to that tier. Publish the
classification with a line count per tier, so the review is auditable and the deep-read surface is
visibly small.

| Depth | What it means | When it applies |
|---|---|---|
| Read every line | Full comprehension. Explain each line and stand behind it; rubber-stamping is forbidden, and code that stays opaque is rejected | Third-party or unknown-provenance code you are adopting as your own. This is what converts it into owned code |
| Review the guard | Read only the trust-boundary functions that admit unknown-provenance input. The question is "is the gate sound?", not "is every line correct?" | A large first-party file whose only exposure is one boundary |
| Drift check | Skim a first-party parallel implementation for divergence from the thing it shadows. Not line-by-line | A deliberate second implementation of behavior that exists elsewhere |
| Glance | Confirm the shape of a representative example. Representative, not exhaustive | Sample or template code that shows a pattern |
| Provenance note | Record where it came from and who verified it | Bundled data rather than code |

**Rule.** Measured in one review: the deep-read tier was roughly five percent of the reviewed lines.
That is the point of the classification -- the expensive read is aimed at the fraction that earns
it, and every other file has a named cheaper obligation rather than being skipped in silence.

The comprehension bar itself is settled on this site: you must be able to explain every reviewed
line and stand behind it, and reaching that explanation with assistance is fine. See *Reject code
you cannot explain* in [CI and standards](../CI-AND-STANDARDS.md).

### Anchor a review record to a stable name, not a line number

**Rule.** Cite the function or symbol name and tell the reviewer to search for it. Record an
approximate position only as a convenience, and say in the record that positions drift. A checklist
whose citations all point at the wrong lines within one release is not a checklist.

---

## Reviewing a trust boundary

When a component executes, imports or loads content of unknown provenance, review the **boundary**
rather than the body, against a fixed question set. These generalize from a real review of one such
seam; the two most commonly missed are the last two.

1. **Does the vet actually bound what can load?** Not "does a vet exist" -- does it constrain the
   set.
2. **Is there any code path that reaches execution without the vet running first?** Check every
   caller, not only the documented one.
3. **Does it fail closed?** No silent downgrade to a weaker mode when the intended backend is
   absent, and no fallback on an unknown name.
4. **Is the load target validated against a fixed known set before use**, so operator input cannot
   trigger an arbitrary import?
5. **Does the vet cover the whole executable surface**, or only the obvious top level?
6. **Does it follow links?** A vetted-looking entry can point at a writable or foreign target.
7. **Is the check silently skipped under a privileged account?** If so, that account must be
   documented as unsupported for running the component.
8. **If it installs a resolution shim, is the shim scoped to the load window and removed
   afterwards, and does it resolve only the names it is meant to?** A shim at the front of the
   resolution order shadows genuine components for its whole lifetime.
9. **Does a failed load clean up after itself**, leaving no partially initialized state registered?
10. **Is there a platform on which the runtime check returns early and does nothing?** If so, the
    real boundary is an install-time filesystem permission that somebody must confirm was actually
    applied -- and if that platform is your primary one, the runtime check is not the control you
    think it is.

**Rule.** Where a question resolves as "not yet, because the risky case does not exist here",
record a **re-review trigger** naming the event that makes it exist.

---

## Confirming the control plane

Split a release review into two parts and do the cheap half first.

**Part A -- the control plane. No code reading.** For each required check, confirm it exists, that
it is **blocking** rather than advisory, and that it was **green on the exact commit being
released**. The release change's own pipeline run is the control plane executing. Confirm at least:

- a dependency inventory with a verify-before-add rule and no fabricated or near-miss names;
- pins that are hash-locked and provably in sync, with a re-export diff that comes back clean;
- a blocking dependency-vulnerability scan that installs with hashes required;
- scheduled vulnerability surveillance across **every** package ecosystem in the repository,
  including ones outside the primary language;
- static analysis and secret scanning, blocking, with the secret scan over the full history;
- the scanner rule configuration and the local hook configuration present, tracking the same tool
  versions as the pipeline;
- any provenance convention the project claims -- counted in the actual history, not assumed.

**Review the scanner suppression list explicitly rather than accepting it.** A suppressed rule class
is a control that has been turned off, and the skip list is where that decision is recorded.

**Mark which nominally-security jobs are advisory rather than blocking, and do not count those as
coverage.** See
[Blocking and advisory are not the same coverage](../CI-AND-STANDARDS.md#blocking-and-advisory-are-not-the-same-coverage).

**Part B -- the line-by-line surface**, reviewed to the depth tiers above.

---

## When review is self-review

Where there is one maintainer, or no available second reviewer, row 5's human review is self-review.
Record that as a **documented deviation** rather than describing the control as satisfied: name the
control that cannot be met, the compensating set actually in force, and the event that ends the
deviation.

Then name the control that most nearly compensates. The overconfidence finding bites hardest
exactly when the author reviews their own machine-assisted output, which makes **mutation on changed
code** the highest-leverage gate to build first: it is the one control that adversarially checks
whether the tests assert anything, independently of the author's confidence.

---

## Adapting this to your project

**Change freely:**

- The tool behind every gate. Nothing here names one, deliberately.
- The thresholds. Set them from your own accumulating data and record them in your own appendix,
  labeled project-set rather than evidence-certified.
- The owner tags. They should name the documents you actually have.
- Row 10's ruleset, and row 1's boundary rules. Both are project-shaped by definition.
- The depth-tier names, if yours are clearer. Keep the property that every file gets exactly one.

**Do not weaken:**

- **The tier split.** Tier 2 rows may never decide a verdict. Moving a measurement row into Tier 1
  because it is easy to measure is the whole failure this rubric exists to prevent.
- **The anti-metric rule.** A coverage floor or a complexity gate is a defect, not a stricter
  standard.
- **The receipt requirement.** No row is recorded as built without proof it examined something.
- **The hedges on the citations.** Quoting a figure without its limitation is how a document loses
  a reviewer who has read the paper.
- **"Unverified is not a pass."** An unscored row is an open question, not a quiet yes.
- **The refuted list.** If you drop it, the surviving citations lose the thing that makes them worth
  more than alarm-bell numbers.

**Decide before you publish, not after:** whether your signal numbers will be cited from outside the
document. In the source rubric they were renumbered one revision after publication, which required
rewriting every cross-reference in the document and its appendices. The citation identifiers were
deliberately left alone, because they are citations rather than signals. If a number will be quoted
elsewhere, freeze it; if you must renumber, say which identifier families are frozen and which
moved, and rewrite every cross-reference in the same change.

---

## In one table

| When | Rule |
|---|---|
| Scoring | Judge by the composite. Tier 1 decides; Tier 2 only starts a conversation |
| Scoring | Unverified is not a pass. An unscored row is an open question |
| Scoring | A row is built only when a receipt proves it examined something |
| Gating | Never certify quality, or fail a build, on any single gameable number |
| Gating | No validated universal threshold exists. Set yours, record it, label it project-set |
| Gating | Advisory findings are a delta against the merge base, annotated where the reviewer is |
| Gating | An outcome metric belongs in a delivery review, not an artifact rubric. Altitude, not distaste |
| Placing | Cheap gates run in both places; expensive ones are pipeline-first but locally invocable |
| Placing | The pipeline is authoritative. Local runs exist for fast feedback |
| Placing | Re-derive placement after any repair -- a cost model built on a broken gate is fiction |
| Tooling | Pin exact tool versions; no failure-swallowing operators; require a non-zero examined count |
| Tooling | Install gate tooling from a digest-recording lock, inside the same export machinery as the runtime locks. The declaration mechanism is ecosystem-specific |
| Citing | Carry the hedge with the claim, at the point of use, never in a footnote |
| Citing | Publish what failed verification next to what passed |
| Reviewing | Classify every file into a depth tier and review to that tier. Publish the classification |
| Reviewing | Review a trust boundary by its question set, not by reading the body |
| Reviewing | Anchor a review record to a symbol name. Line numbers drift |
| Reviewing | Confirm the control plane first: present, blocking, green on the released commit |
| Reviewing | Advisory jobs are not coverage. Count blocking jobs that run on the change |
| Owning | Every control names the document that owns it. Point at the owner; do not restate the control |
| Owning | A control with no failure mode is decoration |
| Owning | Where review is self-review, record the deviation and name what compensates |

---

## Related

- [CI and standards](../CI-AND-STANDARDS.md) -- the metric table with its [external] tags, judging
  tests by assertions, receipts and liveness, sibling-path enumeration, the allowlist rule for
  published artifacts, and the claim-honesty register
- [Tips and tricks](../TIPS-AND-TRICKS.md) -- sections 4 and 5, writing a guardrail and measuring
  whether it works
- [Case study: auditing a multi-session estate as one system](../CASE-STUDY-drift-audit.md) --
  proving a fix by deliberately mutating the shipped artifact
- [Running a large security-standard assessment with AI agents](../ASVS-ASSESSMENT.md) -- verdict
  vocabularies, evidence anchors, corpus pinning, and how to read a movement in a score
- [The leak gate](../LEAK-GATE.md) -- the three ways a scanner lies, and the blind spot no scanner
  closes
