# Secure development: a starting point for your own standard

> **Take a copy:**
> [markdown](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/SECURE-DEVELOPMENT.md)
> or [Word document](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/SECURE-DEVELOPMENT.docx).
> [Every file, both formats](OVERVIEW.md#the-files).

---

## TLDR/BLUF

This is a starting point for your own secure development standard, not a standard to comply with
and not a compliance attestation: copy it, cut what your project does not have, and publish the
result under your own name.

- **What it demands.** Checks that block every change and no author can waive. A written threat
  model per trust boundary, before the code. Every unmet requirement dated, signed, and carrying
  the event that ends it. No green pipeline is a verdict.
- **What it costs.** Calendar time, controls you must not claim because you do not own them, and
  two gaps no internal pipeline closes: third-party source review and
  [penetration testing](#15-independent-external-verification). No code ships with this.
- **Where it does not apply.** Throwaway work, and anything you operate rather than produce.
  Building to this confers nothing on you or on an adopter.
- **Where to start.** [Section 1](#1-shared-responsibility-write-the-split-down-first), the
  ownership split, then the data-class table under it.
  [Adapting this to your project](#adapting-this-to-your-project) says what you may change freely;
  [In one table](#in-one-table) is the summary.

---

## 1. Shared responsibility: write the split down first

Software built by one party and run by another has a boundary. The failure mode is not that somebody
does the wrong thing -- it is that both sides assume the other has it covered. Publish the split as
a table so that assumption cannot survive.

| The producing project owns | The operating organization owns |
|---|---|
| Secure development practice | Its own host, network and platform security |
| Secure-by-default configuration | Identity, credential and key management in its environment |
| Testing and attestation of the software | Backups, disaster recovery, availability |
| Vulnerability response and disclosure | Its own compliance program and risk assessment |
| Documentation and evidence | Monitoring, patching, incident response |
| The audit log's review affordance and a labelled retention default | Reviewing the audit log on a defined cadence, and what counts as unusual activity there |

Shipping the software confers nothing on the operator. An attestation that the software was built
securely is an input to their assessment, never a substitute for it. State that where an adopter
will read it, not in a footnote.

The split also constrains what you may write elsewhere in this document. Anything in the right-hand
column is something you **document and recommend**. It never appears in a list of controls you
provide.

### The third participant: services neither column owns

List the services the build depends on, what each is trusted to do, and what fails if it is
compromised or simply goes away. **[prompted by: 800-53 SA-9]** (The first of the bracketed marks:
the source raised the topic, and the rule as written is ours.
[Where the rules come from](#where-the-rules-come-from) defines this one and the other two.) The two
columns above have no room
for the CI provider, the source host, the package registry, the transparency log or the artifact
store, so every control those hold gets filed under a column where it does not fit. Give them a table
of their own. Five to eight rows is the whole of it.

| Service | Trusted to | What fails if it is compromised, or goes away |
|---|---|---|
| Source host | Hold the trunk, enforce branch protection, keep the history | Every protected-path rule, and the provenance chain back to a commit |
| Build service | Execute the pipeline on a runner you do not administer | The claim that the artifact traces to a repository rather than to a machine |
| Package registry | Serve the artifact under the name consumers resolve | Distribution, and the account that publishes under that name |
| Transparency log | Hold the inclusion proof a consumer checks | Verification for anyone who cannot reach it, unless the proof was bundled |
| Evidence and artifact store | Retain releases, inventories, attestations, register | [Section 10's](#10-build-and-release-integrity) archive, and every claim that rests on it |

This is also where [section 10's](#10-build-and-release-integrity)
*[keyless signing moves the threat model, it does not remove it](#publishing-controls-and-the-limit-each-one-carries)*
puts the load it relocates. That sentence names a relocation and, without this table, the load has
nowhere to land.

Right-size the ongoing part honestly. For a small team, monitoring a provider means subscribing to its
status and security advisory feeds and actually reading them, not auditing it. Write that, rather than
an oversight sentence nobody performs. The table is a written artifact: it introduces no new blocking
release condition and weakens nothing above it.

### What "restricted data" means here, exactly once

Define the data classes in one table, and let every other rule on this page point at it rather than
carry an adjective of its own. **[prompted by: 800-53 SC-28]** One row per class of data the
software handles, with five columns:

| Column | What goes in it |
|---|---|
| Class | The name this document and your code both use for it |
| Enters through | Which trust boundary from [section 2](#2-threat-model-each-trust-boundary-before-you-build-it) it arrives on |
| Comes to rest in | **Every** place, not the obvious one: primary store, application log, audit log, temporary and spool files, crash dumps, diagnostic and support bundles, exports, published artifacts, test fixtures, and the context handed to an AI coding assistant |
| Protected how | The protection at each of those resting places, and where the key material for it lives |
| Kept how long | The shipped retention default, and the documented path that deletes it |

One row filled in, to show the shape. Illustrative only -- it is not a required entry and it
describes no project:

| Class | Enters through | Comes to rest in | Protected how | Kept how long |
|---|---|---|---|---|
| Credentials and key material | No boundary in section 2's list -- the running account resolves this at startup rather than receiving it as input, which is what the column is for | The secret store, and nowhere else -- not the primary store, the application log, the audit log, a temporary or spool file, a crash dump, a support bundle, an export, a published artifact, a test fixture, or the context handed to an AI coding assistant | Encrypted at rest by the secret store, and the running account holds no copy in a file. The key material protecting the store is the operator's, in whatever key service the store is configured against -- a right-hand-column control under [section 1](#1-shared-responsibility-write-the-split-down-first), named here rather than claimed | No retention default, because nothing is retained: rotation replaces the value and the store discards the previous one. Rotation is the documented deletion path |

Classes that recur:

- credentials and key material
- data restricted under a regime the adopting organization operates under
- operational telemetry that identifies a person or a site
- the published artifact and its metadata, which is public by construction and belongs in the table
  precisely so that is written down rather than assumed

The third column is the one that earns the table. "At rest" is commonly read as a property of a
storage device. Read that way it covers the primary store and misses the rotating log file, the
crash dump and the support bundle -- which hold the same content, in the same state, with none of the
protection. Rate the **state of the information**, not the device it happens to sit on and not how
often anything reads it.

Rate each class against the three security objectives, at three impact levels.
**[derived: FIPS 199]** Confidentiality, integrity and availability, each low, moderate or high. That
is the whole of the vocabulary this document needs, and it is enough.

**Restricted data**, everywhere else on this page, means any class your own filled-in copy of that
table rates above low on confidentiality or integrity. Deliberately not "the top impact level". This
term replaced an open-ended adjective that earlier rules on this page already carried. A
definition narrower than the adjective it replaces silently weakens every one of them: it would let a class
rated moderate travel in cleartext, rest unencrypted, and be logged at informational level -- with no
edit to any of those rules, and nothing in the diff to show it. If you want a stricter tier for one
specific ratchet, name that ratchet where it is stated and leave the rest quantified over the broader
set. That is the single definition. If a rule elsewhere says restricted data and your table has no
row that matches, the finding is the missing row.

The table supplies the scope of at-rest protection and the retention default -- what the rule is
quantified over, and for how long. It supplies no storage mechanism, and adopting it does not by
itself make anything encrypted; it makes the existing default in
[section 7](#7-secure-defaults-and-the-opt-in-that-must-be-explicit) checkable, which it was not
before. And it is a written artifact rather than a release gate: it adds no blocking condition and
weakens no requirement above it.

---

## 2. Threat model each trust boundary before you build it

A trust boundary is anywhere input you do not control crosses into code you do. A network
interface is one. So is a command line, a file dropped in a watched directory, a scheduled job
reading shared storage, a queue consumer, a webhook, an inter-process channel, and a database
somebody else writes to. If your system has no network interfaces at all, it still has boundaries.

Every boundary and component gets a written, lightweight threat model. It names a mitigation for each
way in, and puts a constraining control on each piece of dangerous functionality and each
third-party component it pulls in.

Three properties make it worth writing:

- Reviewed against the security requirements before code exists. After the build it becomes
  documentation; before the build it is a design gate.
- The specification the later review checks against. The reviewed artifact plus its acceptance
  criteria are what a change is compared to -- without them, review has nothing but taste.
- Artifact-checked and advisory, not a scanner. Do not pretend otherwise: nothing mechanical
  verifies that a threat model is good, and a gate can only verify that one exists for a boundary
  that was added.

The highest-value form is boring: a list of every place unknown-provenance data or code enters, and
against each one the specific thing that bounds it. When a new ingress is added and nobody can name
its mitigation, that is the finding.

One row, to show the shape. Illustrative only:

| Boundary | Mitigation | Bound |
|---|---|---|
| A file dropped in a watched directory | Path canonicalised against the configured directory so traversal and symlink escapes are rejected; type and size validated by content rather than extension; written atomically then renamed | Maximum file size, files accepted per minute, concurrent readers, and total processing time per file |

Name a bound on resource consumption for every boundary, not only the parsing ones.
**[prompted by: 800-53 SC-5]** The questions in this section and the list in
[section 3](#3-secure-coding-the-finite-list-a-review-can-check) cover confidentiality and integrity
almost exclusively. The one availability control on this page -- rate limits and timeouts -- used to
sit inside [section 3's](#3-secure-coding-the-finite-list-a-review-can-check) structured-document
bullet, as though a parser were the only thing that can be exhausted. That bullet now points here
instead. Availability is a co-equal third objective. So for each boundary in the model, name the
maximum payload size, the request rate, the concurrency and the total time budget that a hostile
input cannot exceed. An unbounded boundary is a finding in the same way an unmitigated ingress is.

The evidence is cheap, and it is the same shape as *enumerate the sibling paths* in
[section 5](#5-scanner-posture-what-blocks-what-advises-what-may-never-be-waived): the bound is a
constant in the code, so the check is one grep from each row of the boundary list to the constant
that enforces it. The common residual is the limit set on the boundary somebody thought about and
absent on its three siblings. Naming the bound records what is already there or reveals that it is
not; it introduces no new blocking release gate.

Run a malformed-input harness against the code behind every ingress in that list.
**[derived: 800-53 SA-11(8)]** Seed it from that boundary's own format, run it on a schedule rather
than on every change, commit the corpus, and turn every crash it finds into a regression test. This
is developer-run dynamic testing, and it is available to a project that cannot fund an outside
engagement -- see the correction in [section 15](#15-independent-external-verification), where this
document previously said otherwise.

[Section 5](#5-scanner-posture-what-blocks-what-advises-what-may-never-be-waived) classifies it,
explicitly, as **advisory**: a scheduled job is by that section's definition not coverage. And this
one must not be wired to block, because its triage burden lands on the same person who would
otherwise be shipping. Carry the coverage hedge with it: a fuzzer that never gets past the first
parse call is the dynamic-testing equivalent of a clean run on a weak ruleset. And be precise about
reach: this gets at parser, decoder and boundary surfaces, not at the whole built artifact, so it
narrows the dynamic-testing gap rather than closing it. Do not write it up as closed.

### A diagram without marked trust boundaries is not a security artifact

The model above is a list, and a list is hard to check for absence: nobody notices the ingress that
was never written down. Draw the same thing. One diagram per system, showing at least the external
entities, the processes, the data stores, and the flows between them -- with the trust boundaries
drawn on it, as lines the flows cross.

**The boundaries are the whole of what makes it a security artifact.** Components and arrows with no
boundaries marked is architecture documentation. It is useful, it is not this, and the failure mode is
specific rather than pedantic: it gets found later by somebody who reads it as a threat model, because
it is the only picture in the repository and it looks like one. Mark on the diagram itself which lines
are boundaries, or do not file it as a threat modeling artifact.

It is one artifact in two forms, and the check is that they agree. Every crossing on the diagram
has a row in the boundary list, and every row in the list has a crossing on the diagram. That two-way
check is what the picture buys over the list alone, and it is a read-through rather than a tool. Label
each flow with the data class it carries, from
[section 1's](#1-shared-responsibility-write-the-split-down-first) table. That table's
*enters through* column becomes checkable in both directions rather than being a field somebody
filled in once.

Keep the source in the repository, in a text format that diffs. A binary drawing in a shared folder
cannot be reviewed inside a change and is stale by the time anyone opens it. A diagram whose source is
text shows a new boundary as an added line in a diff, which is the same property that makes the
boundary list worth keeping in the first place. Any format with a text source works, and this document
names none, because the property is diffability rather than a tool.

The diagram establishes nothing about the code. It records what somebody believed the boundaries
were; the code is where they actually are, and the two diverge without a sound. Nothing mechanical
verifies it, as with the threat model above. And it goes stale on at least the events that stale that
table -- a change that adds a data class, gives an existing class a new resting place, or adds a
boundary. And on a few the table survives, among them a flow rerouted, a data store added, and a
boundary removed. It therefore rides the event trigger
[section 14](#14-re-evaluate-on-a-trigger-and-on-a-short-calendar-for-what-has-no-trigger) gives
[section 1's](#1-shared-responsibility-write-the-split-down-first) data-class table, and the row
[section 16's](#16-the-release-gate) gate already carries for that table, rather than adding a gate
row or a fifth calendar item of its own. It is also a map of every way into the system, so
[section 13's](#13-deviations-and-risk-acceptance) *publish the rule, not the inventory* governs what
you do with it.

Normative force: a written artifact, recommended. It introduces no new blocking release condition and
weakens nothing above it.

### Execution boundaries need the longest look

Trust boundaries where content becomes executable deserve more scrutiny than the rest. These
questions generalize:

- Is there any path that reaches execution without the vet running? Check every caller, not the
  documented one.
- Does it fail closed, with no silent downgrade when the intended backend is absent?
- Is the load target validated against a fixed known set, so input cannot trigger an arbitrary
  import?
- Does the vet cover the whole executable surface or only the obvious top level?
- Does it follow links, so a vetted-looking entry can point somewhere writable?
- Is the check skipped under a privileged account?
- Is there a platform on which the runtime check returns early and does nothing, making the real
  boundary an install-time filesystem permission somebody has to confirm was applied?

That last one is the one most often missed.

---

## 3. Secure coding: the finite list a review can check

A short checkable list beats a principle, because "is this change secure" is not a question a
reviewer can answer and these are.

- Validate structure and content of every inbound payload at ingress. Reject or quarantine
  malformed input rather than processing it. An untrusted payload must be validated before it reaches
  a query, a file path, a subprocess, or a message you emit downstream.
- Parameterised queries only. No string-built statements anywhere, no exceptions held open by a
  comment.
- Authentication and authorization enforced on every action, deny by default.
- For anything that parses structured documents: disable external-entity resolution and
  document-type processing, size-limit payloads against a schema, apply that boundary's resource
  bounds from [section 2](#2-threat-model-each-trust-boundary-before-you-build-it) rather than a rate
  limit and timeout invented here, and never return internal detail in a fault response.
- For file handling: confine reads and writes to configured directories and canonicalise paths so
  traversal and symlink escapes are rejected. Validate type and size by content rather than
  extension. Write atomically then rename so a partial file is never processed. Never place files on
  an executable or served path, and never execute file contents.
- Use vetted cryptographic libraries. Never roll your own.
- Fail closed on error. Never log secrets or restricted data, as
  [section 1's](#1-shared-responsibility-write-the-split-down-first) table defines it.

Two more are already owned elsewhere on this site, and are named here only so the enumeration is
complete: treating everything an agent reads as data rather than instructions, and verifying a
dependency's identity before adding it. Both are covered in
[CI and standards](../CI-AND-STANDARDS.md).

---

## 4. Review, and what to do when there is no second reviewer

Every change is peer-reviewed, static analysis and dependency analysis run on it, and the review also
confirms the change conforms to the acceptance criteria of whatever specified it.

That is the requirement. Many projects cannot meet it, and the honest response is not to redefine
"reviewed" until it fits.

### Self-review is a documented deviation, not a satisfied control

Record it as a deviation. Name the control that cannot be met. Name the compensating set actually in
force -- typically blocking static analysis and dependency audit that cannot be waived, AI-run review
that a human arbitrates, branch protection with required checks, and no direct pushes to the trunk.
Name the event that ends the deviation, which is usually a second maintainer joining.

Then constrain the wording. The compensating set is a **compensating control, explicitly not an
independent audit**, and no published claim may imply otherwise.

### The confidence effect bites hardest in self-review

**[external]** A controlled study found developers with access to an AI coding assistant wrote less
secure code while being more confident it was secure. The study used a 2022-era model, so
re-baseline the magnitude rather than quoting it; the direction is what matters here.

The citation and its hedge live in one place -- the evidence table in
[Judging code quality, whoever or whatever wrote it](CODE-QUALITY.md#the-evidence-and-the-hedge-each-citation-must-carry).

That effect bites hardest exactly in the self-review case, which is the argument for the one control
independent of the author's confidence: an adversarial check on whether the tests assert anything.
See *Judge tests by their assertions, not their presence or their coverage* in
[CI and standards](../CI-AND-STANDARDS.md).

### The comprehension bar, and two additions to it

The comprehension bar that goes with review -- reject code you cannot explain, with assistance in
reaching the explanation being acceptable -- is settled on this site under that name in the same
document.

Two small additions are worth carrying. An AI coding assistant's explanation can be confidently
wrong in the same way its code can, so the human verifies the explanation rather than accepting it.
A periodic cold spot-check of an already-merged assisted change is a cheap way to detect that
explaining has drifted into rubber-stamping.

---

## 5. Scanner posture: what blocks, what advises, what may never be waived

**Coverage is the set of blocking checks that run on a change, not the tool inventory.** Advisory and
scheduled-only jobs are useful and are not coverage. Classify every nominally-security job as one or
the other and write the classification down, because the two are indistinguishable from a green
badge.

### What must block, and may not be waived

The following must block a change, and may not be waived by an author:

- Static analysis, red on any new finding from a clean baseline.
- Dependency vulnerability analysis, red on any new advisory.
- Secret scanning, over the full history, not only the diff.

Mechanics for all three are already published. [CI and standards](../CI-AND-STANDARDS.md) covers
grandfathering to a clean baseline and then ratcheting, and running supply-chain audits on a schedule
as well as on changes. It also covers the two-layer shape where a local hook gives fast feedback and
the pipeline is the authoritative gate.

Fail-closed forbidden-content scanning and the three ways a scanner lies are in
[the leak gate](../LEAK-GATE.md).

The scheduled malformed-input harness described in
[section 2](#2-threat-model-each-trust-boundary-before-you-build-it) is classified here, explicitly,
as **advisory**. It is a real control and it is not coverage. Both halves of that have to be written
down, or the tool inventory grows while the blocking set stands still.

### Dynamic testing: an event trigger, and a written record of what no trigger reached

The blocking set above is entirely static. Three checks that read code, manifests and history without
executing anything. [Section 2](#2-threat-model-each-trust-boundary-before-you-build-it)'s
malformed-input harness is the only control this document states that runs the built code against
input it did not expect. A scheduled job with no stated trigger drifts into being a green light
nobody asked a question of. Give it a policy, in three parts.

Trigger a dynamic pass on an event, and name the events. At least these, and each is answerable from
a diff rather than from a judgment:

- A boundary is added to [section 2](#2-threat-model-each-trust-boundary-before-you-build-it)'s list,
  or the parser, decoder or deserializer behind an existing one is replaced.
- A dependency that does the parsing or decoding at a boundary crosses a major version.
- A finding of this class arrives from any source -- an advisory, a report, a crash in the field. The
  confirming run is [section 12](#12-vulnerability-response-exercised)'s, and it has to mirror the
  original.
- A release changes the ingress surface.

The schedule [section 2](#2-threat-model-each-trust-boundary-before-you-build-it) already sets stays
where it is, and it is doing a different job. A fuzzer finds more with more machine time, so the
scheduled run is how the corpus accumulates. The triggers are what make the pass answer a question.
Neither replaces the other, and a project running only the schedule has a control that cannot respond
to anything.

This is not a fifth item for
[section 14](#14-re-evaluate-on-a-trigger-and-on-a-short-calendar-for-what-has-no-trigger). That pass
is capped at four, and these are events with a diff behind them rather than calendar entries. The
record required below is a field in an entry that pass already writes, so the four-item cap holds and
nothing here adds a row to the release gate in [section 16](#16-the-release-gate).

Write down what no trigger reached, in the record somebody already writes.
[Section 14](#14-re-evaluate-on-a-trigger-and-on-a-short-calendar-for-what-has-no-trigger)'s periodic
pass produces a dated entry recording what was checked and what changed; dynamic testing is a line in
that entry. Where no trigger has fired since the last pass, the line says dynamic testing did not run
and carries that pass's date, rather than inheriting the last green run. That places the honesty
control on an existing artifact with an existing owner and cadence, which is the only way a record of
a non-run ever gets written. Where a pass did run, record its reach and not only its result. The
harness gets at parser, decoder and boundary surfaces, and does not get at authorization decisions,
business logic, multi-step flows, or state held across requests. Those are surfaces an external
engagement reaches and this does not, which is
[section 15](#15-independent-external-verification)'s gap and stays open however green this is.

The honest limit is the one [section 2](#2-threat-model-each-trust-boundary-before-you-build-it)
already carries, and it is the one that decides whether any of this meant anything: a harness that
never gets past the first parse call is the dynamic-testing equivalent of a clean run on a weak
ruleset. The coverage question is what the corpus reached, never how long it ran.

Nothing above blocks -- this section's classification of the harness as advisory does not change, and
a trigger firing produces a pass and a record, not a red change. And nothing here is borrowed at the
technique level. SP 800-115 is the publication whose subject this is, it is cited on this page for
its process material only, and its technique and tooling inventory has a row in the coverage table
saying so. That is why the trigger list and the reach statement are unmarked and this document's own.

Normative force: a triggered pass and a dated record, recommended. Nothing blocks, and no release
condition changes.

### Three additions specific to a security posture

A clean run is a start condition, not a certificate. Zero findings on a weak ruleset proves nothing
at all. What the clean baseline buys you is the ability to enforce red-on-regression; that is the
whole of its value.

Confirm the gate can see the class it exists to catch. A green gate is evidence only once you have
fired the failure class at it and watched it go red. This is stated in full under *Attack the control
with the failure class it was built to catch* in
[CI and standards](../CI-AND-STANDARDS.md), and it applies to every check in this section.

The per-finding form of the same discipline -- a finding is closed by its own check going green on
the commit carrying the fix, never by the fix merging -- is in
[section 12](#12-vulnerability-response-exercised). It is one rule read at two scales, not two rules.

Enumerate the sibling paths. A control implemented exactly where it was prompted, and missing on its
siblings, is the single most common residual after an agent-run security sweep. Encode the control as
one deterministic check shared across every path rather than as a habit applied per path.

Record rigor and scope as two separate values for each blocking check, never as one. A check that ran
on one path at high rigor and a check that ran on every path at low rigor both report green, and no
tool will tell you which of the two you have. Against each check in the blocking list, note how deep
it looks -- a pattern match, a taint analysis, an executed test -- and how much of the surface it
covers: this module, every sibling, the whole tree. Filled in, a row reads pattern match / this
module, or taint analysis / whole tree.

Two words per row, filled in once when the check is added, and it is the fastest way to notice that
the most rigorous check in the suite runs on one directory. The sibling rule above is the scope half
already stated on its own; this pairs it with the depth half, so neither can quietly stand in for the
other. It records what you already have, so it adds no blocking condition.

### The security anti-metrics

The site already forbids gating on a single gameable number, with the general metric evidence. These
are the security-specific badges that impersonate a verdict. Each may be surfaced as advisory
context. None may ever be the pass or fail decision.

| Badge | Why it is not a verdict |
|---|---|
| Number of security scanners | A tool count. Advisory and scheduled-only jobs never redden a change |
| Finding count reaching zero | A start condition for red-on-regression. Zero on a weak ruleset proves nothing |
| Fuzzing hours, or corpus size | Machine time and a file count. Neither says which surfaces the corpus reached |
| A single percentage-pass headline from an assessment | Hides the composite, and moves when the standard revises its denominator |
| "Certified" phrasing against any framework | Describes a certificate that does not exist |
| Count of controls marked "built" | Built is not on-by-default is not fail-closed is not independently verified |
| A green pipeline, or a passing self-assessment | One input. No self-run gate substitutes for an outside challenge |
| "A risk register exists" | An unsigned acceptance is an un-accepted open gap wearing the costume of a decision |
| Count of externally-catalogued control identifiers cited | A citation records where a rule came from. It is not coverage, and counting citations scores nothing |

**There is no validated threshold at which a build becomes secure.** No framework supplies one --
not a blocking-check count, not a pass rate, not a remediation-time floor. Any number you adopt is
project-set and directional. Label it that way, and review it as your own data accumulates.

---

## 6. Secrets and repository hygiene

No secrets, keys, credentials, or restricted data ever enter the repository, and the full history
stays clean rather than only the current tree. This is not a private-repository exemption: a
repository's visibility can change, and its history travels when it does.

The rule and its mechanics are owned by [the leak gate](../LEAK-GATE.md) and by *Secrets and sensitive
data never enter the repository, wherever it is stored* in
[CI and standards](../CI-AND-STANDARDS.md). Two points belong to the process rather than the scanner.

A path deny-list is not a content control. It keeps a file from being read; it does nothing about the
same content typed into a different file. Pair it with a fail-closed commit-time content scan.

A commit-time scanner is not a live interceptor. It sees what lands in a commit. It does not see an
outbound query, a tool-server call, or a fetch argument.

Nothing mechanical stands between a running agent and that channel, so the discipline there is on the
human -- and the standard has to say so, rather than letting the green scanner imply coverage it does
not have.

---

## 7. Secure defaults, and the opt-in that must be explicit

Ship with transport encryption on, encryption at rest on for every resting place
[section 1](#1-shared-responsibility-write-the-split-down-first)'s table names for a restricted class,
least-privilege accounts, and verbose audit logging. Any insecure posture is an explicit, named,
documented and audited opt-in behind a fail-closed guard -- never a posture a deployment inherits by
omission.

The at-rest half of that used to be unverifiable, and the reason was never a missing mechanism. It
was that nobody had said what it was quantified over. The table's third and fourth columns are what
make it checkable: the default holds when every resting place listed for a restricted class has a
protection recorded against it, and the retention column says how long each one keeps it.

Two reading errors go with this, and both are defects in opposite directions.

Off by default, described as active. The code exists; nothing is running.

Fail-closed, mis-read as inert. It looks like nothing is happening because nothing needs to.

Score and describe those states separately, and state fail-open versus fail-closed next to the code
with the reason -- see *Fail-open or fail-closed is a choice you must state* in
[CI and standards](../CI-AND-STANDARDS.md).

### Synthetic data by default in anything that is not production

Test, development and preproduction environments run on synthetic or dummy data, and any use of live
or operational data is approved, documented and dated in the
[section 13](#13-deviations-and-risk-acceptance) deviations register, with that environment protected
to the same level as the system the data came from for as long as it is present.
**[derived: 800-53 SA-3(2)]** The approve-document-control clause and the equal-level clause are the
control; synthetic-by-default is the posture its own discussion directs, stated here as the default
so the approval path is the exception rather than the norm.

State the ratchet explicitly, because it is the part people get backwards. Copying a restricted class
into a test environment does not lower that data's protection requirement -- it raises the
environment's. That is the entire argument for the default being synthetic, because the alternative is
protecting every scratch environment like production, permanently. It also supplies a protection for a
resting place [section 1](#1-shared-responsibility-write-the-split-down-first)'s table would otherwise
list bare: the test fixture. The evidence is the fixture or the generator that produces the synthetic
data, plus a dated register entry naming what was copied, where it went, and when it was destroyed.
This is a default and a register route, not a new blocking release gate.

### Rate a collection by the highest class it holds

**Rate a collection by the highest class it holds, never by the average and never per entry.**
**[derived: FIPS 199]** The at-rest default above is quantified over resting places, and several of
the resting places this document tells you to build are accumulators. The
[section 9](#9-tamper-evident-audit-logging) audit log has an entry-level rule about keeping payloads
out and says nothing about the accumulated record. The
[section 10](#10-build-and-release-integrity) release archive holds the artifact plus its build
inputs plus its inventory, and is therefore a map of the whole system that no single input is. The
[section 13](#13-deviations-and-risk-acceptance) deviations register is the third. Each is
individually innocuous, and collectively they are the thing an attacker would actually want.

[Section 13](#13-deviations-and-risk-acceptance) already reaches the right answer for the register --
publish the rule, not the inventory -- but it reaches it as a standalone instruction. Naming the
roll-up as the principle is what generalises it to the other two. This is a rating decision on three
named artifacts rather than a process. It is evidenced by the access posture on each: who can read
the archive, whether the register sits in the published tree, and whether the audit log has a row in
[section 1](#1-shared-responsibility-write-the-split-down-first)'s table.

---

## 8. Machine-to-machine authentication

A caller that is a machine authenticates as a system, not a person. Use the strongest mechanism
the peer system supports.

Record, per connection, the mechanism, its scope, and a reference to where the credential lives. Keep
that record alongside that connection's configuration, so the posture is reviewable one connection at
a time rather than as a paragraph of prose.

A workable hierarchy, strongest first:

1. **Mutual TLS** with full chain validation, revocation checking, and rotation before expiry.
2. **A client-credentials grant**, preferring asymmetric client authentication over a shared secret,
   issuing short-lived per-connection scoped tokens whose issuer, audience, expiry and scope are
   validated on every request.
3. **Weaker mechanisms** -- a shared secret over TLS, a per-connection API key, a message-level
   username token -- stay supported for peers that cannot do better, but only with a recorded
   per-connection exception. The value of the record is that the weak connections are a short
   explicit list rather than a discovery.

Across all of them: no cleartext transport for restricted data; credentials in a secret store and
never in code or configuration; least privilege per connection; network-level restriction as
defense in depth.

### Service accounts: no long-lived secret in a file

Run under a least-privilege account whose credential rotates automatically and is never stored in
configuration. Where the platform offers a managed service identity, use it. Where the data store
accepts the service identity directly, authenticate that way rather than with a stored password.

Perform directory lookups only over a TLS-protected channel and fail closed on a cleartext one. The
mechanics are platform-specific; the transferable property is that **no long-lived secret exists in a
file** -- which removes both the most commonly leaked credential and the one whose silent expiry
causes the outage nobody diagnoses.

---

## 9. Tamper-evident audit logging

Produce an append-only, timestamped, actor-attributed audit log with a hash chain over its entries,
so alteration is detectable rather than merely discouraged. Gate reads on it. Keep secrets and
restricted data out of it entirely at informational level and above.

An ordinary application log cannot tell an incident review whether the record was altered. A chained
one can, and it costs one hash per entry.

Where the deployment is exposed beyond a single trusted host, off-box forwarding over TLS is what
stops a compromise of the host from also erasing its own record. Record that as an
exposure-conditional requirement rather than an always-on one, so a local-only deployment is not
described as non-compliant for a control it does not need.

### What happens when the log cannot be written

State the behavior when the audit log is unwritable -- disk full, store unreachable, chain
verification failing -- as an explicit fail-open or fail-closed choice next to the code, and raise an
alert rather than degrading silently. **[prompted by: 800-53 AU-5]** The control supplies the alert
on a logging-process failure and a menu of responses to choose from. The rule that leads here is
[section 7](#7-secure-defaults-and-the-opt-in-that-must-be-explicit)'s -- state fail-open versus
fail-closed next to the code -- applied to the one component whose failure removes the evidence that
anything failed at all, which is why it is prompted by AU-5 rather than a restatement of it.

The trap is specific to a chained log, and it is why this is not an operational detail sitting beneath
the feature. An implementation that drops or truncates entries under storage pressure breaks the
chain, and a broken chain is indistinguishable at review time from one broken by tampering. So the
fallback -- overwrite the oldest records, stop accepting work, or stop generating records -- is part
of the tamper-evidence claim, and it belongs in the same paragraph as the hash chain rather than in a
runbook. The cost is a design decision, one branch and one alert, and it is testable by making the
sink fail.

### Ship the review affordance; the cadence is not yours

A log nobody can read is write-only by construction. The reading obligation is the kind of control
[section 1](#1-shared-responsibility-write-the-split-down-first) exists to stop going unowned: it is
easy for a producer to assume the operator reviews the log and for the operator to assume the log is
reviewed by whoever built it.

Ship the affordance and a labelled retention default. **[prompted by: 800-53 AU-6a, AU-11]** Query
and filter by actor and by time, export in a form another tool reads, and one documented command that
verifies the chain and prints which entry first fails. Ship a default retention period and label it
project-set, because an unbounded default is the reason the log later gets truncated by whoever runs
out of disk. The catalog states the review and the retention period as obligations of whoever operates
the system. The split below is this document's, and the affordance is the producer half it implies.

The review cadence itself, and the definition of what counts as unusual activity in that environment,
belong to the operating organization -- which is why they now have a row in
[section 1](#1-shared-responsibility-write-the-split-down-first)'s table rather than a sentence here.
Not claiming the cadence is the correct outcome under the ownership rule rather than a dodge, and
writing it into the table is what makes that visible. Both are a feature and a constant; neither adds
a blocking gate.

---

## 10. Build and release integrity

This is the part an adopter can check without trusting anything you say about your process, which is
what makes it worth more than the rest of your security page.

### Where the build runs, and who can change it

Everything in the next subsection secures the credential and the artifact. None of it says anything
about the machinery that produced them, or about the list of people and machines that can alter that
machinery. Say who may change the build and who may publish, as an enumeration rather than a policy
sentence.

**The release build runs on an ephemeral runner with no interactive login path, and never on a
developer workstation; an artifact built on one is not publishable.**
**[prompted by: 800-53 SA-3(1)]** The control asks that a preproduction environment be protected
commensurate with risk. Naming the runner, closing the interactive login path, and making an artifact
built on a workstation unpublishable are narrower and stronger than that, and they are this
document's. For most small teams this is already true and merely unstated, because a hosted runner
is ephemeral and has no interactive login by construction. Writing it down is the point: an unstated
property cannot be checked when it later stops being true. What it buys is the removal of the class
where a compromised or merely untidy workstation contributes bytes to a release. It is what makes the
provenance attestation below mean anything, since provenance tracing to somebody's machine is
provenance about nothing. What it does not buy is any defense against a malicious change that was
reviewed and merged.

The workflow definition and every file the workflow sources fall under the same protected-path rules
as release code. A pipeline change must not be able to merge on a weaker gate than the code it
builds, because the build configuration is the part of the repository that can alter every artifact
without altering a line of source.

The publishing capability is held by the workflow identity, and the human publishing path is closed
rather than merely unused. **[prompted by: 800-53 AC-6, CM-5]** Closed is a stronger claim than
least privilege makes. It is the one worth writing down, because a path that exists and is not used
is a path nobody is watching. Two conditions travel with it. Required reviewers on the publishing
environment make the release a second decision rather than a consequence of the merge. And the token
scope is declared per job rather than inherited, so a job that has no reason to publish cannot.

Enumerate every principal that can write to the trunk, administer the repository, or publish, and
review that enumeration on a stated cadence. **[derived: 800-53 CM-5(5)]** Human accounts, machine
accounts, deploy keys, installed applications and their scopes, and registry trusted-publisher
entries. Make it an enumeration for the same reason
[section 2](#2-threat-model-each-trust-boundary-before-you-build-it) makes the boundary list an
enumeration: an entry nobody owns then shows up as a row nobody can explain, rather than as something
nobody thought to look for. The row worth staring at is the rarely-used automation token with publish
scope, which is a larger exposure than the maintainer's own account precisely because it has no
session, no notification and nobody watching it. Delete what is no longer needed at each pass and
date the pass. A dated export of the collaborator, deploy-key, installed-application and
environment-protection settings is the whole of the evidence. The honest caveat for a solo
maintainer: this enumeration will show one human holding everything, which is a finding for
[section 13](#13-deviations-and-risk-acceptance) rather than a control to claim.

Pin every action, image, plugin and tool the pipeline invokes to an immutable digest rather than a
moving tag, and review the pinned set on a stated cadence. **[prompted by: 800-53 SA-15a]** The
control asks that the development tools be identified, their options documented, and the integrity of
changes to them ensured. The immutable digest is one mechanism choice among several, and the review
cadence is in no part of it. The pinned set is the allowlist. The publishing controls below already
pin the one publishing action. The general rule over the whole execution surface is what was missing.
The cadence is the other half of it, because a pin that is never revisited silently becomes an
unpatched dependency. That is exactly why a pinned digest and a blocking dependency-advisory gate are
complementary rather than redundant. State the limit in the same paragraph: pinning establishes that
you got the same bytes as last time, never that those bytes are trustworthy.

These are properties of the release path plus one recurring enumeration; they add no row to the
release gate in [section 16](#16-the-release-gate) and weaken nothing above them. Where one of them
is not true today, closing that gap is the work rather than the waiver.

### Publishing controls, and the limit each one carries

Publishing credentials. Replace long-lived registry tokens with credentials minted per run from the
pipeline's own workflow identity, scoped to a specific repository, workflow and environment, and
valid only for the length of an upload. This removes the leaked-token attack class outright.

Two conditions travel with it. Restrict the publishing workflow to trusted triggers such as a tag or
a push, never to a trigger that grants write credentials to code from an untrusted contributor. And
pin the publishing action.

Per-run credentials do not defend against takeover of the publishing account -- that is what
account-level multi-factor and environment protection rules are for.

**Publishing identity does not cover the artifact.** Establishing that the upload came from your
pipeline says nothing about whether the artifact was modified before or after it was built.

Pair it with a signed attestation binding the distributed filename and its digest to the source
repository, workflow and commit that produced it. Record that attestation in a public transparency
log and serve it alongside the artifact, so a consumer can check it without contacting you. Neither
half is sufficient alone.

**Keyless signing moves the threat model, it does not remove it.** Identity-based signing with
short-lived certificates and a transparency log removes long-lived key management, which is a real
win. It relocates what you defend: multi-factor on the publishing account, branch protection, and
pipeline hardening become the load-bearing controls instead of a key safe.

Where consumers verify on air-gapped or otherwise disconnected networks, bundle the transparency-log
inclusion proof with the artifact so verification does not require network access.

Measure whether a signing scheme is verifiable before crediting it. Coverage and verifiability
are separate questions, and both can be near zero while the scheme is nominally in place.

**[external]** When one large package registry measured its long-standing detached-signature support,
only about a third of signing keys could be meaningfully verified, and signed files were a fraction
of a percent of everything published. Support was withdrawn, and existing signatures are now silently
ignored.

Before crediting a signing control, measure what proportion of artifacts carry a signature and what
proportion of those a consumer can resolve to an identity.

### What an adopter can verify without contacting you

Build provenance. Provenance generated by the pipeline proves the artifact traces to a specific
repository, workflow and commit rather than to somebody's machine. Isolating the build behind a
dedicated reusable workflow raises the assurance level further.

A published digest manifest is the lowest-tech verification path. Make it the documented baseline
rather than the afterthought. Publish a signed digest manifest with every release and document the
exact verification commands, including the offline path. That is the one route a reviewer on an
air-gapped network can always run.

**A component inventory is not tamper detection.** Generate one per release, in the formats your
consumers ingest, and attach it to the release and to the archived build.

Be precise about what it buys: answering "do we ship component X" within minutes of a
widely-publicised advisory, drift detection by diffing a produced inventory against the intended
manifest, and satisfying procurement reviews. It is not integrity evidence for your own code and must
not be quoted as such.

Archive each release with its build inputs and its inventory. Two things depend on it: incident
analysis -- what exactly was in the version somebody is running -- and reproducibility. An archive
holding only the artifact answers neither.

Back up that archive off the platform that hosts it, and restore from it at least once, dated.
**[derived: 800-53 CP-9c]** The archive, the build inputs, the component inventories, the
attestations, the signing and publishing identity configuration, and the deviations register are all
evidence this document tells you to create and nowhere tells you to protect. They typically live in
one account at one provider, so an account suspension or a repository deletion takes the provenance,
the attestations, the archive and the register in a single event -- at which point every claim in
[section 17](#17-what-you-may-claim) becomes unevidenced simultaneously. The restore is the part that
matters: once, dated, restore one archived release and confirm the restored artifact still matches
the digest you published for it. A copy nobody has restored from is a claim rather than a backup,
which is the same defect pattern this document already names for a clean scanner run and for an
in-process integrity check.

Keep the boundary explicit in the same paragraph. This is the producer backing up the producer's own
evidence. Backups, disaster recovery and availability for a deployment stay in the right-hand column
of [section 1](#1-shared-responsibility-write-the-split-down-first), unchanged. So this reaches the
evidence archive and not a deployment's data: do not write it up as covering backup and restore.

**What leaves the build must be only what was intended.** Declare an explicit allowlist of what the
published artifact contains, gate on it before the upload step, and verify the published artifact once
after release, because checking what you built is not checking what shipped.

The rule and its failure mode are stated in full under *Package manifests are allowlists, not sweeps*
in [CI and standards](../CI-AND-STANDARDS.md). The case worth naming here is that material a project
treats as withheld can travel inside a published distribution without anyone reviewing the packaging
list.

### Obfuscation is not the control you are looking for

For code whose source is published, obfuscating or compiling the shipped artifact protects nothing
that matters. There is no confidentiality to preserve, and the tamper resistance gained is marginal.
Where a copyleft license requires corresponding source, an obfuscated build also creates friction with
that obligation.

The vendors concede the limit themselves. One obfuscation product's own documentation states it is
not good at memory protection or anti-debug. The same documentation says its runtime-data protection
holds only if the interpreter and its runtime extension are not compromised -- a condition a
privileged attacker defeats by definition.

One native compiler's documentation concedes that its default single-file mode is a self-extracting
archive whose contents land on disk for inspection. Bytecode-only distribution is trivially
decompiled and patched.

**The rule that survives all of it: a protection scheme that must run inside the process it protects
assumes an uncompromised runtime, which is exactly the assumption a privileged attacker breaks.**
Spend the budget on verification instead -- provenance, attestation, inventory, digests -- because
that is what a reviewer can actually check.

If you do ship a hardened build, position it as raising analysis cost, never as tamper-proof, and keep
secrets and authorization decisions out of any artifact an adversary holds.

---

## 11. Runtime tamper resistance, and the bootstrap-trust limit

An application that hashes its own files against a signed manifest at startup detects accidents and
unsophisticated tampering and produces an audit signal. That is worth having, and it is all it is.

It cannot be more, because **the checker runs in the same trust domain as the thing it checks**.
Anyone who can edit the code on disk can also edit the manifest, the embedded key, or the verification
routine. Anyone who can alter the runtime can stub it.

The chain of trust only terminates in hardware measured boot, which is a platform decision the
operator makes and not something the software ships. Ship the check as defense in depth, document the
limit in the same paragraph as the feature, and never let it be quoted as prevention.

State the honest objective. On a host where the adversary has administrative privilege, every
application-level control is ultimately defeatable -- agents can be disabled, baselines altered, the
runtime patched, behavior hooked at load time. Say so explicitly rather than letting the control list
imply prevention.

What is achievable is to make tampering noisy, costly and detectable, to produce audit evidence, and
to push the trust root as low as the operator is willing to go.

### Operator-owned hardening: document and recommend, never claim

These controls are all stronger than any application-level control named above, and none of them are
yours:

- file-integrity monitoring against a baseline
- immutable or read-only deployment with writable state confined to the data store
- least-privilege file ownership so the running account cannot rewrite its own code
- confinement under a mandatory access control system
- signed-artifact admission control that rejects anything unsigned

Ship a hardening guide with a concrete list of paths to monitor and example rules, so the operator has
something to apply on day one rather than a category name.

### Roll out a blocking verification control in audit mode first

A control that rejects artifacts failing verification will also reject valid artifacts whenever its
own preconditions are unmet -- for instance when the enforcing component cannot reach the store
holding the signatures it must fetch.

Start in audit mode where it reports but does not block, confirm it is resolving what it needs, then
switch to enforce. The alternative is a rollout that blocks legitimate deployments on day one and gets
switched off permanently as a result.

---

## 12. Vulnerability response, exercised

A response program is a process control, not a document. It needs:

- A defined private intake channel.
- Severity-banded remediation windows.
- A root-cause review for significant findings, feeding systemic causes back into the standard.
- Coordinated disclosure after a fix exists.
- **The machinery exercised end to end at least once, as a dry run.** This is the part usually
  missing, and it is the part that finds the broken intake address before a real reporter does.

State when the clock starts, next to the window. The two obvious choices give very different numbers.
Measuring from your own triage is right for your own defects. Measuring from the point an upstream
fixed version exists is right for a third-party advisory, because a clock started at triage runs
against something you cannot act on.

Pick per finding class, say which, and track the waiting period itself, so an unfixable advisory is
visible rather than silently blowing a window.

### What actually closes a finding

**A finding is closed by the check that produced it going green on the commit containing the fix --
not by the fix merging, and not by a later full-suite run being green.**
**[prompted by: 800-53 SI-2b]** The control asks that remediation be tested for effectiveness and for
side effects before installation. Naming the originating detector as the thing that has to change its
verdict is narrower than that, and no catalog states it as a requirement -- it is this document's.
A merged fix is a change with an intention attached to it. A green suite establishes that the suite
passed; it does not establish that this finding's detector ran and changed its verdict. Those are two
different sentences, and only the second one closes anything.

**The confirming run has to be a mirror copy of the original: same check, same ruleset, same scope.**
**[derived: 800-115 section 8.3]** A fix confirmed by a differently-configured run has not been
confirmed. This is the failure mode
[section 5](#5-scanner-posture-what-blocks-what-advises-what-may-never-be-waived) already names for
baselines: zero findings on a weak ruleset proves nothing. Applied to the closing run instead of the
opening one, it is the part that makes a retest mean anything rather than being a second green badge.

Record three fields per closed finding: the finding identifier, the fix commit, and the identifier of
the confirming run. The third field is the one carrying the weight, because a reviewer can resolve a
run identifier to a verdict and cannot resolve the word "fixed" to anything at all.

Two ways this fails. Both are common enough to name rather than leave to inference.

The fix merges and the check is never re-run, because the check that produced the finding only fires
on a schedule. For anything caught by a blocking check the retest is automatic by construction and
this rule costs nothing -- most of the value is simply in saying that this is what closure means. The
manual work is entirely in the scheduled and advisory jobs, which are precisely the ones nobody
re-runs on purpose.

The finding is closed by adding a suppression. Under [section 16](#16-the-release-gate) a suppressed
rule class is a control that has been turned off, so a suppression routes the finding into the
suppression review and never into the closed column. Without that clause stated outright, this rule
makes the closure count look better while making the posture worse -- which is the exact species of
badge the anti-metrics table in
[section 5](#5-scanner-posture-what-blocks-what-advises-what-may-never-be-waived) exists to catch.

Every finding therefore ends in exactly one of two places: closed by retest, or held under a dated
signed acceptance in [section 13](#13-deviations-and-risk-acceptance). A finding in neither is an open
item wearing the costume of a closed one.

The cost is three fields in a tracker you already have, plus a re-run that was going to happen anyway,
so this adds no row to the release gate. It is
*[fire the failure class at the gate before crediting its green](#5-scanner-posture-what-blocks-what-advises-what-may-never-be-waived)*
from [section 5](#5-scanner-posture-what-blocks-what-advises-what-may-never-be-waived), applied per
finding rather than per control.

Measure time-to-remediate against the windows you set. **[derived: 800-53 SI-2(3)]** Record the
identification date and the remediation date per finding, and compare the distribution against your
stated windows the next time you set them. A window you have never measured against is a number you
picked, and this document already forbids treating a picked number as a threshold -- so whatever the
data suggests, the resulting window stays labelled project-set and directional. This is also where the
waiting period on an unfixable upstream advisory finally gets recorded, rather than being a discipline
with nowhere to live.

### The producer half: an intake a reporter can find, and an advisory a tool can read

[Section 1](#1-shared-responsibility-write-the-split-down-first)'s split already puts vulnerability
response and disclosure in the producing project's column, opposite monitoring, patching and incident
response in the operating organization's. The right-hand half is written down. The left-hand half is
the list at the top of this section, and that list says the machinery must exist without saying what a
reporter or an adopter ever sees of it. Three things are what they actually encounter, and two more
are decisions that show from outside only by never having been made.

Publish the address of the private intake channel where a reporter will look, and state what happens
next. What is published is where to send a report, never the reports: the channel stays confidential,
per the list above, and only its address and its terms are public. Publish, at least:

- a security contact at a documented address
- a policy file in the repository where the source host surfaces it
- a stated acknowledgment time

Say what you will not do in the same place: no payment, no bounty, no timeline beyond the bands, and
whether a reporter is credited. An unstated expectation is where a coordinated report becomes a public
one. Requiring an account, a login or a form to file is the same defect as an unmonitored address: a
channel that exists and does not work. The dry run in the list above is the only thing that
establishes it does.

Publish the windows with the clock start next to each one. The bands are required above, and so is
stating where the clock starts. The addition is that the published version carries both, because a
window whose start point is unstated cannot be missed and is therefore not a commitment. Label them
project-set, per this document's position that no framework supplies a validated number.

Ship an advisory per fixed vulnerability, on a channel machines read. A changelog line is not an
advisory. Nothing in an adopter's tooling reads prose, so a fix announced only that way reaches the
adopters who happened to be reading. Publish at least the affected versions and the fixed version, the
impact in one sentence, whether a configuration change mitigates it without upgrading, and a stable
identifier. Where the ecosystem has a public advisory database or an identifier authority, file there
too: that is the step that puts the entry into the feeds a blocking dependency audit consumes, and
[dependency and artifact integrity](DEPENDENCY-INTEGRITY.md) covers that consuming half in full.
Issuing one is the same act seen from the producing end, and the asymmetry is worth naming. It is the
common state: a project can be rigorous about every advisory it reads and have never written one.

Decide the threshold for what gets an advisory, and write it down. Not every security-relevant fix
warrants one. A project that has issued none has usually never decided rather than decided not to, and
those two look identical from outside.

Set a maximum embargo, so coordinated does not become indefinite. Disclosure after a fix exists is
already required above. What it leaves open is the fix that never quite lands and the report that is
therefore never published, which is [section 13](#13-deviations-and-risk-acceptance)'s
permanent-excuse shape in different clothes. State the point at which you publish with or without a
fix, including the mitigation if that is all there is.

Two honest limits. **An advisory tells an adopter a fix exists. It does not deploy it.** Released is
not deployed, deploying is the right-hand column of
[section 1](#1-shared-responsibility-write-the-split-down-first)'s table, and writing the advisory as
though issuing it discharged anything over there is the over-reach that table exists to prevent. And
**this is a producer's disclosure path, not an incident response program.** Incidents are generated
by running the software. The coverage table below records the catalog's incident-response family as
not addressed here and gives the reason, and nothing in this subsection changes it.

Recommended: published artifacts and a stated policy. The end-to-end dry run that already has to
happen once is where this gets exercised -- file a test report into the intake, take a test advisory
through the announce path. It adds no second rehearsal and no row to the release gate in
[section 16](#16-the-release-gate).

---

## 13. Deviations and risk acceptance

Where current practice differs from what the standard requires, write the deviation down rather than
quietly redefining the requirement. Each entry carries four fields:

| Field | Why |
|---|---|
| The control not met, and the date the risk was accepted | An undated deviation cannot be aged |
| The compensating controls actually in force | Distinguishes a decision from a gap |
| The trigger that ends it | A deviation with no trigger is a permanent excuse |
| A pointer to where the intended shape is written down | So the fix is designed, not improvised later |

One entry filled in, for an invented single-maintainer project. Illustrative only: it describes no
real project, the date is made up, and it is **not this document's own register** -- publishing that
is what the rule two paragraphs below forbids. The shape is the point; read nothing about anyone's
posture out of the contents.

| Field | Entry |
|---|---|
| The control not met, and the date the risk was accepted | Peer review by a second reviewer, accepted 2026-01-15 |
| The compensating controls actually in force | Blocking static analysis and dependency audit that cannot be waived, AI-run review a human arbitrates, branch protection with required checks, and no direct pushes to the trunk -- each listed only where it is actually in force |
| The trigger that ends it | A second maintainer joins |
| A pointer to where the intended shape is written down | [Section 4](#4-review-and-what-to-do-when-there-is-no-second-reviewer), including the constraint that this set is described as a compensating control and explicitly not as an independent audit |

**Only a dated, signed acceptance is governance.** A register of accepted risks is not, on its own. An
unsigned acceptance is an un-accepted open gap wearing the costume of a decision, and a release gate
that leans on one is not a gate.

**Publish the rule, not the inventory.** A register enumerating which controls are currently absent,
which are off by default, and what is holding each one safe is an operational document with a narrow
audience. Keep it. Do not publish it, and do not reconstruct it in generalized form -- a generalized
list of the places a class of software is typically weak is the same artifact with the names filed
off.

**Mark added practices as recommended, and say they add no blocking gate.** When you grow a standard,
state each addition's normative force explicitly and say in the same paragraph that it introduces no
new blocking release gate and weakens no existing requirement. Additions without that marking either
get treated as mandatory and stall adoption, or get ignored and quietly hollow out the document.

---

## 14. Re-evaluate on a trigger, and on a short calendar for what has no trigger

Every gate in this document is release-triggered. A project that ships nothing for a year runs no
security review in that year. Three of the ways a control degrades to nothing leave no trace a
per-change gate would ever see: a suppression added, a job flipped from blocking to advisory, and a
deviation whose ending trigger fired while its compensating control quietly became the permanent
state.

Run a recurring pass on a stated cadence. **[derived: 800-53 CA-7b]** It does exactly four things, and
the count is a cap of this document's own rather than anything the catalog asks for:

1. Sweep the deviations register for entries whose ending trigger has already fired, and for entries
   not reviewed since the last pass.
2. Re-confirm from the blocking-job list, not from a badge, that every check in the unwaivable set
   still blocks.
3. Confirm the scanner suppression list has not grown unreviewed.
4. Check whether a trust boundary now exists with no threat model.

Set the cadence yourself and label it project-set, consistent with this document's position that no
framework supplies a validated threshold. The evidence is a dated entry per pass recording what was
checked and what changed, which is also what gives the deviations register the ageing it needs to be
more than a list.

Hold it to four. A periodic pass in a small team dies by growing. Somebody adds a fifth item and a
sixth, the pass stops being run, and an unrun scheduled control is worse than an absent one because it
still looks green from outside. The cadences named elsewhere -- the principal enumeration and the
pinned tool set in [section 10](#10-build-and-release-integrity) -- are their own schedules against
their own artifacts, and folding them in here is the growth this rule exists to forbid.

Prefer an event trigger to the calendar wherever an event exists. A trigger tied to a change fires
when the answer actually changed, and leaves the diff as its own evidence. A calendar reminder is the
first thing dropped in a busy month. The data-class table in
[section 1](#1-shared-responsibility-write-the-split-down-first) is the clearest case, which is why it
is event-triggered rather than a fifth item here. It is amended when a change adds a data class, gives
an existing class a new resting place, or adds a boundary.
[Section 16](#16-the-release-gate)'s gate carries the matching row.

State the normative force plainly, because it is not uniform across this section. The four-item pass
is a recurring practice and blocks nothing. The event trigger on the data-class table does add one row
to the release gate in [section 16](#16-the-release-gate) -- the only new gate row this material
introduces -- and it is a row answerable from a diff rather than from a judgment.

---

## 15. Independent external verification

**Third-party source review and penetration testing are the only controls an internally-run pipeline
cannot substitute for.** **[prompted by: 800-53 CA-8(1)]** Their absence caps what you can honestly
claim, no matter how good the automated layer is.

Dynamic testing was named in that sentence in an earlier version of this material, and has been
removed from it. That was wrong, and it mattered: it let a reader believe dynamic testing was
unavailable without funding. A developer-run malformed-input harness costs runner minutes rather than
money, [section 2](#2-threat-model-each-trust-boundary-before-you-build-it) describes it, and
[section 5](#5-scanner-posture-what-blocks-what-advises-what-may-never-be-waived) says when it runs.
It is weaker than an external engagement, not out of reach without one, and both halves of that go in
together.

### Write the engagement down before it starts

Scope the engagement in writing, and have it reviewed and approved before work begins.
**[derived: 800-53 CA-2b, CA-2c]** The plan names what is under assessment, the procedures to be used
to determine whether a control is effective, and the environment, the team and the roles. The ordering
is part of the requirement rather than a nicety: approved prior to conducting, not written up
afterwards from what happened.

Agree the rules of engagement with the other side, countersigned, before testing commences.
**[derived: 800-115 Appendix B]** The template that survives:

- the objective, and what is explicitly out of scope
- the environment and the authorized test site
- the artifacts you hand over up front -- threat models, architecture, previous assessment results,
  the deviations register
- named points of contact on both sides, including the incident-response contact
- permitted testing hours
- the risks and their agreed mitigations
- what data the tester may encounter, and how it must be handled and destroyed
- how findings are delivered and disclosed

The data-handling clause is the one teams skip and the hardest to repair afterwards. Testing can
expose to an outside party information held under a regime the adopting organization operates under,
and the rules of engagement are where the handling and destruction expectations get written down.
[Section 1](#1-shared-responsibility-write-the-split-down-first)'s data-class table is what you hand
over to make that clause specific rather than generic.

An unscoped engagement produces a report you cannot use. A finding whose scope was never agreed cannot
be traced to a boundary in [section 2](#2-threat-model-each-trust-boundary-before-you-build-it), and
it cannot be closed under the retest rule in
[section 12](#12-vulnerability-response-exercised), because there is no agreed original run for a
confirming run to mirror. Independence is the other half: an engagement run by a party with no stake
in the result is what distinguishes this from the self-assessment
[section 17](#17-what-you-may-claim) forbids conflating with it.

Write this even if the engagement is never funded. Scope is what an engagement is priced on, so
writing it before soliciting quotes is the difference between comparable bids and a surprise. And
[section 13](#13-deviations-and-risk-acceptance) requires holding the unfunded gap under a dated
signed acceptance, where an acceptance naming what would have been in scope is a far stronger record
than one saying testing was not performed. It adds no row to the release gate; it makes the row
already there answerable.

Where the engagement has not happened, say so plainly and hold the gap under a dated signed
acceptance. Do not let a self-assessment read as verification, and do not omit the cost context.

A bare "not yet performed" with no explanation reads as negligence. But "not yet performed, and here
is the order of magnitude it would cost" reads as a funding constraint a reader can evaluate.

Do not gate somebody else's deployment on your engagement. For software an adopter self-hosts, the
decision to deploy and the assessment supporting it belong to the adopting organization. Record what
has and has not been independently verified; do not assert authority over a rollout you do not
control.

This is a correction to an earlier version of this material, which stated the independent review as a
precondition for production exposure -- an over-reach for software the producer does not operate.

If you are running a formal assessment against a published verification standard, the method for it is
covered in [running a large security-standard assessment with AI agents](../ASVS-ASSESSMENT.md). That
covers:

- verdict vocabulary
- why `unverified` must never read as a pass
- evidence anchors a machine can re-check
- pinning the standard's corpus
- how to read a movement in a score

Do not build a second procedure beside it.

---

## 16. The release gate

Codify the gate as an explicit pass or fail list rather than a judgment:

- Automated blocking checks passing on the exact commit being released.
- No unresolved high or critical findings.
- Current independent-review status, or a signed risk acceptance standing in for it.
- Updated evidence.
- A signed artifact with its component inventory and digest manifest attached to the tag.
- [Section 1](#1-shared-responsibility-write-the-split-down-first)'s data-class table current as of
  the last change that added a class, gave a class a new resting place, or added a boundary.

Two constraints on reading it. **The gate must not lean on an unsigned acceptance**, or it is not a
gate. And **no single row is the gate on its own** -- the composite is.

One caveat belongs next to it permanently: "no unresolved high or critical" is only as honest as the
scanner baselines behind it. It says nothing if the baseline was set on a weak ruleset, or if advisory
jobs were miscounted as gating coverage. Verify enforcement from the blocking-job list, not from a
green badge -- see *A check that cannot fail is not a control* in
[CI and standards](../CI-AND-STANDARDS.md).

### Confirm the control plane before reading any code

Confirming the control plane is a separate pass from reading code, and it comes first. For each
required check, confirm three things and read no source: that it exists, that it blocks rather than
advises, and that it was green on the exact commit being released. The release change's own pipeline
run is the control plane executing.

Review the scanner suppression list explicitly rather than accepting it, because a suppressed rule
class is a control that has been turned off. A finding closed by adding a suppression is not a closed
finding, and it lands in this review rather than in the closed column --
[section 12](#12-vulnerability-response-exercised) carries that rule in full. Mark which
nominally-security jobs are advisory and do not count those as coverage. Only then spend line-by-line
reading on what the automated controls cannot cover.

---

## 17. What you may claim

The register you have is **built to**, **aligned with**, and **self-assessed against**, each backed by
evidence, and each a claim about this document and your own process. You do not have
**certified**, **verified**, or **compliant**, and writing one of those is the fastest way to have the
whole page discounted.

The register does not extend to a publication you cited. "Aligned with" is available only against
a named control identifier -- "this practice corresponds to SP 800-53 Rev. 5 control SA-11(8)" is a
claim a reviewer can check against one paragraph of one publication. Against a publication as a
whole it is unavailable, in either direction: not "aligned with SP 800-53", which claims a catalog of
a thousand controls nobody assessed, and not "built to SP 800-218", which is the same defect wearing
the register's own vocabulary and is close to the wording a federal secure-software attestation turns
on. Naming four publications on this page does not enlarge what may be claimed at the
bottom of it; the reasoning is in *Naming these sources is not a conformance claim* and is not
repeated here.

The general rule, with the honesty-state tagging and the claims register that goes with it, is in
[CI and standards](../CI-AND-STANDARDS.md). Four things are specific to a security claim:

- State the attestation posture positively, with its scope named. "This project attests that it
  builds under this standard" is a claim you can support. "The output is independently audited" is
  not, unless it is.
- Say what the standard does not confer, structurally and near the top. It confers no compliance,
  certification, or fitness on the product, on you, or on an adopter, and it does not substitute for
  an adopter's own assessment. That is a statement about scope, not a disclaimer.
- Where you borrow discipline from a regime you are not subject to, say so. Adopted by analogy and
  voluntarily; producing the artifacts confers nothing.
- Never restate another document's assurance-level target, count, or score. Two documents that
  each restate the other's target will eventually disagree, and both will look authoritative. Name the
  record of record and link to it, so there is exactly one place that can be wrong.

That last one is the state-it-once rule applied to the one class of fact where being wrong is most
expensive.

Cite a proposed requirement as proposed. Where a standard or regulation is under revision, a draft
that has not been finalised is never a current requirement, and the frame is "if finalised" every time
it appears. Record the date you last checked its status -- that check is what goes stale, not the
citation.

---

## In one table

| When | Rule |
|---|---|
| Starting | Write the producer-versus-operator split before claiming any control |
| Starting | Define restricted data once, as a table of classes and every place each one rests |
| Starting | List the services neither column owns, and what fails if one goes away |
| Designing | Threat model each trust boundary before the build; name a mitigation for each way in |
| Designing | Draw the boundary list; a diagram with no boundaries marked on it is not a security artifact |
| Designing | Bound resource consumption per boundary; an unbounded boundary is a finding |
| Designing | At an execution boundary, check every caller reaches it, not the documented one |
| Coding | Validate at ingress, parameterise every query, confine every path, fail closed |
| Reviewing | Self-review is a documented deviation, not a satisfied control |
| Reviewing | Name the compensating set and the event that ends the deviation |
| Gating | Coverage is the blocking checks that run on the change, not the tool count |
| Gating | A clean run is a start condition for red-on-regression, never a certificate |
| Gating | Fire the failure class at the gate before crediting its green |
| Gating | Trigger a dynamic pass on an event; when no trigger fires, record that nothing ran |
| Gating | Encode a control as one shared check across sibling paths |
| Gating | Record rigor and scope separately per blocking check; one green hides both |
| Configuring | Secure by default; every insecure posture is a named, audited, fail-closed opt-in |
| Configuring | Off-by-default and fail-closed are different states -- describe them apart |
| Configuring | Synthetic data outside production; live data raises the environment, not lowers the class |
| Configuring | Rate a collection by the highest class in it, never the average or per entry |
| Authenticating | Strongest mechanism the peer supports, recorded per connection |
| Authenticating | No long-lived secret in a file; no cleartext directory bind |
| Logging | Append-only, hash-chained, actor-attributed; no secrets or restricted data at info level |
| Logging | State what happens when the log cannot be written; a broken chain reads as tampering |
| Logging | Ship the query, export and chain-verify affordance; the review cadence is the operator's |
| Releasing | The release build runs on an ephemeral runner, never on a developer workstation |
| Releasing | Pin every action, image and tool by digest, and review the pinned set on a cadence |
| Releasing | Enumerate every principal that can write, administer or publish; review and prune it |
| Releasing | Short-lived workflow-bound publishing credentials, paired with an attestation over the digest |
| Releasing | Publish a signed digest manifest and document the offline verification path |
| Releasing | A component inventory answers "do we ship X" -- it is not tamper detection |
| Releasing | Archive the artifact, its build inputs, and its inventory together |
| Releasing | Verify the published artifact after release; what you built is not what shipped |
| Releasing | Back up the evidence archive off-platform, and restore one release to prove it |
| Hardening | An in-process integrity check detects accidents, never a privileged attacker |
| Hardening | Operator-side controls are documented and recommended, never claimed |
| Hardening | Roll out a blocking verification control in audit mode first |
| Responding | Rehearse the response program end to end; state where each clock starts |
| Responding | Publish the intake, the bands and the clock start; an unmonitored address is not a channel |
| Responding | Ship an advisory per fixed vulnerability where tooling reads it; a changelog line is not one |
| Responding | A finding closes when its own check goes green on the fix commit, not when the fix merges |
| Responding | The confirming run is a mirror copy; a suppression is a suppression, never a closure |
| Responding | Measure time-to-remediate against the windows you set, then label them project-set |
| Accepting risk | Dated and signed, with a trigger that voids it. Unsigned is an open gap |
| Accepting risk | Publish the rule, not the inventory of what is currently absent |
| Re-evaluating | Four items on a stated cadence; hold it to four or nobody runs it |
| Re-evaluating | Event-trigger the data-class table instead of adding a fifth calendar item |
| Verifying | Scope an external engagement in writing, countersigned and approved before work starts |
| Shipping | The gate is a list with a defined failure mode, and no single row is the gate |
| Shipping | Confirm the control plane -- present, blocking, green on this commit -- before reading code |
| Claiming | Built to, aligned with a named control, self-assessed against -- of your own process, never of a cited publication |
| Claiming | Never certified, and never aligned with a publication as a whole |
| Claiming | Never restate another document's target or score; link to the record of record |

---

## Adapting this to your project

Change freely:

- The section set. Drop what you do not have. A project with no network interfaces does not need
  [section 8](#8-machine-to-machine-authentication), and saying so beats leaving an empty heading
  that reads as an unowned control.
- The authentication hierarchy. It is ordered by what a peer system can support, and yours will
  differ. Keep the property -- strongest available, recorded per connection, weak ones as an explicit
  short list -- and replace the mechanisms.
- The remediation windows. There is no validated number. Set yours from your own capacity, record
  them where a reporter can read them, and label them project-set.
- Everything platform-specific. Managed service identities, transparency logs, admission control
  and integrity monitoring all have different names and different guarantees per platform. Name the
  one you use rather than implying the pattern is universal.
- The adoption order. Sections 1, 5 and 13 are the cheapest and the highest-leverage; after those,
  take whatever your riskiest surface demands.

Do not weaken:

- **The ownership split, in either direction.** Claiming an operator-side control is over-reach.
  Pushing a producer-side control onto the operator is abdication.
- **The single definition of restricted data.** One table in
  [section 1](#1-shared-responsibility-write-the-split-down-first), and every other rule points at
  it rather than carrying its own adjective. Two terms for one idea is how a rule ends up enforced in
  one section and quietly absent from its sibling, and the fix is to delete the second term rather
  than to define it as well.
- **The unwaivable set.** Static analysis, dependency analysis and secret scanning block, and an
  author cannot waive their own change past them. The moment one becomes waivable it stops being a
  control and becomes a preference.
- **The deviation format.** Dropping the date makes it unageable; dropping the trigger makes it
  permanent; dropping the signature makes it an open gap. All three fields or none of it counts.
- **The claim register.** "Certified" is not a stronger synonym for "self-assessed against". It is a
  different and false statement, and it is the one a reader will check.
- **The honest limit next to each control.** Each of these is a compensating control resting on a
  false premise: an in-process integrity check that is described without the bootstrap-trust limit, a
  component inventory described as tamper detection, or a self-assessment described as verification.
  The next person to touch it reasons from your description rather than from the code.

---

## Where the rules come from

Most of what this page states is this document's own reasoning about what a small producing team can
actually execute. Where a rule was borrowed, it was borrowed from, at least, these. Each
publication's status, its date, and the date that status was last checked are in
[Sources](#sources) at the bottom, in one table and nowhere else, so a status re-check is a
single-table edit rather than a sweep.

- NIST SP 800-218 v1.1, Secure Software Development Framework (SSDF). The only one of these
  written for a software producer rather than a system operator, so it is the outcome layer: it
  states things like dynamic testing of the built artifact and a secure build environment as outcomes
  the producer owns. No rule on this page carries an SSDF mark, and that is deliberate rather than an
  oversight. Where a rule restates one of those outcomes, the specific text it restates was read in
  an 800-53 control, and a mark points at the publication whose text was actually opened. The sources
  table records which practices sit behind which rules.
- NIST SP 800-53 Rev. 5, Security and Privacy Controls for Information Systems and
  Organizations, as maintained by Release 5.2.0 (2025-08-27). It supplies the specific, quotable
  control text where the SSDF states only an outcome, cited by control identifier. Always name the
  release -- see the version trap below.
- NIST SP 800-115, Technical Guide to Information Security Testing and Assessment. Cited here for
  its process material only -- the rules-of-engagement template for an external engagement, and the
  caveat that a retest verifies a fix only if the confirming run is a mirror copy of the original. It
  is eighteen years old; its technique and tooling inventory is not current and nothing here borrows
  from it.
- FIPS 199, Standards for Security Categorization. One page of vocabulary: three security
  objectives against three impact levels, plus the high-water-mark roll-up for a collection.

Name the release, not just the revision, and record the date you checked. "SP 800-53 Rev. 5"
today names two artifacts that disagree. The PDF served under that title carries content dated
September 2020 with updates as of 2020-12-10. Release 5.2.0, issued 2025-08-27, adds SA-24,
SI-02(07) and SA-15(13) and revises SI-07(12) -- none of which can appear in a document whose
content predates them -- while the file name and the title are unchanged. So a citation reading
"SA-24, SP 800-53 Rev. 5" is simultaneously correct and unresolvable by a reader who downloads the
publication. Every 800-53 citation here is to Release 5.2.0 as checked on the date recorded in the
sources table, and names a control present in the served PDF. The sibling rule for any revised
publication: carry the revision number as well, because a bare identifier can resolve to a superseded
or withdrawn document that still says something plausible.

**Naming these sources is not a conformance claim, and cannot become one.** They are sources this
document draws on. It claims conformance with none of them, and none of them certify anything --
no publication in that list issues a certificate, and a self-assessment is not one either. Quoting
a control's text is not a claim of conformance to the catalog it came from. The wording that
survives a reviewer is "this practice corresponds to SP 800-53 Rev. 5 control SA-11(8)" -- a named
control, checkable against one paragraph of one publication. Which wordings fail, including the ones
that name a publication rather than a control, is [section 17](#17-what-you-may-claim)'s register;
it is stated there once and is not repeated here. For 800-53 in
particular the catalog's own notion of conformance is a selected control baseline plus an
authorization decision, and a software producer makes neither. So the baselines, the tailoring
apparatus and the risk management framework built around the catalog are all out of scope here.
Only named control text is borrowed.

How borrowings are marked. The default is inverted from a compliance matrix: an unmarked rule is
this document's own, and only a borrowing carries a mark. `**[external]**` is empirical evidence --
a study, a measurement, a vendor's own concession. `**[derived: <code>]**` means the rule is a
published requirement, restated for this audience. `**[prompted by: <code>]**` means the source
raised the topic and the rule as written is ours, being stronger, narrower or different. The test
that decides between the last two: if the source changed, would this rule change? Yes is
derived, no is prompted-by, and no source at all is unmarked. A mark attaches to the rule -- the
lead sentence, or the bullet -- never to the prose arguing for it, so the explanation, the
honest limit and the cost sitting inside a derived rule stay unmarked, because those are ours.

### Full conformance is not on offer, so tailoring is not a compromise

The SSDF has no conformance criteria, no levels and no assessment procedure. Nothing issues a
pass. So the familiar advice -- aim for a tailored, risk-based subset rather than one hundred
percent conformance -- understates the position. Full conformance is not a thing that exists to be
aimed at. The framework states outcomes a producer should achieve and leaves the how open, and its
implementation examples are illustrative rather than required.

What that does not license is dropping a practice. Tailoring here happens at the implementation
layer -- which mechanism satisfies an outcome -- far more than at the practice layer. A practice
rarely stops applying because of a technology choice. A memory-safe language changes which
vulnerability classes you face, and therefore how you satisfy the code-analysis and testing
practices; it does not remove them. Treating a language feature as grounds to skip a practice is the
specific error this subsection exists to prevent.

The artifact of tailoring is a written record of what you left out and why. This document already
produces one: the `NOT ADDRESSED` rows of
[the coverage table](#what-this-document-does-not-take-from-a-control-catalog), each carrying a
reason rather than an apology. An exclusion nobody wrote down is indistinguishable later from an
oversight, and the reason is what a reader needs in order to disagree with you.

### The one setting where such a claim is a legal instrument, and its expiry date

There used to be a clean answer to when conformance actually binds a producer: selling software to
the US federal government. Executive Order 14028 led to OMB Memoranda M-22-18 (2022) and M-23-16
(2023), which required agencies to obtain a secure-software-development self-attestation from
producers, on a common form published by CISA in March 2024.

That government-wide requirement was rescinded on 2026-01-23 by OMB Memorandum M-26-05, which
states that M-22-18 and M-23-16 "are hereby rescinded". Agencies "may choose to use" the attestation
form; none is required to collect it. The SSDF survives in that memo as a resource agencies "can
reference", not as a mandate, and agencies must still maintain a complete software and hardware
inventory and set assurance requirements matching their own risk determinations.

Two things follow, and they pull in opposite directions.

- Advice written before 2026 saying you must sign the common form to sell federally is now wrong,
  and that advice is still widely in circulation.
- **This is not a relaxation.** The memorandum moves the obligation onto each agency head and says
  there is no one-size-fits-all method. An individual agency may still require an attestation by its
  own policy or contract. Read as a loosening, it is being read backwards.

The stated reason is worth reading if you are deciding how much rigor to adopt. OMB wrote that the
prior approach "imposed unproven and burdensome software accounting processes that prioritized
compliance over genuine security investments" and "diverted agencies from developing tailored
assurance requirements". That is the argument of the subsection above, made by the party that had
imposed the mandate.

**What did not change is the exposure on any attestation you do sign.** A signed attestation is a
representation to a customer, and in the federal setting a false one carries civil fraud exposure
whether or not anyone required it. The rescission removed a requirement to make the statement. It did
nothing to the consequences of making a false one.

*Memorandum text read directly and verified 2026-08-06; see the sources table for how this status is
carried. A compliance fact without a date is a claim with a hidden expiry, and this one replaced a
four-year-old regime.*

---

## What this document does not take from a control catalog

A reader who arrives holding the SSDF or SP 800-53, rather than at the top, has two ways in. For what
was borrowed, the marks in the body are the index: each names the control it came from, so a search
for a control identifier lands on the rule that restates it, inside the section that argues for it.
The sources table below records which publication contributes what. This table is the other half, and
the half nobody writes down: the areas a control catalog covers that this document deliberately takes
nothing from, and why. An absence then reads as a decision rather than an oversight, and a reader
holding a catalog can stop looking.

It is not a coverage map, and there is nothing here to score. A row means this document has declined
to say something about that area. Nothing here claims the document satisfies a control, that a
product built under it satisfies one, or that either could be assessed against the catalog an
identifier came from. [Section 17](#17-what-you-may-claim) carries the claim register, and *Naming
these sources is not a conformance claim* in
[Where the rules come from](#where-the-rules-come-from) carries the reasoning; neither is repeated
here.

There is deliberately no table mapping this document's rules onto a catalog's controls. A reader
would read one as a scorecard whatever it said about itself, control identifiers being unusually
quotable, and a count of them already sits in
[section 5](#5-scanner-posture-what-blocks-what-advises-what-may-never-be-waived)'s anti-metrics
table as a badge that measures nothing. Most of what such a table would have held is stated once
already, in the body, at the rule.

The 800-53 rows name controls as they stand in Release 5.2.0, per *Name the release, not just the
revision* above. And an absence from this table is not a claim in either direction: the area may have
been borrowed from, in which case a mark in the body says so, or it may simply be one nobody has
asked about yet.

| Control or practice | What it asks for, in one line | Why nothing here is taken from it |
|---|---|---|
| 800-53 AC-5 | Separation of duties, divided among individuals | NOT ADDRESSED, structurally. It requires two qualified individuals. Section 4 models the correct treatment of a control a small team cannot meet: name the control, record the deviation, name the compensating set actually in force, and name the event that ends it -- never redefine the control until it fits |
| 800-53 AT family | Security awareness and role-based training, with completion records | NOT ADDRESSED. Section 4's comprehension bar -- reject code you cannot explain -- is the right-sized substitute and is already there. A training program with completion records beside it would be a second record of the same obligation, which is what section 17's name-the-record-of-record rule exists to prevent |
| 800-53 AU-9(1), AU-10 | Write-once media for audit records; non-repudiation | NOT ADDRESSED. The hash-chained log in section 9 is the right assurance level for this audience. Write-once media and public-key-backed non-repudiation are operator infrastructure whose cost is orders of magnitude above the threat a small producer is defending against |
| 800-53 CA-6, and the SP 800-53B baselines around it | Select and tailor a control baseline, then authorize the system to operate | NOT ADDRESSED, deliberately. This is what makes 800-53 mean something to a system owner and it is meaningless to a producer who does not operate the system. An adopter who follows the citation upstream will spend weeks tailoring and end with a document describing an organization they are not. Only named control text is borrowed here |
| 800-53 CM-5(4) | Dual authorization for changes | NOT ADDRESSED, structurally, for the same reason as AC-5: it requires two qualified individuals. Section 13 is where a solo maintainer records it, not section 10 |
| 800-53 CP-2, CP-4 | A contingency plan for the system, and testing of it, with recovery time and recovery point objectives | NOT ADDRESSED. Continuity of a running deployment is in the right-hand column of section 1's table, and claiming it would be the over-reach that table exists to prevent. Only the producer-side sliver crosses over -- backing up the producer's own evidence archive, in section 10 -- and section 10 states in the same paragraph that it does not cover a deployment's data |
| 800-53 IR-1 through IR-8 as a program | An incident response capability with handling phases, training, testing and reporting obligations | NOT ADDRESSED as a program. Section 12 carries the producer-scoped slice -- private intake, banded windows, root-cause review, coordinated disclosure, and the machinery exercised end to end at least once. Incidents are generated by running the software, which is the operator's column |
| 800-53 MA family | Controlled maintenance, maintenance personnel, maintenance tools, nonlocal maintenance | NOT ADDRESSED. It assumes an owned hardware estate serviced by identified technicians. There is no analogue in a topology of a workstation and a hosted runner, and forcing one produces a control satisfied by definition -- which is the failure section 5 names when it requires you to fire the failure class at a gate before crediting its green |
| 800-53 PE family | Facility perimeter, physical access authorization and records, visitor control, environmental protection | NOT ADDRESSED. A producing team has no facility to evidence any of it against. The part that would matter -- physical access to the machine the build runs on -- sits with the build service, which section 1's third-participant table names and does not claim |
| 800-53 PM family | An organizational security program: senior officials, enterprise architecture, insider threat, a risk executive function | NOT ADDRESSED. There is no small-team version of it. There is only a solo maintainer writing an organization chart that does not exist, which is the kind of fiction section 17's claim register is built to catch |
| 800-53 PS family | Personnel screening, termination and transfer procedures, and formal sanctions for policy violation | NOT ADDRESSED. Employment controls belong to the adopting organization. A one- or two-person team screening and sanctioning itself is theater, and naming it as satisfied would be worse than naming it absent |
| 800-53 RA-3, RA-9 | A standing risk assessment and a criticality analysis, as separate artifacts | NOT ADDRESSED as standing artifacts. Section 2's per-boundary threat model carries the part a producer can act on, and it is better targeted because it is checkable one boundary at a time. A standalone risk assessment gives the release gate something to point at that nobody verified |
| 800-53 SR-11, and the physical supply-chain controls beside it | Component authenticity and anti-counterfeit; shipping, handling, tamper checks and disposal | NOT ADDRESSED. These are hardware and physical-supply-chain controls. The software supply-chain content a producer can actually evidence -- provenance, attestation over the digest, component inventory, published digest manifest, pinned toolchain -- is in section 10 and is stronger there than a mapping to these would make it |
| Third-party agreements | Contractual terms binding a service that handles your data, with defined obligations and remedies | NOT ADDRESSED. The third-participant table records the trust and the failure mode; it does not attempt an agreement. Negotiated terms are the adopting organization's instrument, and a small team on a provider's standard terms has nothing to negotiate -- writing a clause it cannot enforce would be a compensating control resting on a false premise |
| Assessment determination statements | Per-control determination statements, assessed by examine, interview and test methods | NOT ADDRESSED, and deliberately not imported. Converting a standard a team builds to into an audit program a team is subjected to changes what the document is for. Section 15 points at this site's own assessment method and is explicit that a second procedure must not be built beside it |
| System categorization | Assign an overall impact level to a system | NOT ADDRESSED, and it would be over-reach to try. This document categorizes data classes, which are a property of the code it ships. The deployed system belongs to the adopting organization and its category is theirs to assign, per section 1's split and section 15's correction about not gating somebody else's deployment |
| SP 800-115 technique and tooling inventory | Named scanning, sniffing, password-cracking and review techniques | NOT ADDRESSED, and not borrowed. The publication is from 2008 and only its process material is durable, which is why the source list above scopes it to process and nothing here cites it for technique |
| Social engineering testing | Phishing simulation, pretexting, and physical-access attempts against people | NOT ADDRESSED as a control. Its target is an organization's staff and premises, not a build. Section 15 requires the engagement scope to state what is explicitly out of scope, which is the one place a decision either way gets recorded rather than assumed |

---

## Sources

The record of record for the four publications named above. Status, date, and the date the
status was last checked live here and nowhere else on the page, so a re-check is one edit. The one
place two of these dates appear again is the version-trap paragraph
[above](#where-the-rules-come-from), where the two disagreeing dates *are* the argument rather than a
status record.

| Short code | Publication | Status and date | What it uniquely contributes | Status last checked |
|---|---|---|---|---|
| `SSDF <practice>` | NIST SP 800-218 v1.1, Secure Software Development Framework | Final, February 2022 | The producer-facing outcome layer. PW.8 (test executable code, including fuzzing tied to intended use), PO.3 (define and maintain the toolchains) and PO.5 (a secure environment for developing and building) are the outcomes standing behind section 2's malformed-input harness and section 10's build-environment rules | 2026-08-06 |
| `800-53 <CONTROL>` | NIST SP 800-53 Rev. 5, Security and Privacy Controls for Information Systems and Organizations, as maintained by Release 5.2.0 | Rev. 5 final, content dated September 2020 with updates as of 2020-12-10; Release 5.2.0 issued 2025-08-27 | Quotable control text, cited by identifier on the rule that restates it. Controls held out of the prose by the one-mark-per-rule cap, recorded here instead: SA-11 base, SA-11d, SA-11e, CM-5(1), SC-28(1), SC-28(3), SI-12, CA-2d, CA-7c, CA-8, CP-9(1), CP-9(2), AU-6(3) | 2026-08-06 |
| `800-115 Appendix B`, `800-115 section 8.3` | NIST SP 800-115, Technical Guide to Information Security Testing and Assessment | Final, September 2008 | Process material only: the rules-of-engagement template (Appendix B) and the caveat that a retest verifies a fix only if the confirming run mirrors the original (section 8.3) | 2026-08-06 |
| `FIPS 199` | FIPS 199, Standards for Security Categorization of Federal Information and Information Systems | Final, February 2004 | Three security objectives -- confidentiality, integrity, availability -- at three impact levels, and the high-water-mark roll-up that rates a collection by the highest class it holds | 2026-08-06 |

A publication's presence here says only that a rule on this page borrowed from it. It is not a claim
of conformance with any of them, and none of them certify anything -- see
[section 17](#17-what-you-may-claim).

---

## Related

- [CI and standards](../CI-AND-STANDARDS.md) -- blocking versus advisory coverage, receipts, claim
  honesty, gate design, and the general metric evidence this document does not restate
- [The leak gate](../LEAK-GATE.md) -- fail-closed secret and forbidden-content scanning, and the three
  ways a scanner lies
- [Dependency and artifact integrity](DEPENDENCY-INTEGRITY.md) -- the consuming half of an advisory,
  per-manifest audit nets, and the pinned resolved graph
- [What to ask a software vendor for](DILIGENCE-PACKET.md) -- the buyer's side of section 12, what
  each item of evidence proves, and why organization-layer evidence is not software-layer evidence
- [Running a large security-standard assessment with AI agents](../ASVS-ASSESSMENT.md) -- verdict
  vocabulary, evidence anchors, corpus pinning, and reading a movement in a score
- [Case study: auditing a multi-session estate as one system](../CASE-STUDY-drift-audit.md) -- proving
  a fix by deliberate mutation of the shipped artifact
- [Tips and tricks](../TIPS-AND-TRICKS.md) -- section 4 on writing a guardrail, section 5 on measuring
  whether it works
