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

## How to read the rules

Every rule is one testable statement in a table, with an identifier and the evidence that settles
it. Cite the identifier in your deviations register and in a review, so both point at the same
sentence.

| Element | What it means |
|---|---|
| The subject | The producing project, in every rule. Where a rule is the operator's, it says so |
| `SD-<section>.<n>` | A stable identifier. It does not change when the text around it is reworded |
| **MUST**, **MUST NOT** | Absolute. Not meeting one is a deviation under [section 13](#13-deviations-and-risk-acceptance), never a judgment call |
| **SHOULD** | Ignore it only for a stated reason you have weighed |
| **MAY** | A free choice. Conforming either way |
| Evidence | What a reviewer looks at. A rule with no checkable evidence is an aspiration |

Capitals carry that meaning; the same words in lowercase prose do not. Rules are the tables.
Everything else on the page is the reason for one, and **Limit:** lines are where a control stops
working -- both are as binding on what you may claim as the rules themselves.

**An identifier is a permanent name, never a position.** A new rule takes the next free number in
its section and is appended, so document order and identifier order are independent -- inserting a
rule must never renumber the ones after it, because a citation written against the old number would
then silently resolve to a different requirement. Reword a rule freely under the same identifier.
Change what it demands and you retire the identifier and allocate a new one.
[Retired rules](#retired-rules) keeps the tombstones, so a citation that outlives its rule lands on
a record of what happened rather than on somebody else's requirement.

Marks record where a rule was borrowed. An unmarked rule is this document's own.
**[derived: `<code>`]** restates a published requirement; **[prompted by: `<code>`]** means the
source raised the topic and the rule is ours; **[external]** is empirical evidence. The test:
if the source changed, would the rule change? Yes is derived, no is prompted-by.
[Where the rules come from](#where-the-rules-come-from) names the publications.

---

## 1. Shared responsibility: write the split down first

Software built by one party and run by another has a boundary. The failure is not that somebody
does the wrong thing. It is that both sides assume the other has it covered.

| ID | Requirement | Evidence |
|---|---|---|
| SD-1.1 | **MUST** publish a table splitting every control between the producing project and the operating organization | The published table |
| SD-1.2 | **MUST** state, where an adopter will read it, that shipping the software confers nothing on the operator | The statement, not in a footnote |
| SD-1.3 | **MUST NOT** list a control from the operator's column as one you provide. Document and recommend it instead | No operator-side control in your control list |

| The producing project owns | The operating organization owns |
|---|---|
| Secure development practice | Its own host, network and platform security |
| Secure-by-default configuration | Identity, credential and key management in its environment |
| Testing and attestation of the software | Backups, disaster recovery, availability |
| Vulnerability response and disclosure | Its own compliance program and risk assessment |
| Documentation and evidence | Monitoring, patching, incident response |
| The audit log's review affordance and a labelled retention default | Reviewing the audit log on a defined cadence, and what counts as unusual activity there |

An attestation that the software was built securely is an input to the operator's assessment, never
a substitute for it.

### The third participant: services neither column owns

Neither column has room for the CI provider, the source host, the package registry, the
transparency log or the artifact store, so every control those hold gets filed where it does not
fit.

| ID | Requirement | Evidence |
|---|---|---|
| SD-1.4 | **MUST** list the services the build depends on, what each is trusted to do, and what fails if it is compromised or goes away. **[prompted by: 800-53 SA-9]** | A table of five to eight rows |
| SD-1.5 | **SHOULD** state the monitoring you actually perform. For a small team that is subscribing to status and advisory feeds and reading them, not auditing a provider | The named feeds |

| Service | Trusted to | What fails if it is compromised, or goes away |
|---|---|---|
| Source host | Hold the trunk, enforce branch protection, keep the history | Every protected-path rule, and the provenance chain back to a commit |
| Build service | Execute the pipeline on a runner you do not administer | The claim that the artifact traces to a repository rather than to a machine |
| Package registry | Serve the artifact under the name consumers resolve | Distribution, and the account that publishes under that name |
| Transparency log | Hold the inclusion proof a consumer checks | Verification for anyone who cannot reach it, unless the proof was bundled |
| Evidence and artifact store | Retain releases, inventories, attestations, register | [Section 10's](#10-build-and-release-integrity) archive, and every claim that rests on it |

This table is where
*[keyless signing moves the threat model, it does not remove it](#publishing-controls-and-the-limit-each-one-carries)*
puts the load it relocates. Without it, that load has nowhere to land.

### What "restricted data" means here, exactly once

| ID | Requirement | Evidence |
|---|---|---|
| SD-1.6 | **MUST** define the data classes in one table, and **MUST NOT** carry a second adjective for the same idea anywhere else. **[prompted by: 800-53 SC-28]** | One table, one term |
| SD-1.7 | **MUST** list every place a class comes to rest, not the obvious one | The third column, filled |
| SD-1.8 | **MUST** rate each class for confidentiality, integrity and availability at low, moderate or high. **[derived: FIPS 199]** | A rating per class |

**Restricted data** means any class your filled-in table rates above low on confidentiality or
integrity. Deliberately not the top level: a definition narrower than the adjective it replaced
would silently weaken every rule that uses it, with nothing in the diff to show it. If a rule says
restricted data and your table has no matching row, the finding is the missing row.

| Column | What goes in it |
|---|---|
| Class | The name this document and your code both use for it |
| Enters through | Which trust boundary from [section 2](#2-threat-model-each-trust-boundary-before-you-build-it) it arrives on |
| Comes to rest in | **Every** place: primary store, application log, audit log, temporary and spool files, crash dumps, diagnostic and support bundles, exports, published artifacts, test fixtures, and the context handed to an AI coding assistant |
| Protected how | The protection at each resting place, and where its key material lives |
| Kept how long | The shipped retention default, and the documented path that deletes it |

One row filled in, to show the shape. Illustrative only -- it describes no project:

| Class | Enters through | Comes to rest in | Protected how | Kept how long |
|---|---|---|---|---|
| Credentials and key material | No boundary -- the running account resolves this at startup rather than receiving it as input | The secret store, and nowhere else | Encrypted at rest by the secret store; the running account holds no copy in a file. The key material is the operator's, named here rather than claimed | Nothing is retained: rotation replaces the value and is the documented deletion path |

Classes that recur: credentials and key material; data restricted under a regime the adopting
organization operates under; operational telemetry identifying a person or a site; and the
published artifact, which is public by construction and belongs in the table so that is written
down rather than assumed.

The third column is what earns the table. "At rest" read as a property of a storage device covers
the primary store and misses the rotating log file, the crash dump and the support bundle -- same
content, same state, none of the protection. Rate the **state of the information**, not the device.

**Limit:** this is a written artifact. It adds no blocking release condition, and it makes
[section 7](#7-secure-defaults-and-the-opt-in-that-must-be-explicit)'s at-rest default checkable
rather than encrypting anything itself.

---

## 2. Threat model each trust boundary before you build it

A trust boundary is anywhere input you do not control crosses into code you do: a network
interface, a command line, a file dropped in a watched directory, a scheduled job reading shared
storage, a queue consumer, a webhook, an inter-process channel, a database somebody else writes to.
A system with no network interfaces still has boundaries.

| ID | Requirement | Evidence |
|---|---|---|
| SD-2.1 | **MUST** write a threat model for every trust boundary, and **MUST** have it reviewed before the code exists | The reviewed artifact, dated before the change |
| SD-2.2 | **MUST** name a mitigation for each way in, and a constraining control on each piece of dangerous functionality | A row per boundary |
| SD-2.3 | **MUST** name a bound on resource consumption for every boundary: maximum payload, request rate, concurrency, total time. **[prompted by: 800-53 SC-5]** | A constant in the code, one grep from each row |
| SD-2.4 | **SHOULD** run a malformed-input harness against the code behind every ingress, seeded from that boundary's format, on a schedule. **[derived: 800-53 SA-11(8)]** | A committed corpus, and a regression test per crash found |

An unbounded boundary is a finding in the same way an unmitigated ingress is. The common residual
is the limit set on the boundary somebody thought about and absent on its three siblings.

| Boundary | Mitigation | Bound |
|---|---|---|
| A file dropped in a watched directory | Path canonicalised against the configured directory so traversal and symlink escapes are rejected; type and size validated by content rather than extension; written atomically then renamed | Maximum file size, files accepted per minute, concurrent readers, total processing time per file |

**Limit:** nothing mechanical verifies that a threat model is good. A gate can only check that one
exists for a boundary that was added. The harness is
[advisory, not coverage](#5-scanner-posture-what-blocks-what-advises-what-may-never-be-waived), it
reaches parser, decoder and boundary surfaces rather than the whole artifact, and one that never
gets past the first parse call is the dynamic-testing equivalent of a clean run on a weak ruleset.
It narrows the [section 15](#15-independent-external-verification) gap. It does not close it.

### A diagram without marked trust boundaries is not a security artifact

A list is hard to check for absence: nobody notices the ingress that was never written down.

| ID | Requirement | Evidence |
|---|---|---|
| SD-2.5 | **SHOULD** draw one diagram per system showing external entities, processes, data stores and flows, with the trust boundaries drawn as lines the flows cross | The diagram |
| SD-2.6 | **MUST NOT** file a diagram with no boundaries marked on it as a threat-modeling artifact | Boundaries visible on the drawing itself |
| SD-2.7 | **SHOULD** keep the diagram source in the repository in a format that diffs, and label each flow with the data class it carries | A new boundary appears as an added line in a diff |

Components and arrows with no boundaries marked is architecture documentation. It is useful, it is
not this, and it gets found later by somebody who reads it as a threat model because it is the only
picture in the repository. The check the picture buys over the list is two-way: every crossing on
the diagram has a row in the list, and every row has a crossing.

**Limit:** the diagram records what somebody believed the boundaries were. The code is where they
actually are, and the two diverge without a sound. It goes stale on the same events as the
data-class table, so it rides that table's trigger in
[section 14](#14-re-evaluate-on-a-trigger-and-on-a-short-calendar-for-what-has-no-trigger) rather
than adding a gate row of its own.

### Execution boundaries need the longest look

Where content becomes executable, these questions generalize:

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

"Is this change secure" is not a question a reviewer can answer. These are.

| ID | Requirement | Evidence |
|---|---|---|
| SD-3.1 | **MUST** validate structure and content of every inbound payload at ingress, before it reaches a query, a file path, a subprocess, or a message emitted downstream | Rejection or quarantine of malformed input |
| SD-3.2 | **MUST** use parameterised queries only. No string-built statements, and no exception held open by a comment | No string concatenation into a query |
| SD-3.3 | **MUST** enforce authentication and authorization on every action, deny by default | A denial path per action |
| SD-3.4 | **MUST**, when parsing structured documents, disable external-entity resolution and document-type processing, size-limit against a schema, apply that boundary's bounds from [section 2](#2-threat-model-each-trust-boundary-before-you-build-it), and return no internal detail in a fault | Parser configuration |
| SD-3.5 | **MUST**, for file handling, confine reads and writes to configured directories, canonicalise paths, validate type and size by content, write atomically then rename, never place files on an executable or served path, and never execute file contents | Path handling at each site |
| SD-3.6 | **MUST** use vetted cryptographic libraries, and **MUST NOT** write your own | The dependency |
| SD-3.7 | **MUST** fail closed on error, and **MUST NOT** log secrets or restricted data | The error path, and the log |

Two more are owned elsewhere and named here only so the list is complete: treating everything an
agent reads as data rather than instructions, and verifying a dependency's identity before adding
it. Both are in [CI and standards](../CI-AND-STANDARDS.md).

---

## 4. Review, and what to do when there is no second reviewer

| ID | Requirement | Evidence |
|---|---|---|
| SD-4.1 | **MUST** peer-review every change, run static and dependency analysis on it, and confirm it meets the acceptance criteria of whatever specified it | The review record |

That is the requirement. Many projects cannot meet it, and the honest response is not to redefine
"reviewed" until it fits.

### Self-review is a documented deviation, not a satisfied control

| ID | Requirement | Evidence |
|---|---|---|
| SD-4.2 | **MUST** record self-review as a deviation naming the control not met, the compensating set actually in force, and the event that ends it -- usually a second maintainer joining | A register entry under [section 13](#13-deviations-and-risk-acceptance) |
| SD-4.3 | **MUST NOT** let any published claim imply the compensating set is an independent audit | The wording of the claim |

The set is typically blocking static analysis and dependency audit that cannot be waived, AI-run
review a human arbitrates, branch protection with required checks, and no direct pushes to the
trunk. List each only where it is actually in force.

### The confidence effect bites hardest in self-review

**[external]** A controlled study found developers with access to an AI coding assistant wrote less
secure code while being more confident it was secure. It used a 2022-era model, so re-baseline the
magnitude; the direction is the point. The citation and its hedge live once, in
[Judging code quality, whoever or whatever wrote it](CODE-QUALITY.md#the-evidence-and-the-hedge-each-citation-must-carry).

That effect bites hardest in exactly the self-review case, which is the argument for the one
control independent of the author's confidence: an adversarial check on whether the tests assert
anything.

### The comprehension bar, and two additions to it

| ID | Requirement | Evidence |
|---|---|---|
| SD-4.4 | **MUST** reject code you cannot explain. Reaching the explanation with assistance is acceptable | The reviewer's explanation |
| SD-4.5 | **MUST** verify an AI assistant's explanation rather than accepting it. It can be confidently wrong the same way its code can | The verification |
| SD-4.6 | **SHOULD** cold spot-check an already-merged assisted change periodically, to detect explaining drifting into rubber-stamping | A dated spot-check |

---

## 5. Scanner posture: what blocks, what advises, what may never be waived

**Coverage is the set of blocking checks that run on a change, not the tool inventory.** Advisory
and scheduled-only jobs are useful and are not coverage.

| ID | Requirement | Evidence |
|---|---|---|
| SD-5.1 | **MUST** classify every nominally-security job as blocking or advisory, and write the classification down | The classification, since the two are indistinguishable from a green badge |

### What must block, and may not be waived

| ID | Requirement | Evidence |
|---|---|---|
| SD-5.2 | **MUST** block on static analysis, red on any new finding from a clean baseline | The blocking-job list |
| SD-5.3 | **MUST** block on dependency vulnerability analysis, red on any new advisory | The blocking-job list |
| SD-5.4 | **MUST** block on secret scanning over the full history, not only the diff | The blocking-job list |
| SD-5.5 | **MUST NOT** let an author waive any of the three past their own change | Branch protection settings |

Mechanics are published elsewhere: [CI and standards](../CI-AND-STANDARDS.md) covers grandfathering
to a clean baseline and ratcheting, and the two-layer shape where a local hook gives fast feedback
and the pipeline is the authoritative gate. [The leak gate](../LEAK-GATE.md) covers fail-closed
forbidden-content scanning and the three ways a scanner lies.

### Dynamic testing: an event trigger, and a written record of what no trigger reached

The blocking set above is entirely static: three checks that read code, manifests and history
without executing anything. A scheduled job with no stated trigger drifts into a green light nobody
asked a question of.

| ID | Requirement | Evidence |
|---|---|---|
| SD-5.6 | **SHOULD** trigger a dynamic pass on a named event, each answerable from a diff | The trigger list below |
| SD-5.7 | **MUST**, where no trigger has fired since the last periodic pass, record that dynamic testing did not run, carrying that pass's date rather than inheriting the last green run | A line in [section 14](#14-re-evaluate-on-a-trigger-and-on-a-short-calendar-for-what-has-no-trigger)'s dated entry |
| SD-5.8 | **MUST** record a pass's reach, not only its result | What the corpus reached |

The events, at least: a boundary is added or the parser behind an existing one is replaced; a
parsing or decoding dependency crosses a major version; a finding of this class arrives from any
source; a release changes the ingress surface. The schedule in
[section 2](#2-threat-model-each-trust-boundary-before-you-build-it) stays and does a different job
-- it is how the corpus accumulates. A project running only the schedule has a control that cannot
respond to anything.

**Limit:** nothing here blocks, and the coverage question is what the corpus reached, never how
long it ran. The harness does not reach authorization decisions, business logic, multi-step flows,
or state held across requests. Those stay in [section 15](#15-independent-external-verification)'s
gap however green this is.

### Three additions specific to a security posture

| ID | Requirement | Evidence |
|---|---|---|
| SD-5.9 | **MUST NOT** treat a clean run as a certificate. It is a start condition for red-on-regression, and zero findings on a weak ruleset proves nothing | The ruleset, not the result |
| SD-5.10 | **MUST** fire the failure class at a gate and watch it go red before crediting its green | A dated record of the gate refusing something |
| SD-5.11 | **MUST** encode a control as one deterministic check shared across every sibling path, never as a habit applied per path | One check, every path |
| SD-5.12 | **MUST** record rigor and scope as two values per blocking check, never as one | A row reading "pattern match / this module" or "taint analysis / whole tree" |

A control implemented exactly where it was prompted and missing on its siblings is the most common
residual after an agent-run security sweep. And a check that ran on one path at high rigor and a
check that ran on every path at low rigor both report green, with no tool to tell you which you
have.

### The security anti-metrics

Each may be surfaced as advisory context. None may ever be the pass or fail decision.

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
| Count of externally-catalogued control identifiers cited | A citation records where a rule came from. Counting citations scores nothing |

**There is no validated threshold at which a build becomes secure.** No framework supplies one. Any
number you adopt is project-set and directional. Label it that way.

---

## 6. Secrets and repository hygiene

| ID | Requirement | Evidence |
|---|---|---|
| SD-6.1 | **MUST** keep secrets, keys, credentials and restricted data out of the repository, across the full history rather than only the current tree | A clean history scan |
| SD-6.2 | **MUST** pair any path deny-list with a fail-closed commit-time content scan | Both controls present |

This is not a private-repository exemption: a repository's visibility can change, and its history
travels when it does. The rule and its mechanics are owned by
[the leak gate](../LEAK-GATE.md) and by *Secrets and sensitive data never enter the repository* in
[CI and standards](../CI-AND-STANDARDS.md).

**Limit:** a path deny-list keeps a file from being read and does nothing about the same content
typed into a different file. A commit-time scanner sees what lands in a commit -- not an outbound
query, a tool-server call, or a fetch argument. Nothing mechanical stands between a running agent
and that channel, so the discipline there is on the human, and the standard has to say so rather
than letting a green scanner imply coverage it does not have.

---

## 7. Secure defaults, and the opt-in that must be explicit

| ID | Requirement | Evidence |
|---|---|---|
| SD-7.1 | **MUST** ship with transport encryption on, encryption at rest on for every resting place [section 1](#1-shared-responsibility-write-the-split-down-first)'s table names for a restricted class, least-privilege accounts, and verbose audit logging | The shipped defaults |
| SD-7.2 | **MUST** make any insecure posture an explicit, named, documented and audited opt-in behind a fail-closed guard, never one a deployment inherits by omission | The guard, and the opt-in record |
| SD-7.3 | **MUST** state fail-open versus fail-closed next to the code, with the reason | The statement at the site |

Two reading errors go with this, and they are defects in opposite directions. **Off by default,
described as active**: the code exists, nothing is running. **Fail-closed, mis-read as inert**: it
looks like nothing is happening because nothing needs to. Score and describe those states
separately.

### Synthetic data by default in anything that is not production

| ID | Requirement | Evidence |
|---|---|---|
| SD-7.4 | **MUST** run test, development and preproduction environments on synthetic or dummy data. **[derived: 800-53 SA-3(2)]** | The fixture or the generator |
| SD-7.5 | **MUST** approve, document and date any use of live data in [section 13](#13-deviations-and-risk-acceptance)'s register, and protect that environment to the level of the system the data came from for as long as it is present | A dated entry naming what was copied, where it went, and when it was destroyed |

State the ratchet, because it is the part people get backwards: copying a restricted class into a
test environment does not lower that data's protection requirement, it raises the environment's.
That is the whole argument for synthetic by default, since the alternative is protecting every
scratch environment like production, permanently.

### Rate a collection by the highest class it holds

| ID | Requirement | Evidence |
|---|---|---|
| SD-7.6 | **MUST** rate a collection by the highest class it holds, never by the average and never per entry. **[derived: FIPS 199]** | The access posture on each accumulator |

Three of the resting places this document tells you to build are accumulators: the
[section 9](#9-tamper-evident-audit-logging) audit log, the
[section 10](#10-build-and-release-integrity) release archive -- artifact plus build inputs plus
inventory, and therefore a map of the whole system that no single input is -- and the
[section 13](#13-deviations-and-risk-acceptance) register. Each is individually innocuous.
Collectively they are the thing an attacker would actually want.

---

## 8. Machine-to-machine authentication

| ID | Requirement | Evidence |
|---|---|---|
| SD-8.1 | **MUST** authenticate a machine caller as a system, not a person, using the strongest mechanism the peer supports | The mechanism per connection |
| SD-8.2 | **MUST** record per connection the mechanism, its scope, and where the credential lives, alongside that connection's configuration | A reviewable record, one connection at a time |
| SD-8.3 | **MUST** record a per-connection exception wherever a weaker mechanism is used | A short explicit list rather than a discovery |
| SD-8.4 | **MUST NOT** carry restricted data over cleartext transport, keep credentials in code or configuration, or grant more than least privilege per connection | The transport, the secret store, the scope |
| SD-8.5 | **SHOULD** restrict the connection at the network level as defense in depth | The network rule |

A workable hierarchy, strongest first:

1. **Mutual TLS** with full chain validation, revocation checking, and rotation before expiry.
2. **A client-credentials grant**, preferring asymmetric client authentication over a shared
   secret, issuing short-lived per-connection scoped tokens whose issuer, audience, expiry and
   scope are validated on every request.
3. **Weaker mechanisms** -- a shared secret over TLS, a per-connection API key, a message-level
   username token -- for peers that cannot do better, under SD-8.3.

### Service accounts: no long-lived secret in a file

| ID | Requirement | Evidence |
|---|---|---|
| SD-8.6 | **MUST** run under a least-privilege account whose credential rotates automatically and is never stored in configuration. Where the platform offers a managed service identity, use it | No long-lived secret in a file |
| SD-8.7 | **MUST** perform directory lookups over a TLS-protected channel and fail closed on a cleartext one | The bind configuration |

The mechanics are platform-specific. The transferable property is that no long-lived secret exists
in a file, which removes both the most commonly leaked credential and the one whose silent expiry
causes the outage nobody diagnoses.

---

## 9. Tamper-evident audit logging

| ID | Requirement | Evidence |
|---|---|---|
| SD-9.1 | **MUST** produce an append-only, timestamped, actor-attributed audit log with a hash chain over its entries | The chain, one hash per entry |
| SD-9.2 | **MUST** gate reads on it, and keep secrets and restricted data out of it entirely at informational level and above | The log contents |
| SD-9.3 | **MUST**, where the deployment is exposed beyond a single trusted host, forward off-box over TLS | The forwarding configuration |

An ordinary application log cannot tell an incident review whether the record was altered. A chained
one can. SD-9.3 is exposure-conditional, so a local-only deployment is not described as
non-compliant for a control it does not need.

### What happens when the log cannot be written

| ID | Requirement | Evidence |
|---|---|---|
| SD-9.4 | **MUST** state the behavior when the log is unwritable -- disk full, store unreachable, chain verification failing -- as an explicit fail-open or fail-closed choice next to the code, and raise an alert rather than degrading silently. **[prompted by: 800-53 AU-5]** | One branch and one alert, testable by making the sink fail |

The trap is specific to a chained log. An implementation that drops or truncates entries under
storage pressure breaks the chain, and a broken chain is indistinguishable at review time from one
broken by tampering. So the fallback -- overwrite the oldest, stop accepting work, or stop
generating records -- is part of the tamper-evidence claim and belongs beside the hash chain rather
than in a runbook.

### Ship the review affordance; the cadence is not yours

| ID | Requirement | Evidence |
|---|---|---|
| SD-9.5 | **MUST** ship query and filter by actor and by time, export in a form another tool reads, and one documented command that verifies the chain and prints which entry first fails. **[prompted by: 800-53 AU-6a]** | The command, run |
| SD-9.6 | **MUST** ship a default retention period and label it project-set. **[prompted by: 800-53 AU-11]** | The labelled default |
| SD-9.7 | **MUST NOT** claim the review cadence or the definition of unusual activity. Both are the operator's, and have a row in [section 1](#1-shared-responsibility-write-the-split-down-first)'s table | The table row |

A log nobody can read is write-only by construction, and the reading obligation is exactly the kind
of control that goes unowned: the producer assumes the operator reviews it, the operator assumes it
is reviewed by whoever built it. An unbounded retention default is why the log later gets truncated
by whoever runs out of disk.

---

## 10. Build and release integrity

This is the part an adopter can check without trusting anything you say about your process, which
is what makes it worth more than the rest of your security page.

### Where the build runs, and who can change it

| ID | Requirement | Evidence |
|---|---|---|
| SD-10.1 | **MUST** run the release build on an ephemeral runner with no interactive login path, never on a developer workstation. An artifact built on one is not publishable. **[prompted by: 800-53 SA-3(1)]** | The runner configuration |
| SD-10.2 | **MUST** hold the workflow definition and every file it sources under the same protected-path rules as release code | Branch protection covering the pipeline |
| SD-10.3 | **MUST** hold the publishing capability in the workflow identity and close the human publishing path, with required reviewers on the publishing environment and token scope declared per job. **[prompted by: 800-53 AC-6, CM-5]** | No usable human publish path |
| SD-10.4 | **MUST** enumerate every principal that can write to the trunk, administer the repository, or publish -- human accounts, machine accounts, deploy keys, installed applications and their scopes, and registry trusted-publisher entries -- and review that list on a stated cadence. **[derived: 800-53 CM-5(5)]** | A dated export of the collaborator, deploy-key, installed-application and environment-protection settings |
| SD-10.5 | **MUST** pin every action, image, plugin and tool the pipeline invokes to an immutable digest, and review the pinned set on a stated cadence. **[prompted by: 800-53 SA-15a]** | The pinned set, and a dated review |

SD-10.1 is usually already true and merely unstated, and writing it down is the point: an unstated
property cannot be checked when it stops being true. Build configuration can alter every artifact
without altering a line of source, which is why SD-10.2 exists. Closed is a stronger claim than
least privilege, because a path that exists and is not used is a path nobody is watching. The row
worth staring at in SD-10.4 is the rarely-used automation token with publish scope -- a larger
exposure than the maintainer's own account precisely because it has no session and no notification.

**Limit:** SD-10.1 removes the class where an untidy workstation contributes bytes to a release. It
is no defense against a malicious change that was reviewed and merged. Pinning establishes that you
got the same bytes as last time, never that those bytes are trustworthy, which is why a pin and a
blocking advisory gate are complementary. For a solo maintainer SD-10.4 will show one human holding
everything -- a [section 13](#13-deviations-and-risk-acceptance) entry, not a control to claim.

### Publishing controls, and the limit each one carries

| ID | Requirement | Evidence |
|---|---|---|
| SD-10.6 | **MUST** mint publishing credentials per run from the pipeline's own workflow identity, scoped to a specific repository, workflow and environment, valid only for the length of an upload | No long-lived registry token |
| SD-10.7 | **MUST** restrict the publishing workflow to trusted triggers such as a tag or a push, never one that grants write credentials to code from an untrusted contributor, and **MUST** pin the publishing action | The trigger, and the pin |
| SD-10.8 | **MUST** pair publishing identity with a signed attestation binding the distributed filename and its digest to the source repository, workflow and commit, recorded in a public transparency log and served alongside the artifact | The attestation, resolvable by a consumer |
| SD-10.9 | **SHOULD**, where consumers verify on disconnected networks, bundle the transparency-log inclusion proof with the artifact | Verification without network access |
| SD-10.10 | **MUST** measure what proportion of artifacts carry a signature and what proportion a consumer can resolve to an identity, before crediting a signing control | The two proportions |

**Limits, three of them.** Per-run credentials do not defend against takeover of the publishing
account; that is what account-level multi-factor and environment protection are for. **Publishing
identity does not cover the artifact** -- establishing that the upload came from your pipeline says
nothing about whether the artifact was modified before or after it was built, which is why neither
half of SD-10.8 is sufficient alone. And **keyless signing moves the threat model, it does not
remove it**: short-lived certificates and a transparency log remove long-lived key management,
which is a real win, and they relocate the load onto multi-factor, branch protection and pipeline
hardening.

**[external]** When one large package registry measured its long-standing detached-signature
support, only about a third of signing keys could be meaningfully verified, and signed files were a
fraction of a percent of everything published. Support was withdrawn, and existing signatures are
now silently ignored. Coverage and verifiability are separate questions, and both can be near zero
while a scheme is nominally in place.

### What an adopter can verify without contacting you

| ID | Requirement | Evidence |
|---|---|---|
| SD-10.11 | **MUST** generate build provenance from the pipeline, proving the artifact traces to a specific repository, workflow and commit rather than to somebody's machine. Isolating the build behind a dedicated reusable workflow raises the assurance level further | The provenance |
| SD-10.12 | **MUST** publish a signed digest manifest with every release and document the exact verification commands, including the offline path | The manifest, and the documented commands |
| SD-10.13 | **MUST** generate a component inventory per release in the formats your consumers ingest, and attach it to the release and to the archived build | The inventory |
| SD-10.14 | **MUST** archive each release with its build inputs and its inventory | The archive |
| SD-10.15 | **MUST** back that archive up off the platform that hosts it, and restore from it at least once, dated. **[derived: 800-53 CP-9c]** | A restored release whose artifact still matches the published digest |
| SD-10.16 | **MUST** declare an explicit allowlist of what the published artifact contains, gate on it before the upload step, and verify the published artifact once after release | The allowlist, and the post-release check |

The digest manifest is the lowest-tech verification path and the one route a reviewer on an
air-gapped network can always run. Make it the documented baseline rather than the afterthought.
SD-10.15 matters because the archive, the build inputs, the inventories, the attestations, the
publishing identity configuration and the deviations register typically live in one account at one
provider -- so an account suspension takes all of it in a single event, at which point every claim
in [section 17](#17-what-you-may-claim) becomes unevidenced simultaneously. A copy nobody has
restored from is a claim rather than a backup.

**Limits.** **A component inventory is not tamper detection.** It answers "do we ship component X"
within minutes of an advisory, detects drift against the intended manifest, and satisfies
procurement. It is not integrity evidence for your own code and must not be quoted as such. An
archive holding only the artifact answers neither incident analysis nor reproducibility. Checking
what you built is not checking what shipped. And SD-10.15 reaches the producer's own evidence, not
a deployment's data: backups and disaster recovery stay in the operator's column, unchanged.

### Obfuscation is not the control you are looking for

| ID | Requirement | Evidence |
|---|---|---|
| SD-10.17 | **MUST NOT** describe a hardened build as tamper-proof. Position it as raising analysis cost, and keep secrets and authorization decisions out of any artifact an adversary holds | The wording of the claim |

For code whose source is published, obfuscating or compiling the shipped artifact protects nothing
that matters: there is no confidentiality to preserve, the tamper resistance gained is marginal, and
where a copyleft license requires corresponding source it creates friction with that obligation.

The vendors concede the limit themselves. One obfuscation product's documentation states it is not
good at memory protection or anti-debug, and that its runtime-data protection holds only if the
interpreter and its runtime extension are not compromised -- a condition a privileged attacker
defeats by definition. One native compiler concedes its default single-file mode is a
self-extracting archive whose contents land on disk. Bytecode-only distribution is trivially
decompiled.

**The rule that survives all of it: a protection scheme that must run inside the process it
protects assumes an uncompromised runtime, which is exactly the assumption a privileged attacker
breaks.** Spend the budget on verification instead, because that is what a reviewer can check.

---

## 11. Runtime tamper resistance, and the bootstrap-trust limit

| ID | Requirement | Evidence |
|---|---|---|
| SD-11.1 | **MAY** hash the application's own files against a signed manifest at startup. It detects accidents and unsophisticated tampering and produces an audit signal | The check, and the signal |
| SD-11.2 | **MUST** document the bootstrap-trust limit in the same paragraph as the feature, and **MUST NOT** let it be quoted as prevention | The limit, next to the claim |
| SD-11.3 | **MUST** state the honest objective: on a host where the adversary has administrative privilege, every application-level control is ultimately defeatable | The stated objective |

The checker runs in the same trust domain as the thing it checks. Anyone who can edit the code on
disk can edit the manifest, the embedded key, or the verification routine; anyone who can alter the
runtime can stub it. The chain of trust terminates only in hardware measured boot, which is a
platform decision the operator makes. What is achievable is to make tampering noisy, costly and
detectable, and to push the trust root as low as the operator is willing to go.

### Operator-owned hardening: document and recommend, never claim

| ID | Requirement | Evidence |
|---|---|---|
| SD-11.4 | **MUST NOT** claim any of the controls below. They are stronger than anything above and none of them are yours | Their absence from your control list |
| SD-11.5 | **SHOULD** ship a hardening guide with concrete paths to monitor and example rules, so the operator has something to apply on day one | The guide |

- file-integrity monitoring against a baseline
- immutable or read-only deployment with writable state confined to the data store
- least-privilege file ownership so the running account cannot rewrite its own code
- confinement under a mandatory access control system
- signed-artifact admission control that rejects anything unsigned

### Roll out a blocking verification control in audit mode first

| ID | Requirement | Evidence |
|---|---|---|
| SD-11.6 | **SHOULD** start a blocking verification control in audit mode, confirm it resolves what it needs, then switch to enforce | The audit-mode period |

A control that rejects artifacts failing verification will also reject valid ones whenever its own
preconditions are unmet -- for instance when the enforcing component cannot reach the store holding
the signatures. The alternative is a rollout that blocks legitimate deployments on day one and gets
switched off permanently as a result.

---

## 12. Vulnerability response, exercised

A response program is a process control, not a document.

| ID | Requirement | Evidence |
|---|---|---|
| SD-12.1 | **MUST** operate a defined private intake channel | The channel |
| SD-12.2 | **MUST** set severity-banded remediation windows, and state where the clock starts next to each one | The bands, with clock starts |
| SD-12.3 | **MUST** run a root-cause review for significant findings, feeding systemic causes back into the standard | The review, and the resulting edit |
| SD-12.4 | **MUST** disclose in coordination after a fix exists | The disclosure |
| SD-12.5 | **MUST** exercise the machinery end to end at least once as a dry run | A dated dry run |

SD-12.5 is the part usually missing, and the part that finds the broken intake address before a
real reporter does. On SD-12.2, the two obvious clock starts give very different numbers: measuring
from your own triage is right for your own defects, and measuring from the point an upstream fixed
version exists is right for a third-party advisory, because a clock started at triage runs against
something you cannot act on. Pick per finding class, say which, and track the waiting period so an
unfixable advisory is visible rather than silently blowing a window.

### What actually closes a finding

| ID | Requirement | Evidence |
|---|---|---|
| SD-12.6 | **MUST** close a finding by the check that produced it going green on the commit containing the fix -- not by the fix merging, and not by a later full-suite run being green. **[prompted by: 800-53 SI-2b]** | The confirming run |
| SD-12.7 | **MUST** make the confirming run a mirror copy of the original: same check, same ruleset, same scope. **[derived: 800-115 section 8.3]** | The two run configurations |
| SD-12.8 | **MUST** record the finding identifier, the fix commit, and the identifier of the confirming run | Three fields per closed finding |
| SD-12.9 | **MUST NOT** close a finding by adding a suppression. A suppression routes it into [section 16](#16-the-release-gate)'s suppression review | The suppression list |
| SD-12.10 | **MUST** measure time-to-remediate against the windows you set, then label the windows project-set. **[derived: 800-53 SI-2(3)]** | Identification and remediation dates per finding |

A merged fix is a change with an intention attached. A green suite establishes that the suite
passed, not that this finding's detector ran and changed its verdict. The third field in SD-12.8
carries the weight: a reviewer can resolve a run identifier to a verdict and cannot resolve the word
"fixed" to anything at all.

Two ways this fails. The check is never re-run because it only fires on a schedule -- for a blocking
check the retest is automatic, so the manual work is entirely in the scheduled and advisory jobs,
which are exactly the ones nobody re-runs on purpose. Or the finding is closed by a suppression,
which improves the closure count while worsening the posture. Every finding ends in one of two
places: closed by retest, or held under a dated signed acceptance. A finding in neither is an open
item wearing the costume of a closed one.

### The producer half: an intake a reporter can find, and an advisory a tool can read

| ID | Requirement | Evidence |
|---|---|---|
| SD-12.11 | **MUST** publish a security contact at a documented address, a policy file where the source host surfaces it, and a stated acknowledgment time | The three published items |
| SD-12.12 | **MUST** say what you will not do in the same place: no payment, no bounty, no timeline beyond the bands, and whether a reporter is credited | The published terms |
| SD-12.13 | **MUST** publish the windows with the clock start next to each one, labelled project-set | The published windows |
| SD-12.14 | **MUST** ship an advisory per fixed vulnerability on a channel machines read, carrying affected and fixed versions, the impact in one sentence, any configuration mitigation, and a stable identifier | The advisory, in the feed |
| SD-12.15 | **SHOULD** file in the ecosystem's public advisory database, which is what puts the entry into the feeds a blocking dependency audit consumes | The database entry |
| SD-12.16 | **MUST** decide and write down the threshold for what gets an advisory | The written threshold |
| SD-12.17 | **MUST** set a maximum embargo, and state the point at which you publish with or without a fix | The stated maximum |

What is published is where to send a report, never the reports. Requiring an account, a login or a
form to file is the same defect as an unmonitored address: a channel that exists and does not work.
A changelog line is not an advisory -- nothing in an adopter's tooling reads prose. A project that
has issued no advisory has usually never decided rather than decided not to, and those two look
identical from outside.

**Limits.** **An advisory tells an adopter a fix exists. It does not deploy it.** Released is not
deployed, and deploying is the operator's column. And **this is a producer's disclosure path, not
an incident response program**: incidents are generated by running the software.

---

## 13. Deviations and risk acceptance

| ID | Requirement | Evidence |
|---|---|---|
| SD-13.1 | **MUST** write down every place current practice differs from what the standard requires, rather than quietly redefining the requirement | A register entry with all four fields |
| SD-13.2 | **MUST** date and sign each acceptance. A register of accepted risks is not governance on its own | The signature and the date |
| SD-13.3 | **MUST NOT** publish the register, or reconstruct it in generalized form | The register kept, not shipped |
| SD-13.4 | **MUST** state each added practice's normative force, and say in the same paragraph that it introduces no new blocking gate and weakens no existing requirement | The marking on the addition |

| Field | Why |
|---|---|
| The control not met, and the date the risk was accepted | An undated deviation cannot be aged |
| The compensating controls actually in force | Distinguishes a decision from a gap |
| The trigger that ends it | A deviation with no trigger is a permanent excuse |
| A pointer to where the intended shape is written down | So the fix is designed, not improvised later |

One entry filled in, for an invented single-maintainer project. Illustrative only -- it is **not
this document's own register**, which SD-13.3 forbids publishing:

| Field | Entry |
|---|---|
| The control not met, and the date the risk was accepted | SD-4.1, peer review by a second reviewer, accepted 2026-01-15 |
| The compensating controls actually in force | Blocking static analysis and dependency audit that cannot be waived, AI-run review a human arbitrates, branch protection with required checks, and no direct pushes to the trunk |
| The trigger that ends it | A second maintainer joins |
| A pointer to where the intended shape is written down | [Section 4](#4-review-and-what-to-do-when-there-is-no-second-reviewer), including SD-4.3 |

An unsigned acceptance is an un-accepted open gap wearing the costume of a decision, and a release
gate that leans on one is not a gate. A register enumerating which controls are absent, which are
off by default, and what is holding each one safe is an operational document with a narrow
audience -- and a generalized version of it is the same artifact with the names filed off.
Additions without the SD-13.4 marking either get treated as mandatory and stall adoption, or get
ignored and quietly hollow out the document.

---

## 14. Re-evaluate on a trigger, and on a short calendar for what has no trigger

Every gate in this document is release-triggered, so a project that ships nothing for a year runs no
security review in that year. Three ways a control degrades leave no trace a per-change gate would
see: a suppression added, a job flipped from blocking to advisory, and a deviation whose ending
trigger fired while its compensating control quietly became permanent.

| ID | Requirement | Evidence |
|---|---|---|
| SD-14.1 | **MUST** run a recurring pass on a stated cadence, doing exactly the four things below. **[derived: 800-53 CA-7b]** | A dated entry per pass recording what was checked and what changed |
| SD-14.2 | **MUST NOT** grow the pass beyond four items | The item count |
| SD-14.3 | **MUST** amend [section 1](#1-shared-responsibility-write-the-split-down-first)'s data-class table on the event, not the calendar: a change that adds a data class, gives a class a new resting place, or adds a boundary | The amendment in the same change |

1. Sweep the deviations register for entries whose ending trigger has already fired, and for
   entries not reviewed since the last pass.
2. Re-confirm from the blocking-job list, not from a badge, that every check in the unwaivable set
   still blocks.
3. Confirm the scanner suppression list has not grown unreviewed.
4. Check whether a trust boundary now exists with no threat model.

Set the cadence yourself and label it project-set. Hold it to four: a periodic pass in a small team
dies by growing, and an unrun scheduled control is worse than an absent one because it still looks
green from outside. The cadences named in [section 10](#10-build-and-release-integrity) are their
own schedules against their own artifacts; folding them in here is the growth SD-14.2 forbids.

Prefer an event trigger wherever an event exists. A trigger tied to a change fires when the answer
actually changed and leaves the diff as its own evidence; a calendar reminder is the first thing
dropped in a busy month. SD-14.3 is the only new gate row this section introduces, and it is
answerable from a diff rather than from a judgment.

---

## 15. Independent external verification

| ID | Requirement | Evidence |
|---|---|---|
| SD-15.1 | **MUST NOT** treat any internally-run control as a substitute for third-party source review and penetration testing. **[prompted by: 800-53 CA-8(1)]** | The gap, stated |
| SD-15.2 | **MUST**, where the engagement has not happened, say so plainly and hold the gap under a dated signed acceptance, with the order-of-magnitude cost | The acceptance |
| SD-15.3 | **MUST NOT** gate an adopter's deployment on your engagement. Record what has and has not been verified; the decision to deploy is theirs | The wording |

Their absence caps what you can honestly claim, no matter how good the automated layer is. A bare
"not yet performed" reads as negligence; "not yet performed, and here is the order of magnitude it
would cost" reads as a funding constraint a reader can evaluate.

**A correction, recorded rather than quietly fixed.** Dynamic testing was named in SD-15.1's
sentence in an earlier version of this material. That was wrong, and it mattered: it let a reader
believe dynamic testing was unavailable without funding. A developer-run malformed-input harness
costs runner minutes rather than money -- SD-2.4 describes it and SD-5.6 says when it runs. An
earlier version also stated independent review as a precondition for production exposure, which is
over-reach for software the producer does not operate; SD-15.3 is the corrected form.

### Write the engagement down before it starts

| ID | Requirement | Evidence |
|---|---|---|
| SD-15.4 | **MUST** scope the engagement in writing, reviewed and approved before work begins -- what is under assessment, the procedures, the environment, the team and the roles. **[derived: 800-53 CA-2b, CA-2c]** | The approved plan, dated before the work |
| SD-15.5 | **MUST** agree countersigned rules of engagement before testing commences. **[derived: 800-115 Appendix B]** | The countersigned document |
| SD-15.6 | **SHOULD** write the scope even if the engagement is never funded | The scope, attached to the SD-15.2 acceptance |

The rules of engagement template that survives: the objective and what is explicitly out of scope;
the environment and authorized test site; the artifacts you hand over up front, including threat
models and the deviations register; named contacts on both sides including incident response;
permitted testing hours; risks and agreed mitigations; what data the tester may encounter and how it
must be handled and destroyed; and how findings are delivered and disclosed.

The data-handling clause is the one teams skip and the hardest to repair afterwards.
[Section 1](#1-shared-responsibility-write-the-split-down-first)'s data-class table is what makes it
specific rather than generic. An unscoped engagement produces a report you cannot use: a finding
whose scope was never agreed cannot be traced to a boundary, and cannot be closed under SD-12.6
because there is no agreed original for a confirming run to mirror. Scope is also what an engagement
is priced on, so SD-15.6 is the difference between comparable bids and a surprise.

If you are running a formal assessment against a published verification standard, the method is in
[running a large security-standard assessment with AI agents](../ASVS-ASSESSMENT.md) -- verdict
vocabulary, why `unverified` must never read as a pass, evidence anchors a machine can re-check,
corpus pinning, and how to read a movement in a score. Do not build a second procedure beside it.

---

## 16. The release gate

| ID | Requirement | Evidence |
|---|---|---|
| SD-16.1 | **MUST** codify the gate as an explicit pass or fail list rather than a judgment | The list below |
| SD-16.2 | **MUST NOT** let the gate lean on an unsigned acceptance, or it is not a gate | Signatures on every acceptance it counts |
| SD-16.3 | **MUST NOT** treat any single row as the gate. The composite is | The gate read whole |

The list:

- Automated blocking checks passing on the exact commit being released.
- No unresolved high or critical findings.
- Current independent-review status, or a signed risk acceptance standing in for it.
- Updated evidence.
- A signed artifact with its component inventory and digest manifest attached to the tag.
- [Section 1](#1-shared-responsibility-write-the-split-down-first)'s data-class table current as of
  the last change that added a class, gave a class a new resting place, or added a boundary.

**Limit:** "no unresolved high or critical" is only as honest as the scanner baselines behind it. It
says nothing if the baseline was set on a weak ruleset, or if advisory jobs were miscounted as
gating coverage.

### Confirm the control plane before reading any code

| ID | Requirement | Evidence |
|---|---|---|
| SD-16.4 | **MUST** confirm, for each required check and before reading any source, that it exists, that it blocks rather than advises, and that it was green on the exact commit being released | The blocking-job list, not a badge |
| SD-16.5 | **MUST** review the scanner suppression list explicitly rather than accepting it | The reviewed list |
| SD-16.6 | **MUST** mark which nominally-security jobs are advisory, and not count those as coverage | The marking |

A suppressed rule class is a control that has been turned off. Only once the control plane is
confirmed is line-by-line reading worth spending on what the automated controls cannot cover.

---

## 17. What you may claim

| ID | Requirement | Evidence |
|---|---|---|
| SD-17.1 | **MAY** claim **built to**, **aligned with**, and **self-assessed against**, each backed by evidence and each about this document and your own process | The evidence behind each |
| SD-17.2 | **MUST NOT** claim **certified**, **verified**, or **compliant** | The wording |
| SD-17.3 | **MUST NOT** claim alignment with a publication as a whole. "Aligned with" is available only against a named control identifier | A claim checkable against one paragraph |
| SD-17.4 | **MUST** state the attestation posture positively, with its scope named | "This project attests that it builds under this standard" |
| SD-17.5 | **MUST** say near the top what the standard does not confer: no compliance, certification or fitness on the product, on you, or on an adopter, and no substitute for an adopter's own assessment | The statement, structurally placed |
| SD-17.6 | **MUST** say so where you borrow discipline from a regime you are not subject to: adopted by analogy and voluntarily | The wording |
| SD-17.7 | **MUST NOT** restate another document's assurance-level target, count, or score. Name the record of record and link to it | One place that can be wrong |
| SD-17.8 | **MUST** cite a proposed requirement as proposed, framed "if finalised" every time, and record the date you last checked its status | The dated check |

Writing "certified" is the fastest way to have the whole page discounted. SD-17.3 fails in both
directions: not "aligned with SP 800-53", which claims a catalog of a thousand controls nobody
assessed, and not "built to SP 800-218", which is the same defect wearing the register's own
vocabulary and close to the wording a federal secure-software attestation turns on. Naming four
publications on this page does not enlarge what may be claimed at the bottom of it. SD-17.7 is the
state-it-once rule applied to the class of fact where being wrong is most expensive: two documents
that each restate the other's target will eventually disagree, and both will look authoritative.

The general rule, with honesty-state tagging and the claims register, is in
[CI and standards](../CI-AND-STANDARDS.md).

---

## In one table

The rules you reach for most often, by the moment you need them. It is an index, not the full set --
the sections carry rules this table does not.

| When | Rule | ID |
|---|---|---|
| Starting | Write the producer-versus-operator split before claiming any control | SD-1.1 |
| Starting | Never list an operator-side control as one you provide | SD-1.3 |
| Starting | List the services neither column owns, and what fails if one goes away | SD-1.4 |
| Starting | Define restricted data once, as classes and every place each one rests | SD-1.6 |
| Designing | Threat model each trust boundary before the build; name a mitigation for each way in | SD-2.1, SD-2.2 |
| Designing | Bound resource consumption per boundary; an unbounded boundary is a finding | SD-2.3 |
| Designing | Draw the boundary list; a diagram with no boundaries marked is not a security artifact | SD-2.5, SD-2.6 |
| Designing | At an execution boundary, check every caller reaches the vet, not the documented one | Section 2 |
| Coding | Validate at ingress, parameterise every query, confine every path, fail closed | SD-3.1 to SD-3.7 |
| Reviewing | Self-review is a documented deviation, not a satisfied control | SD-4.2 |
| Reviewing | Never let the compensating set be described as an independent audit | SD-4.3 |
| Reviewing | Reject code you cannot explain; verify the assistant's explanation too | SD-4.4, SD-4.5 |
| Gating | Coverage is the blocking checks that run on the change, not the tool count | SD-5.1 |
| Gating | Static analysis, dependency analysis and secret scanning block, unwaivable by the author | SD-5.2 to SD-5.5 |
| Gating | Trigger a dynamic pass on an event; when none fires, record that nothing ran | SD-5.6, SD-5.7 |
| Gating | A clean run is a start condition for red-on-regression, never a certificate | SD-5.9 |
| Gating | Fire the failure class at the gate before crediting its green | SD-5.10 |
| Gating | Encode a control as one shared check across sibling paths | SD-5.11 |
| Gating | Record rigor and scope separately per blocking check; one green hides both | SD-5.12 |
| Configuring | Secure by default; every insecure posture is a named, audited, fail-closed opt-in | SD-7.1, SD-7.2 |
| Configuring | Off-by-default and fail-closed are different states -- describe them apart | SD-7.3 |
| Configuring | Synthetic data outside production; live data raises the environment, not lowers the class | SD-7.4, SD-7.5 |
| Configuring | Rate a collection by the highest class in it, never the average or per entry | SD-7.6 |
| Authenticating | Strongest mechanism the peer supports, recorded per connection | SD-8.1, SD-8.2 |
| Authenticating | No long-lived secret in a file; no cleartext directory bind | SD-8.6, SD-8.7 |
| Logging | Append-only, hash-chained, actor-attributed; no secrets or restricted data at info level | SD-9.1, SD-9.2 |
| Logging | State what happens when the log cannot be written; a broken chain reads as tampering | SD-9.4 |
| Logging | Ship the query, export and chain-verify affordance; the review cadence is the operator's | SD-9.5, SD-9.7 |
| Releasing | The release build runs on an ephemeral runner, never on a developer workstation | SD-10.1 |
| Releasing | Enumerate every principal that can write, administer or publish; review and prune it | SD-10.4 |
| Releasing | Pin every action, image and tool by digest, and review the pinned set on a cadence | SD-10.5 |
| Releasing | Short-lived workflow-bound publishing credentials, paired with an attestation over the digest | SD-10.6, SD-10.8 |
| Releasing | Publish a signed digest manifest and document the offline verification path | SD-10.12 |
| Releasing | A component inventory answers "do we ship X" -- it is not tamper detection | SD-10.13 |
| Releasing | Archive the artifact, its build inputs and its inventory; back it up off-platform and restore once | SD-10.14, SD-10.15 |
| Releasing | Verify the published artifact after release; what you built is not what shipped | SD-10.16 |
| Hardening | An in-process integrity check detects accidents, never a privileged attacker | SD-11.1, SD-11.2 |
| Hardening | Operator-side controls are documented and recommended, never claimed | SD-11.4 |
| Hardening | Roll out a blocking verification control in audit mode first | SD-11.6 |
| Responding | Rehearse the response program end to end; state where each clock starts | SD-12.5, SD-12.2 |
| Responding | A finding closes when its own check goes green on the fix commit, not when the fix merges | SD-12.6 |
| Responding | The confirming run is a mirror copy; a suppression is a suppression, never a closure | SD-12.7, SD-12.9 |
| Responding | Publish the intake, the bands and the clock start; an unmonitored address is not a channel | SD-12.11, SD-12.13 |
| Responding | Ship an advisory per fixed vulnerability where tooling reads it; a changelog line is not one | SD-12.14 |
| Accepting risk | Dated and signed, with a trigger that voids it. Unsigned is an open gap | SD-13.1, SD-13.2 |
| Accepting risk | Publish the rule, not the inventory of what is currently absent | SD-13.3 |
| Re-evaluating | Four items on a stated cadence; hold it to four or nobody runs it | SD-14.1, SD-14.2 |
| Re-evaluating | Event-trigger the data-class table instead of adding a fifth calendar item | SD-14.3 |
| Verifying | Nothing internal substitutes for third-party review and penetration testing | SD-15.1 |
| Verifying | Scope an external engagement in writing, countersigned and approved before work starts | SD-15.4, SD-15.5 |
| Shipping | The gate is a list with a defined failure mode, and no single row is the gate | SD-16.1, SD-16.3 |
| Shipping | Confirm the control plane -- present, blocking, green on this commit -- before reading code | SD-16.4 |
| Claiming | Built to, aligned with a named control, self-assessed against -- never certified | SD-17.1, SD-17.2 |
| Claiming | Never align with a publication as a whole, only with a named control | SD-17.3 |
| Claiming | Never restate another document's target or score; link to the record of record | SD-17.7 |

---

## Retired rules

A rule that goes away gets a row here rather than being deleted, and its identifier is never issued
again. Retiring costs one row; reusing an identifier silently repoints every citation written
against it, including ones in registers you do not control.

| Retired | Date | Why, and what replaced it |
|---|---|---|
| -- | -- | No rule has been retired yet. This table is the format, waiting for the first one |

---

## Adapting this to your project

Change freely:

- **The section set.** Drop what you do not have. A project with no network interfaces does not need
  [section 8](#8-machine-to-machine-authentication), and saying so beats an empty heading that reads
  as an unowned control.
- **The authentication hierarchy.** Keep the property -- strongest available, recorded per
  connection, weak ones as an explicit short list -- and replace the mechanisms.
- **The remediation windows.** There is no validated number. Set yours from your own capacity and
  label them project-set.
- **Everything platform-specific.** Managed service identities, transparency logs, admission control
  and integrity monitoring differ per platform. Name the one you use.
- **The adoption order.** Sections 1, 5 and 13 are the cheapest and highest-leverage. After those,
  take whatever your riskiest surface demands.

Do not weaken:

- **The ownership split, in either direction.** Claiming an operator-side control is over-reach.
  Pushing a producer-side control onto the operator is abdication.
- **The single definition of restricted data.** Two terms for one idea is how a rule ends up
  enforced in one section and quietly absent from its sibling. The fix is to delete the second term,
  not to define it as well.
- **The unwaivable set.** The moment one of the three becomes waivable it stops being a control and
  becomes a preference.
- **The deviation format.** Dropping the date makes it unageable; dropping the trigger makes it
  permanent; dropping the signature makes it an open gap. All three, or none of it counts.
- **The claim register.** "Certified" is not a stronger synonym for "self-assessed against". It is a
  different and false statement, and it is the one a reader will check.
- **The Limit lines.** Each names a control resting on a false premise if you delete it: an
  in-process integrity check without the bootstrap-trust limit, an inventory described as tamper
  detection, a self-assessment described as verification. The next person reasons from your
  description rather than from the code.

---

## Where the rules come from

Most of this page is this document's own reasoning about what a small producing team can execute.
Where a rule was borrowed, the mark on it names the source; [Sources](#sources) carries each
publication's status, its date, and the date that status was last checked, in one table so a
re-check is a single edit.

- **NIST SP 800-218 v1.1 (SSDF)** -- the only one written for a producer rather than an operator, so
  it is the outcome layer. No rule here carries an SSDF mark: where a rule restates one of its
  outcomes, the text actually read was an 800-53 control, and the mark points at the publication
  that was opened.
- **NIST SP 800-53 Rev. 5**, as maintained by Release 5.2.0 -- the quotable control text where the
  SSDF states only an outcome, cited by control identifier.
- **NIST SP 800-115** -- process material only: the rules-of-engagement template, and the caveat
  that a retest verifies a fix only if the confirming run mirrors the original.
- **FIPS 199** -- one page of vocabulary: three security objectives at three impact levels, plus the
  high-water-mark roll-up.

**Name the release, not just the revision, and record the date you checked.** "SP 800-53 Rev. 5"
today names two artifacts that disagree: the PDF served under that title carries content dated
September 2020, while Release 5.2.0 of 2025-08-27 adds SA-24, SI-02(07) and SA-15(13) and revises
SI-07(12), with the file name and title unchanged. So "SA-24, SP 800-53 Rev. 5" is simultaneously
correct and unresolvable by a reader who downloads the publication. The sibling rule for any revised
publication: carry the revision, because a bare identifier can resolve to a superseded document that
still says something plausible.

**Naming these sources is not a conformance claim, and cannot become one.** This document claims
conformance with none of them, and none of them certify anything. Quoting a control's text is not a
claim of conformance to the catalog it came from -- SD-17.3 is the register that governs the
wording. For 800-53 in particular, conformance means a selected control baseline plus an
authorization decision, and a software producer makes neither, so the baselines, the tailoring
apparatus and the risk management framework are all out of scope. Only named control text is
borrowed.

### Full conformance is not on offer, so tailoring is not a compromise

The SSDF has no conformance criteria, no levels and no assessment procedure. Nothing issues a pass.
So the familiar advice -- aim for a tailored subset rather than one hundred percent conformance --
understates the position: full conformance is not a thing that exists to be aimed at.

What that does not license is dropping a practice. Tailoring happens at the implementation layer --
which mechanism satisfies an outcome -- far more than at the practice layer. A memory-safe language
changes which vulnerability classes you face, and therefore how you satisfy the analysis and testing
practices; it does not remove them. The artifact of tailoring is a written record of what you left
out and why, which is what
[the table below](#what-this-document-does-not-take-from-a-control-catalog) is.

### The one setting where such a claim is a legal instrument, and its expiry date

Selling software to the US federal government used to be the clean answer to when conformance binds
a producer. Executive Order 14028 led to OMB Memoranda M-22-18 and M-23-16, which required agencies
to obtain a secure-software-development self-attestation on a common form published by CISA in March
2024.

That government-wide requirement was rescinded on 2026-01-23 by OMB Memorandum M-26-05, which states
that M-22-18 and M-23-16 "are hereby rescinded". Agencies "may choose to use" the form; none is
required to collect it. Two things follow, pulling in opposite directions. Advice written before
2026 saying you must sign the form to sell federally is now wrong, and still widely circulated. And
**this is not a relaxation** -- the memorandum moves the obligation onto each agency head, and an
individual agency may still require an attestation by its own policy or contract.

OMB's stated reason is worth reading if you are deciding how much rigor to adopt: the prior approach
"imposed unproven and burdensome software accounting processes that prioritized compliance over
genuine security investments". That is the argument of the subsection above, made by the party that
had imposed the mandate.

**What did not change is the exposure on any attestation you do sign.** A signed attestation is a
representation to a customer, and in the federal setting a false one carries civil fraud exposure
whether or not anyone required it. The rescission removed a requirement to make the statement. It
did nothing to the consequences of making a false one.

*Memorandum text read directly and verified 2026-08-06.*

---

## What this document does not take from a control catalog

A reader arriving with the SSDF or SP 800-53 in hand has two ways in. For what was borrowed, the
marks in the body are the index. This table is the other half, and the half nobody writes down: the
areas a catalog covers that this document deliberately takes nothing from, and why. An absence then
reads as a decision rather than an oversight.

It is not a coverage map and there is nothing here to score. There is deliberately no table mapping
this document's rules onto a catalog's controls, because a reader would read one as a scorecard
whatever it said about itself. The 800-53 rows name controls as they stand in Release 5.2.0.

| Control or practice | What it asks for, in one line | Why nothing here is taken from it |
|---|---|---|
| 800-53 AC-5 | Separation of duties, divided among individuals | Requires two qualified individuals. Section 4 models the right treatment of a control a small team cannot meet: name it, record the deviation, never redefine it until it fits |
| 800-53 AT family | Security awareness and role-based training, with completion records | SD-4.4's comprehension bar is the right-sized substitute. A training program beside it is a second record of one obligation, which SD-17.7 forbids |
| 800-53 AU-9(1), AU-10 | Write-once media for audit records; non-repudiation | Operator infrastructure, orders of magnitude above the threat a small producer defends against. Section 9's hash chain is the right assurance level here |
| 800-53 CA-6, and the SP 800-53B baselines | Select and tailor a control baseline, then authorize the system to operate | Meaningless to a producer who does not operate the system. An adopter who follows the citation upstream spends weeks and ends with a document describing an organization they are not |
| 800-53 CM-5(4) | Dual authorization for changes | Two qualified individuals again. Section 13 is where a solo maintainer records it |
| 800-53 CP-2, CP-4 | A contingency plan for the system, and testing of it | Continuity of a running deployment is the operator's column. Only SD-10.15 crosses over, and it says in the same paragraph that it does not cover a deployment's data |
| 800-53 IR-1 to IR-8 as a program | An incident response capability with handling phases, training, testing and reporting | Incidents are generated by running the software, which is the operator's column. Section 12 carries the producer-scoped slice |
| 800-53 MA family | Controlled maintenance, personnel, tools, nonlocal maintenance | Assumes an owned hardware estate and identified technicians. Forcing an analogue onto a workstation and a hosted runner produces a control satisfied by definition, which is what SD-5.10 exists to catch |
| 800-53 PE family | Facility perimeter, physical access, visitor control, environmental protection | No facility to evidence it against. The part that matters -- physical access to the build machine -- sits with the build service, which SD-1.4 names and does not claim |
| 800-53 PM family | An organizational security program: senior officials, enterprise architecture, a risk executive | No small-team version exists. Only a solo maintainer writing an organization chart that does not |
| 800-53 PS family | Personnel screening, termination and transfer, formal sanctions | Employment controls belong to the adopting organization. A two-person team screening itself is theater |
| 800-53 RA-3, RA-9 | A standing risk assessment and a criticality analysis, as separate artifacts | Section 2's per-boundary threat model carries the part a producer can act on, and is better targeted because it is checkable one boundary at a time |
| 800-53 SR-11, and the physical supply-chain controls beside it | Component authenticity and anti-counterfeit; shipping, handling, tamper checks, disposal | Hardware controls. The software supply-chain content a producer can evidence is in section 10, and is stronger there than a mapping would make it |
| Third-party agreements | Contractual terms binding a service that handles your data | A small team on a provider's standard terms has nothing to negotiate, and a clause it cannot enforce is a compensating control resting on a false premise. SD-1.4 records the trust and the failure mode instead |
| Assessment determination statements | Per-control determination statements, assessed by examine, interview and test | Converting a standard a team builds to into an audit program a team is subjected to changes what the document is for. Section 15 forbids a second procedure beside this site's own method |
| System categorization | Assign an overall impact level to a system | Over-reach. This document categorizes data classes, a property of the code it ships. The deployed system's category is the adopting organization's to assign |
| SP 800-115 technique and tooling inventory | Named scanning, sniffing, password-cracking and review techniques | From 2008; only its process material is durable |
| Social engineering testing | Phishing simulation, pretexting, physical-access attempts against people | Targets an organization's staff and premises, not a build. SD-15.4 requires the scope to state what is out of scope, which is where a decision either way gets recorded |

---

## Sources

The record of record for the four publications named above. Status and dates live here and nowhere
else, so a re-check is one edit.

| Short code | Publication | Status and date | What it uniquely contributes | Status last checked |
|---|---|---|---|---|
| `SSDF <practice>` | NIST SP 800-218 v1.1, Secure Software Development Framework | Final, February 2022 | The producer-facing outcome layer. PW.8 (test executable code, including fuzzing tied to intended use), PO.3 (define and maintain the toolchains) and PO.5 (a secure environment for developing and building) stand behind SD-2.4 and section 10's build-environment rules | 2026-08-06 |
| `800-53 <CONTROL>` | NIST SP 800-53 Rev. 5, Security and Privacy Controls for Information Systems and Organizations, as maintained by Release 5.2.0 | Rev. 5 final, content dated September 2020 with updates as of 2020-12-10; Release 5.2.0 issued 2025-08-27 | Quotable control text, cited by identifier on the rule that restates it. Controls held out of the body by the one-mark-per-rule cap: SA-11 base, SA-11d, SA-11e, CM-5(1), SC-28(1), SC-28(3), SI-12, CA-2d, CA-7c, CA-8, CP-9(1), CP-9(2), AU-6(3) | 2026-08-06 |
| `800-115 Appendix B`, `800-115 section 8.3` | NIST SP 800-115, Technical Guide to Information Security Testing and Assessment | Final, September 2008 | Process material only: the rules-of-engagement template (Appendix B) and the caveat that a retest verifies a fix only if the confirming run mirrors the original (section 8.3) | 2026-08-06 |
| `FIPS 199` | FIPS 199, Standards for Security Categorization of Federal Information and Information Systems | Final, February 2004 | Three security objectives at three impact levels, and the high-water-mark roll-up behind SD-7.6 | 2026-08-06 |

A publication's presence here says only that a rule on this page borrowed from it. It is not a claim
of conformance with any of them, and none of them certify anything.

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
