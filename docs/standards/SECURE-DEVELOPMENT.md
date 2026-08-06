# Secure development: the process a build must satisfy

This is a starting point you adapt, not a compliance attestation. It describes the process a build
has to satisfy before you can honestly say it was built securely.

It answers who owns what, what gets threat modelled, and what a review checks. It also answers which
checks may never be waived, how a release is signed and verifiable, and what has to be true on the
day you ship.

> **Take a copy:**
> [markdown](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/SECURE-DEVELOPMENT.md)
> or [Word document](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/SECURE-DEVELOPMENT.docx).
> [Every file, both formats](OVERVIEW.md#the-files).

It is deliberately framework-neutral, and it names practices, never certifications. No standards
body issues a certificate for any of this, and a self-assessment is not one either. So every claim
here is phrased as something you can evidence rather than something you can be awarded.

Written for a project where much of the code is written by Claude Code, or another AI coding
assistant, and several sessions push into one trunk. That is not a special case for this material.
It is the case where the process layer stops being paperwork, because the machine-enforced layer
gets cheap and the human layer does not.

---

## What you get

- **A written ownership split.** One table saying what the producing project owns and what the
  operating organization owns, so a control cannot end up unowned because each side assumed the
  other had it.
- **Review with something to check against.** A per-interface threat model turns "does this change
  look secure" into "which boundary does this touch, and does its named mitigation still hold". A
  missing control then shows up as a gap in an enumeration rather than as something nobody thought
  of.
- **A finite secure-coding list.** A reviewer, human or automated, gets a bounded set of questions
  instead of an unanswerable one.
- **An honest read of your own pipeline.** Two layers, weighted differently, with a plain statement
  of what a green run has and has not established. Effort goes to the layer that is actually
  missing rather than to a ninth scanner.
- **A release gate that is a checklist, not a debate.** Defined pass and fail conditions, so the
  conditions under which you shipped are recoverable afterwards.
- **Artifacts an adopter can verify without trusting your description of your process** -- build
  provenance, an attestation over the artifact digest, a component inventory, a published digest
  manifest with the offline verification path documented.
- **A posture you can publish when you cannot meet every requirement.** Dated deviations, named
  compensating controls, and a trigger that ends each one -- instead of either overclaiming or
  quietly having a gap.
- **Wording that survives a reviewer.** Phrases you can use, phrases you cannot, and the reason, so
  publishing a security page does not accidentally assert a certification that does not exist.

## What this costs you

- **Calendar time in two places that resist automation.** Threat modeling happens before the build,
  and vulnerability response has to be rehearsed end to end at least once. Neither can be discharged
  by a passing check.
- **Controls you do not own and must not claim.** The strongest tamper controls -- file-integrity
  monitoring, immutable deployment, least-privilege file ownership, signed-artifact admission
  control -- belong to whoever runs the software. You can document and recommend them. Claiming them
  is a defect.
- **A gap you cannot close by working harder.** Independent external review and testing is the one
  control an internally-run pipeline cannot substitute for. In one project's planning, a single
  engagement at the highest assurance tier was budgeted in the tens of thousands of currency units.
  If you cannot fund it, the honest move is to say so and hold the gap under a signed acceptance --
  not to let a self-assessment read as verification.
- **No code ships with this.** No workflow, no scanner configuration, no template. The mechanics
  below are described so you can build them where you already run checks.

### Where this does not apply

- **Throwaway work.** A spike nobody installs does not need a threat model or a release gate.
  Applying the whole of this to code with no consumer is how a process gets abandoned wholesale.
- **Anything you are not the producer of.** If you operate software rather than publish it, most of
  the build and release sections are somebody else's obligation and the hardening sections are
  yours.
- **As a compliance position.** Building to this confers nothing on the product, on you, or on an
  adopter, and it does not substitute for an adopting organization's own assessment.

## How to adopt this

Start with the ownership split (section 1). One table, one sitting. It is the artifact that makes
every later claim scopeable, and most of the arguments it prevents are arguments about who was
supposed to do something.

Then work in this order:

1. **Ownership split.** Section 1.
2. **Threat model one interface** -- the riskiest, not all of them. Section 2. A single worked
   boundary teaches the format better than a sweep does.
3. **Make the scanner posture honest.** Section 5. Classify every nominally-security job as blocking
   or advisory before adding any new one. This usually reveals that coverage is narrower than the
   tool list suggested, at zero engineering cost.
4. **Write the deviations register.** Section 13. Start with what you cannot do today. A register
   written while you are still honest about the gaps is worth more than one written at review time.
5. **Build and release integrity.** Section 10. Short-lived publishing credentials, an attestation
   over the artifact digest, and a published digest manifest cover most of what an adopter needs.
6. **The release gate.** Section 15. Now that you know which checks block, the gate can be written as
   a list rather than a judgment.
7. **Rehearse vulnerability response.** Section 12. A dry run finds the broken intake channel before
   a real reporter does.
8. **The remaining sections** as they become relevant to what you build.

---

## The shape: two layers, and the second is where the defects are

Judge a build's security as a composite of two layers. Never on one row of either.

**The machine-enforced layer** is blocking analysis and secret-scan gates, secure coding practice,
dependency and supply-chain integrity, secrets hygiene, secure-by-default configuration, interface
authentication, and tamper-evident audit logging. It is hard to fake, because its evidence is a red
or green pipeline leg rather than a claim.

**The process layer** is an exercised vulnerability-response program, an independent external
challenge, a single honest verdict-of-record, and a release gate. None of it can be discharged by a
passing scanner. It needs a rehearsal, a signature, or an outside party.

**A green pipeline from a gate you ran on yourself does not substitute for an adversary who did
not.** Defects concentrate in the second layer, and a perfect first layer does not compensate for an
empty second one. Say that in the same breath as any claim about your automated coverage.

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

**Shipping the software confers nothing on the operator.** An attestation that the software was
built securely is an input to their assessment, never a substitute for it. State that where an
adopter will read it, not in a footnote.

The split also constrains what you may write elsewhere in this document. Anything in the right-hand
column is something you **document and recommend**. It never appears in a list of controls you
provide.

---

## 2. Threat model each interface before you build it

Every interface and component gets a written, lightweight threat model. It enumerates the trust
boundaries, names a mitigation for each ingress, and puts a constraining control on each piece of
dangerous functionality and each third-party component it pulls in.

Three properties make it worth writing:

- **Reviewed against the security requirements before code exists.** After the build it becomes
  documentation; before the build it is a design gate.
- **The specification the later review checks against.** The reviewed artifact plus its acceptance
  criteria are what a change is compared to -- without them, review has nothing but taste.
- **Artifact-checked and advisory, not a scanner.** Do not pretend otherwise: nothing mechanical
  verifies that a threat model is good, and a gate can only verify that one exists for a boundary
  that was added.

The highest-value form is boring: a list of every place unknown-provenance data or code enters, and
against each one the specific thing that bounds it. When a new ingress is added and nobody can name
its mitigation, that is the finding.

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

- **Validate structure and content of every inbound payload at ingress.** Reject or quarantine
  malformed input rather than processing it. An untrusted payload must be validated before it reaches
  a query, a file path, a subprocess, or a message you emit downstream.
- **Parameterised queries only.** No string-built statements anywhere, no exceptions held open by a
  comment.
- **Authentication and authorization enforced on every action, deny by default.**
- **For any interface that parses structured documents:** disable external-entity resolution and
  document-type processing, size-limit payloads against a schema, apply rate limits and timeouts, and
  never return internal detail in a fault response.
- **For file handling:** confine reads and writes to configured directories and canonicalise paths so
  traversal and symlink escapes are rejected. Validate type and size by content rather than
  extension. Write atomically then rename so a partial file is never processed. Never place files on
  an executable or served path, and never execute file contents.
- **Use vetted cryptographic libraries.** Never roll your own.
- **Fail closed on error.** Never log secrets or sensitive data.

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

### Three additions specific to a security posture

**A clean run is a start condition, not a certificate.** Zero findings on a weak ruleset proves
nothing at all. What the clean baseline buys you is the ability to enforce red-on-regression; that is
the whole of its value.

**Confirm the gate can see the class it exists to catch.** A green gate is evidence only once you
have fired the failure class at it and watched it go red. This is stated in full under *Attack the
control with the failure class it was built to catch* in
[CI and standards](../CI-AND-STANDARDS.md), and it applies to every check in this section.

**Enumerate the sibling paths.** A control implemented exactly where it was prompted, and missing on
its siblings, is the single most common residual after an agent-run security sweep. Encode the
control as one deterministic check shared across every path rather than as a habit applied per path.

### The security anti-metrics

The site already forbids gating on a single gameable number, with the general metric evidence. These
are the security-specific badges that impersonate a verdict. Each may be surfaced as advisory
context. None may ever be the pass or fail decision.

| Badge | Why it is not a verdict |
|---|---|
| Number of security scanners | A tool count. Advisory and scheduled-only jobs never redden a change |
| Finding count reaching zero | A start condition for red-on-regression. Zero on a weak ruleset proves nothing |
| A single percentage-pass headline from an assessment | Hides the composite, and moves when the standard revises its denominator |
| "Certified" phrasing against any framework | Describes a certificate that does not exist |
| Count of controls marked "built" | Built is not on-by-default is not fail-closed is not independently verified |
| A green pipeline, or a passing self-assessment | One input. No self-run gate substitutes for an outside challenge |
| "A risk register exists" | An unsigned acceptance is an un-accepted open gap wearing the costume of a decision |

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

**A path deny-list is not a content control.** It keeps a file from being read; it does nothing about
the same content typed into a different file. Pair it with a fail-closed commit-time content scan.

**A commit-time scanner is not a live interceptor.** It sees what lands in a commit. It does not see
an outbound query, a tool-server call, or a fetch argument.

Nothing mechanical stands between a running agent and that channel, so the discipline there is on the
human -- and the standard has to say so, rather than letting the green scanner imply coverage it does
not have.

---

## 7. Secure defaults, and the opt-in that must be explicit

Ship with transport encryption on, encryption of sensitive data at rest on, least-privilege accounts,
and verbose audit logging. Any insecure posture is an explicit, named, documented and audited opt-in
behind a fail-closed guard -- never a posture a deployment inherits by omission.

Two reading errors go with this, and both are defects in opposite directions.

**Off by default, described as active.** The code exists; nothing is running.

**Fail-closed, mis-read as inert.** It looks like nothing is happening because nothing needs to.

Score and describe those states separately, and state fail-open versus fail-closed next to the code
with the reason -- see *Fail-open or fail-closed is a choice you must state* in
[CI and standards](../CI-AND-STANDARDS.md).

---

## 8. Interface and service authentication

Machine interfaces authenticate **systems, not people**. Use the strongest mechanism the peer system
supports.

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

Across all of them: no cleartext transport for sensitive data; credentials in a secret store and
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
sensitive payloads out of it entirely at informational level and above.

An ordinary application log cannot tell an incident review whether the record was altered. A chained
one can, and it costs one hash per entry.

Where the deployment is exposed beyond a single trusted host, off-box forwarding over TLS is what
stops a compromise of the host from also erasing its own record. Record that as an
exposure-conditional requirement rather than an always-on one, so a local-only deployment is not
described as non-compliant for a control it does not need.

---

## 10. Build and release integrity

This is the part an adopter can check without trusting anything you say about your process, which is
what makes it worth more than the rest of your security page.

### Publishing controls, and the limit each one carries

**Publishing credentials.** Replace long-lived registry tokens with credentials minted per run from
the pipeline's own workflow identity, scoped to a specific repository, workflow and environment, and
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

Where consumers verify on restricted or disconnected networks, bundle the transparency-log inclusion
proof with the artifact so verification does not require network access.

**Measure whether a signing scheme is verifiable before crediting it.** Coverage and verifiability
are separate questions, and both can be near zero while the scheme is nominally in place.

**[external]** When one large package registry measured its long-standing detached-signature support,
only about a third of signing keys could be meaningfully verified, and signed files were a fraction
of a percent of everything published. Support was withdrawn, and existing signatures are now silently
ignored.

Before crediting a signing control, measure what proportion of artifacts carry a signature and what
proportion of those a consumer can resolve to an identity.

### What an adopter can verify without contacting you

**Build provenance.** Provenance generated by the pipeline proves the artifact traces to a specific
repository, workflow and commit rather than to somebody's machine. Isolating the build behind a
dedicated reusable workflow raises the assurance level further.

**A published digest manifest is the lowest-tech verification path.** Make it the documented baseline
rather than the afterthought. Publish a signed digest manifest with every release and document the
exact verification commands, including the offline path. That is the one route a reviewer on a
restricted network can always run.

**A component inventory is not tamper detection.** Generate one per release, in the formats your
consumers ingest, and attach it to the release and to the archived build.

Be precise about what it buys: answering "do we ship component X" within minutes of a
widely-publicised advisory, drift detection by diffing a produced inventory against the intended
manifest, and satisfying procurement reviews. It is not integrity evidence for your own code and must
not be quoted as such.

**Archive each release with its build inputs and its inventory.** Two things depend on it: incident
analysis -- what exactly was in the version somebody is running -- and reproducibility. An archive
holding only the artifact answers neither.

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
routine; anyone who can alter the runtime can stub it.

The chain of trust only terminates in hardware measured boot, which is a platform decision the
operator makes and not something the software ships. Ship the check as defense in depth, document the
limit in the same paragraph as the feature, and never let it be quoted as prevention.

**State the honest objective.** On a host where the adversary has administrative privilege, every
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

**State when the clock starts, next to the window.** The two obvious choices give very different
numbers. Measuring from your own triage is right for your own defects. Measuring from the point an
upstream fixed version exists is right for a third-party advisory, because a clock started at triage
runs against something you cannot act on.

Pick per finding class, say which, and track the waiting period itself, so an unfixable advisory is
visible rather than silently blowing a window.

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

## 14. Independent external verification

Third-party source review, penetration testing and dynamic testing are the only controls an
internally-run pipeline cannot substitute for. Their absence caps what you can honestly claim, no
matter how good the automated layer is.

Where the engagement has not happened, say so plainly and hold the gap under a dated signed
acceptance. Do not let a self-assessment read as verification, and do not omit the cost context.

A bare "not yet performed" with no explanation reads as negligence. But "not yet performed, and here
is the order of magnitude it would cost" reads as a funding constraint a reader can evaluate.

**Do not gate somebody else's deployment on your engagement.** For software an adopter self-hosts, the
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

## 15. The release gate

Codify the gate as an explicit pass or fail list rather than a judgment:

- Automated blocking checks passing on the exact commit being released.
- No unresolved high or critical findings.
- Current independent-review status, or a signed risk acceptance standing in for it.
- Updated evidence.
- A signed artifact with its component inventory and digest manifest attached to the tag.

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
class is a control that has been turned off. Mark which nominally-security jobs are advisory and do
not count those as coverage. Only then spend line-by-line reading on what the automated controls
cannot cover.

---

## 16. What you may claim

The register you have is **built to**, **aligned with**, and **self-assessed against**, each backed by
evidence. You do not have **certified**, **verified**, or **compliant**, and writing one of those is
the fastest way to have the whole page discounted.

The general rule, with the honesty-state tagging and the claims register that goes with it, is in
[CI and standards](../CI-AND-STANDARDS.md). Four things are specific to a security claim:

- **State the attestation posture positively, with its scope named.** "This project attests that it
  builds under this standard" is a claim you can support. "The output is independently audited" is
  not, unless it is.
- **Say what the standard does not confer, structurally and near the top.** It confers no compliance,
  certification, or fitness on the product, on you, or on an adopter, and it does not substitute for
  an adopter's own assessment. That is a statement about scope, not a disclaimer.
- **Where you borrow discipline from a regime you are not subject to, say so.** Adopted by analogy and
  voluntarily; producing the artifacts confers nothing.
- **Never restate another document's assurance-level target, count, or score.** Two documents that
  each restate the other's target will eventually disagree, and both will look authoritative. Name the
  record of record and link to it, so there is exactly one place that can be wrong.

That last one is the state-it-once rule applied to the one class of fact where being wrong is most
expensive.

**Cite a proposed requirement as proposed.** Where a standard or regulation is under revision, a draft
that has not been finalised is never a current requirement, and the frame is "if finalised" every time
it appears. Record the date you last checked its status -- that check is what goes stale, not the
citation.

---

## In one table

| When | Rule |
|---|---|
| Starting | Write the producer-versus-operator split before claiming any control |
| Designing | Threat model each interface before the build; name a mitigation per ingress |
| Designing | At an execution boundary, check every caller reaches it, not the documented one |
| Coding | Validate at ingress, parameterise every query, confine every path, fail closed |
| Reviewing | Self-review is a documented deviation, not a satisfied control |
| Reviewing | Name the compensating set and the event that ends the deviation |
| Gating | Coverage is the blocking checks that run on the change, not the tool count |
| Gating | A clean run is a start condition for red-on-regression, never a certificate |
| Gating | Fire the failure class at the gate before crediting its green |
| Gating | Encode a control as one shared check across sibling paths |
| Configuring | Secure by default; every insecure posture is a named, audited, fail-closed opt-in |
| Configuring | Off-by-default and fail-closed are different states -- describe them apart |
| Authenticating | Strongest mechanism the peer supports, recorded per connection |
| Authenticating | No long-lived secret in a file; no cleartext directory bind |
| Logging | Append-only, hash-chained, actor-attributed; no secrets or sensitive data at info level |
| Releasing | Short-lived workflow-bound publishing credentials, paired with an attestation over the digest |
| Releasing | Publish a signed digest manifest and document the offline verification path |
| Releasing | A component inventory answers "do we ship X" -- it is not tamper detection |
| Releasing | Archive the artifact, its build inputs, and its inventory together |
| Releasing | Verify the published artifact after release; what you built is not what shipped |
| Hardening | An in-process integrity check detects accidents, never a privileged attacker |
| Hardening | Operator-side controls are documented and recommended, never claimed |
| Hardening | Roll out a blocking verification control in audit mode first |
| Responding | Rehearse the response program end to end; state where each clock starts |
| Accepting risk | Dated and signed, with a trigger that voids it. Unsigned is an open gap |
| Accepting risk | Publish the rule, not the inventory of what is currently absent |
| Shipping | The gate is a list with a defined failure mode, and no single row is the gate |
| Shipping | Confirm the control plane -- present, blocking, green on this commit -- before reading code |
| Claiming | Built to, aligned with, self-assessed against. Never certified |
| Claiming | Never restate another document's target or score; link to the record of record |

---

## Adapting this to your project

**Change freely:**

- **The section set.** Drop what you do not have. A project with no network interfaces does not need
  section 8, and saying so beats leaving an empty heading that reads as an unowned control.
- **The authentication hierarchy.** It is ordered by what a peer system can support, and yours will
  differ. Keep the property -- strongest available, recorded per connection, weak ones as an explicit
  short list -- and replace the mechanisms.
- **The remediation windows.** There is no validated number. Set yours from your own capacity, record
  them where a reporter can read them, and label them project-set.
- **Everything platform-specific.** Managed service identities, transparency logs, admission control
  and integrity monitoring all have different names and different guarantees per platform. Name the
  one you use rather than implying the pattern is universal.
- **The adoption order.** Sections 1, 5 and 13 are the cheapest and the highest-leverage; after those,
  take whatever your riskiest surface demands.

**Do not weaken:**

- **The ownership split, in either direction.** Claiming an operator-side control is over-reach.
  Pushing a producer-side control onto the operator is abdication.
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

## Related

- [CI and standards](../CI-AND-STANDARDS.md) -- blocking versus advisory coverage, receipts, claim
  honesty, gate design, and the general metric evidence this document does not restate
- [The leak gate](../LEAK-GATE.md) -- fail-closed secret and forbidden-content scanning, and the three
  ways a scanner lies
- [Running a large security-standard assessment with AI agents](../ASVS-ASSESSMENT.md) -- verdict
  vocabulary, evidence anchors, corpus pinning, and reading a movement in a score
- [Case study: auditing a multi-session estate as one system](../CASE-STUDY-drift-audit.md) -- proving
  a fix by deliberate mutation of the shipped artifact
- [Tips and tricks](../TIPS-AND-TRICKS.md) -- section 4 on writing a guardrail, section 5 on measuring
  whether it works
