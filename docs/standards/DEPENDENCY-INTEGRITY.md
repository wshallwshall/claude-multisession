# Dependency and artifact integrity

Trusting what you did not write, and controlling what you ship.

Two questions, one document. **Inbound:** you import code you did not write, cannot fully audit, and
that changes underneath you -- how do you control that without reading it? **Outbound:** you publish
a build that other people install -- how do they know it is the thing you meant to send, and how do
you know it contains only what you intended?

> **This one is dense.** Reading it end to end works, and you will need to eventually -- it
> becomes your standard once you adopt it. It is usually faster to hand the
> [markdown](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/DEPENDENCY-INTEGRITY.md) to Claude Code, or
> another AI coding assistant, and ask it to summarize this against your repository,
> rewrite a section in plainer terms, or answer what already holds here and what would have to
> change.
>
> Reading or circulating instead? [Word document](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/DEPENDENCY-INTEGRITY.docx).
> [Every file, both formats](OVERVIEW.md#the-files).

The two halves share a shape. In both, the honest answer is not "review it harder". It is a small
number of machine-enforced controls, plus human attention spent at two or three specific moments
rather than spread thin across everything.

---

## What you get

- **A dependency discipline that never asks you to read library source.** Third-party code is a
  black box by definition. The controls below manage it as one -- identify, vet at adoption, test at
  your own boundary, surveil, pin -- so the obligation is finite instead of impossible.
- **Human effort concentrated at two moments.** Adopting a dependency and bumping its version. A
  few minutes of provenance work at adoption, a changelog-and-lock-delta read at each bump.
  Everything else runs unattended until it pings you.
- **A defense against a package name that looks right and is not.** Assistant-suggested imports make
  plausible-but-fake names a routine hazard rather than an exotic one, and the same check that
  catches a fabricated name also catches a typosquat of a real one.
- **An upstream behavior change that fails in your test suite instead of in production.** Tests
  written at the integration boundary are the black-box substitute for reading the code, and they
  turn a silent semantic change into a red bump.
- **A published build that contains only what you declared.** An allowlist checked before the upload
  step, because the upload is irreversible and an exclusion list ships whatever nobody thought to
  exclude.
- **A one-command verification story for whoever installs your build.** Published digests, build
  provenance tied to a repository and a commit, and an attestation over the artifact -- so an adopter
  can check what you shipped without contacting you or trusting your description of your own process.
- **Language given back to you for saying what these controls do not do.** Wording for the runtime
  tamper question that neither oversells a self-check nor pretends the problem is unsolvable.

---

## What this costs you, and where it does not apply

- **This document ships no configuration.** No workflow, no lockfile, no publishing pipeline. It is
  a set of rules and the failure each one answers.
- **Some of it is one ecosystem's mechanics, not a universal guarantee.** Lockfile semantics,
  install-time digest enforcement, audit tooling and registry attestation differ per language, and
  the differences are not cosmetic. *Which rules are universal, and which are one ecosystem's
  mechanics* below marks the line explicitly, and every ecosystem-specific rule is tagged where it
  appears.
- **Recurring cost is small but real:** a few minutes of due diligence per new dependency, a review
  per version bump, and one wiring exercise per manifest in the repository. Publishing controls are
  mostly a one-time pipeline change.
- **None of this detects a malicious release from a legitimate maintainer.** A compromised upstream
  that publishes a signed, canonically named, advisory-free release passes every control here. What
  they buy you is that the change is *pinned, surveilled and reviewable* rather than silent.
- **If you publish nothing, skip the outbound half.** If nobody else runs your software on their own
  host, skip the runtime section as well -- it is about a machine you do not control.
- **Obfuscating or compiling your build is not in scope as an integrity control**, and the section on
  runtime tampering says why rather than leaving it implied.

---

## How to adopt this

Smallest first step, which is a measurement and not a build:

1. **List every dependency manifest in the repository, and write down which of them has an audit.**
   One line per manifest. A repository that grew a second language usually grew an unwatched
   dependency tree at the same time, and this is a ten-minute check that finds it. Print what you
   enumerated, not what you found -- a sweep that examined nothing certifies nothing
   ([CI and standards](../CI-AND-STANDARDS.md#receipts-count-what-the-check-examined-never-what-it-found)).

Then, in order of value per unit of effort:

2. Wire a **blocking** advisory audit for each manifest, and run it on a schedule as well as on
   proposals.
3. Pin the resolved graph and **enforce the pins at install time**, not only at resolution time.
4. Adopt the verify-before-add rule and record a dated vet note with each new dependency.
5. Write behavior tests at each integration boundary that matters.
6. Declare an allowlist of what your published artifact contains and gate on it **before** upload.
7. Publish digests, then build provenance, then an attestation over the artifact.
8. Archive each release with its build inputs and its component inventory.

---

## Inbound: code you deliberately do not read

### Third-party code is code of unknown provenance, and the discipline says so

Third-party code is **code of unknown provenance**: software you incorporate but did not develop and
cannot fully audit. Naming it that way is useful because it states the honest position. You are not
going to read your dependency tree. Nobody does. The discipline that follows from that never asks
you to; it asks you to manage each component as a black box.

| What the discipline requires | The black-box control | Where the human effort lands |
|---|---|---|
| Uniquely identify each component and its exact version | Pin the whole resolved tree by digest; emit a component inventory | One-time, then automated |
| Vet provenance at adoption | Due diligence when you add it: real package, not a near-miss of one; maintained; acceptable license; genuinely used | A few minutes per new dependency |
| Specify what you need and verify it | Test the behavior you depend on, at your own integration boundary | Written once, runs forever |
| Evaluate known advisories against your pinned versions | Automated surveillance, not a re-read | Automated; triage on alert |
| Control change | Pin so nothing drifts; every bump is a reviewed change, re-audited and re-tested | Read the changelog and the lock delta, not the code |
| Contain what you cannot vouch for | Least-privilege runtime, so an unreviewed component has a bounded blast radius | Architectural, set once |

**Rule.** Manage third-party code through provenance, surveillance and verification at your own
boundary. Concentrate human attention at adoption and at each bump, and put nothing in the loop that
requires reading library internals -- because a control nobody can perform is not a control.

### Choosing a widely reviewed library *is* the mitigation for not reading it

On a security-critical path, the choice of dependency is the control. A reputable, widely adopted,
actively maintained library has been effectively reviewed by a population far larger than you can
field. That is what discharges the risk of not reading it, and it is where the adoption minutes
should go -- not into skimming internals, which produces the feeling of review without the substance.

**Rule.** Spend adoption time on the judgment: is this the package I meant, is the project healthy
and maintained, is the license acceptable, is it actually used by anyone. On a security-critical
seam, prefer the widely reviewed option to the clever one, and record why in the vet note.

### The hallucinated package, and why an AI coding assistant makes it routine

An AI coding assistant generates a plausible import the same way it generates plausible prose. A
package name that reads correctly, sits in the right namespace, and matches the shape of real
names in that ecosystem is exactly the output the model is good at producing. And it is
indistinguishable, at the point of use, from a name that exists. That regularity is the attack
surface: a name suggested often enough can be registered by somebody else.

The site already carries the rule, the gate shape and the published magnitude with its model-era
caveat, so it is not restated here: [Verify a dependency before adding it, and know what
verification cannot see](../CI-AND-STANDARDS.md#verify-a-dependency-before-adding-it-and-know-what-verification-cannot-see).

Two things worth adding at this document's altitude:

- **The automated check covers a narrower class than it appears to.** Existence, publishing history,
  an age floor and canonical-name identity are all mechanical. *Is this the project I meant* is not.
  A package that genuinely exists, publishes files, is years old and is served under its own
  canonical name can still be a different project than the one intended, and it passes everything.
- **This is the one moment the black-box discipline is not self-sufficient.** Every other inbound
  control assumes you got the right component. Verify-before-add is the control that establishes the
  assumption, so it is the one place a human is structurally required.

### Explaining code and reading dependencies are different obligations

"Reject code you cannot explain" and "do not read your dependencies" look contradictory. They are
not, and the boundary between them is ownership rather than authorship.

- Code **in your tree** is yours to account for, whoever or whatever typed it. The site's settled
  position -- an explanation reached with assistance is acceptable, rubber-stamping is not, opaque
  even with help is discarded, capture it durably -- is at [Reject code you cannot explain --
  assistance in reaching the explanation is
  fine](../CI-AND-STANDARDS.md#reject-code-you-cannot-explain----assistance-in-reaching-the-explanation-is-fine).
- Code **behind a package boundary** is not yours to account for. You account for its *provenance*
  and for the *behavior you depend on*, which is what the table above enumerates.

**Rule.** Apply the explainability bar at the tree boundary, not at the import statement. Then note
the consequence: anything that moves code across that boundary moves the obligation with it. Two
things do -- vendoring, and generated code checked in. Both arrive looking like dependencies and are
owned code the moment they land.

Two additions worth carrying from the argument that produced the pragmatic bar, neither of which the
site states:

- **An AI coding assistant's explanation can be confidently wrong in exactly the way its code can.** The human
  verifies the explanation; accepting it is the rubber-stamp under a different name.
- **When it breaks, you may not have the AI coding assistant in the loop.** That is the honest residual risk of
  the pragmatic bar, and it argues for unaided comprehension specifically on the seams where a
  mistake is most expensive -- authentication, cryptography, and wherever regulated data crosses.

A cheap detector for drift on this rule: periodically pick a merged assisted change and ask its
author to explain it cold. If that is uncomfortable to schedule, the bar has already slipped.

### Vendored code is owned code, not a dependency

Copying third-party source into your tree converts cheap-to-manage third-party code into code you
own. Worse, it silently leaves the machinery: a vendored path is not in the lockfile, so the advisory
auditor never sees it, and static analysis configured for your first-party package skips the new
directory. Every dependency control reports green while covering nothing.

This is the sibling-path failure in its most common form
([CI and standards](../CI-AND-STANDARDS.md#enumerate-sibling-paths-for-every-control)).

**Rule.** If you vendor, hold the copy to the same gates as first-party code, in the same change that
introduces it:

- behavior tests over the vendored surface
- a header in each file recording what it mirrors and why, so drift is reviewable
- analysis scope extended to include the path, with any suppression carrying a per-line justification
  that names the rule

Record the trade-off that justified vendoring and the concrete trigger that would reverse it, so the
decision is revisitable instead of permanent by default.

### Every manifest in the repository needs its own audit net

Advisory surveillance and blocking audits are configured per ecosystem. A repository that adds a
second language, a build tool with its own manifest, or a documentation site with its own
dependency tree grows a tree that nothing watches -- while the dashboard still says the repository is
covered.

**Rule.** Enumerate the manifests and wire **both halves** for each: scheduled surveillance that
raises a change when an advisory lands, and a **blocking**, install-free audit that fails closed on
any advisory. Prefer one check that fails when a manifest exists with no corresponding audit entry,
so the parity is deterministic rather than a recurring manual sweep. Triage a transitive advisory by
pinning it out through the ecosystem's own override mechanism.

**Judging impact, not skipping it.** A tree that is build-time only -- bundlers, test runners, type
checkers -- is a build-supply-chain concern rather than a runtime exposure, and that difference is
worth stating when you triage. It is not a reason to leave the tree unsurveilled: the build tooling
is the part that touches every line of code you ship.

### Pin the resolved graph, and enforce the pin at install

The general principle is two sentences, and both halves are load-bearing.

**Rule.** Pin the entire resolved dependency graph by cryptographic digest, in an artifact that is
checked in and reviewable. Then make the **install step refuse anything not in the pin**, so a
substituted artifact fails at install on every machine rather than at audit on whichever machine
happened to run the auditor.

Resolution-time pinning without install-time enforcement is the common half-measure: it makes builds
reproducible, which is worth having, and it does not make them verified.

Three questions to answer for your own ecosystem before assuming you have this:

- Does the lock record a **digest**, or only a version? A version pin is not a hash pin.
- Does the **default** install path verify that digest, or is verification opt-in behind a flag?
- Can a developer or a CI step bypass it -- an ad-hoc install, a floating tool install on the runner,
  a build step that resolves fresh?

The site's [Constrain every install site from a checked-in
lock](../CI-AND-STANDARDS.md#constrain-every-install-site-from-a-checked-in-lock) covers the
CI-facing half, including the regenerate-and-diff gate that keeps the lock honest. Two deltas belong
here rather than there:

- **A version pin does not satisfy a supply-chain scorer's pinned-dependency requirement**, and more
  importantly does not satisfy the property you actually wanted. If your CI tooling is installed by
  version rather than by digest, it is unpinned in the sense that matters.
- **A hash-pinned toolchain kept *outside* your existing regenerate-and-diff machinery rots into a
  pinned, stale and unpatched one** -- which is a worse posture than floating, because it looks
  controlled. Keep every lock, including the one for CI-only tooling, inside the same machinery that
  regenerates the runtime locks. Declare the tooling group non-default, and add a test asserting it
  does not leak into the runtime exports.

### The version bump is a bounded review

**Rule.** At each bump, read the changelog and the lock delta the automated update produced, and let
the pipeline re-run the advisory audit and the test suite. You are reviewing *what changed* and
*whether your boundary tests still pass* -- not the library's implementation. Everything else in the
loop is machinery.

Bounding it is the point. An unbounded upgrade review gets deferred, and deferred upgrades are how a
project ends up doing an emergency bump across several major versions under advisory pressure.

### Contain what you cannot vouch for

**Rule.** Bound the blast radius of code you have not reviewed with a least-privilege runtime rather
than with more review:

- a restricted network posture
- authentication required
- no outbound path for sensitive data
- every inbound payload treated as untrusted, validated for structure and content before it reaches
  a query, a file path, a subprocess, or a downstream request

This is architectural and set once, and it is the only inbound control whose value does not depend on
having correctly identified the component.

---

## Outbound: what you publish

### The artifact contains only what you declared

Covered in full at [Package manifests are allowlists, not
sweeps](../CI-AND-STANDARDS.md#package-manifests-are-allowlists-not-sweeps), and not restated. One
instance worth naming here, because it is the case people assume cannot happen: **material a project
treats as withheld can travel inside a published distribution** without anyone reviewing the
packaging list. That is because the packaging list was written as an exclusion and the material was
added later. Checking the thing you built is not checking the thing that shipped.

### Publishing credentials should be minted per run, not stored

A long-lived registry token is the most common supply-chain compromise path available to a small
project, because it leaks quietly and nothing about the leak is visible until it is used.

**Rule.** Replace long-lived publishing tokens with a credential minted per run from the pipeline's
own workflow identity, scoped to a specific repository, workflow and environment, and valid only for
the length of an upload. State the *property* -- short-lived, workflow-bound -- rather than a
current time-to-live, which is a provider implementation detail.

Two conditions travel with it, and both have bitten people:

- **Restrict the publishing workflow to trusted triggers** -- a tag or a push -- and never to a
  trigger that grants write credentials to code from an untrusted contributor. Pin the publishing
  action.
- **It does not defend against takeover of the publishing account.** Multi-factor on the account and
  environment protection rules are what cover that, and they are a different control.

*(Ecosystem-specific: the mechanism exists on some registries and not others, and the exact scoping
vocabulary differs. The property is general; the availability is not.)*

### Publishing identity does not cover the artifact

Establishing that an upload came from your pipeline says nothing about whether the artifact was
modified before or after it was built. The registries that offer identity-based publishing say so in
their own documentation, which is the sort of caveat worth reading before crediting a control.

**Rule.** Pair the publishing identity with a **signed attestation** binding the distributed
filename and its digest to the source repository, workflow and commit that produced it. Record that
attestation in a public transparency log and have the registry serve it, so a consumer can check it
without contacting you. Neither the identity nor the attestation is sufficient alone.

### A signing scheme nobody can verify is not a control

Signature *coverage* and signature *verifiability* are separate questions, and both can be near zero
while the scheme is nominally in place.

**[external]**, from a major language registry's own published measurement when it removed
long-standing detached-signature support: only about a third of signing keys could be meaningfully
verified at all, and signed files were a fraction of a percent of everything published. Support was
withdrawn and existing signatures are now ignored. Figures are that registry's, at that time; they
are quoted for the shape of the finding, not as constants.

**Rule.** Before crediting a signing control, measure two things: what proportion of artifacts carry
a signature, and what proportion of those signatures a consumer can actually resolve to an identity.
Prefer identity-based signing bound to the build workflow and recorded in a transparency log, where
verification does not depend on a key-distribution story that never worked. Signing repository tags
and commits remains worthwhile for source provenance -- it is the *artifact* signature path that this
finding replaced.

### Build provenance, and the lowest-tech verification path

Two artifacts do most of the work for whoever installs your build.

**Rule.** Generate **build provenance** in the pipeline, proving the artifact traces to a specific
repository, workflow and commit rather than to somebody's machine. Isolating the build behind a
dedicated reusable workflow raises the assurance further, and the published build-level frameworks
are what let you say which level you reached without inventing a scale.

**Rule.** Publish a **signed digest manifest** with every release, and document the exact
verification commands including the offline path. This is the one route a reviewer on a restricted or
disconnected network can always run, and it should be the documented baseline rather than an
afterthought. If your signing scheme supports bundling a transparency-log inclusion proof with the
artifact, bundle it, for the same reason.

Keyless, identity-based signing removes long-lived key management, which is a real win. Be clear
about what it does to the threat model rather than what it removes from it: **you are no longer
protecting a key, you are protecting the pipeline identity.** Account multi-factor, branch protection
and pipeline hardening become the load-bearing controls. A project that adopts keyless signing and
leaves the pipeline unhardened has moved the target, not removed it.

### A component inventory is not tamper detection, and saying so matters

**Rule.** Generate a component inventory with each release, in the formats your consumers ingest, and
attach it to the release and to the archived build. Then be precise about what it buys, because it is
routinely quoted as integrity evidence it does not provide. It buys at least: answering *do we ship
component X* within minutes of a widely publicised advisory; drift detection, by diffing a produced
inventory against the intended manifest; and satisfying procurement reviews that ask for one.

It does not detect tampering with your own code. Nothing about it is a signature.

### Archive each release with its build inputs and its inventory

**Rule.** Retain, per released version, the artifact, the inputs it was built from, and its component
inventory. Two questions depend on it and neither can be answered later without it: *what exactly was
in the version this adopter is running*, and *can we rebuild it at all*. An archive holding only the
artifact answers neither.

---

## After it ships: the runtime you do not control

This section applies only if somebody else runs your software on a host you do not administer. It is
short on purpose, because most of what works here is not yours to own.

### Obfuscation is not the integrity story for source-available code

If your source is published, obfuscating or compiling the shipped artifact protects nothing that
matters. There is no confidentiality to preserve, and the tamper resistance gained is marginal:

- Bytecode-only distribution is decompiled and patched by public tooling.
- Native compilation raises the bar but leaks identifier and symbol information by default, and the
  binary remains patchable with standard tools.
- Self-extracting single-file bundles leave their contents on disk for inspection, which the tools'
  own documentation concedes.

The protection schemes that run *inside* the process they protect assume an uncompromised runtime,
and that is precisely the assumption a privileged attacker breaks.

Where a license obliges you to provide corresponding source, an obfuscated build also creates
friction with that obligation.

**Rule.** Spend the effort on verification instead -- provenance, attestation, inventory, published
digests -- because that is what a reviewer can independently check. If you ship a hardened build for
other reasons, position it as raising analysis cost and never as tamper-proof, and keep secrets and
authorization decisions out of any artifact an adversary holds.

*(Specific defeat tooling is deliberately not enumerated here. The conclusion stands on the vendors'
own stated limits, and the assessment is version-specific enough that it should be re-derived rather
than quoted.)*

### The self-integrity check, and the bootstrap-trust problem

An application that hashes its own files against a signed manifest at startup detects accidents and
unsophisticated tampering, and produces an audit signal. That is worth having.

It cannot be more than that, because the checker runs in the same trust domain as the thing it
checks. Whoever can edit the code on disk can also edit the manifest, the embedded key, or the
verification routine; whoever can alter the runtime can stub it. The chain of trust only terminates
in hardware measured boot, which is the operator's platform decision and not something your software
ships.

**Rule.** Ship it as defense in depth if you ship it, and document the limit **in the same paragraph
as the feature**, not in a footnote. Never let it be quoted as prevention. This is the general rule
about stating what a gate does not prove
([CI and standards](../CI-AND-STANDARDS.md#state-what-a-gate-does-not-prove)) applied to the hardest
case.

### Operator-owned hardening: document and recommend, never claim

The strongest tamper controls are outside the software:

- file-integrity monitoring against a baseline
- immutable or read-only deployment with writable state confined to the data store
- least-privilege file ownership, so the running account cannot rewrite its own code
- mandatory-access-control confinement
- admission control that rejects an unsigned artifact

You cannot own any of them. What you can do is ship a hardening guide with a concrete list of paths
to monitor and example rules, so an operator has something to apply on day one rather than a category
name.

**Rule.** Publish a two-column responsibility split before claiming any control. The producing
project owns secure development practice, secure-by-default configuration, testing and attestation
of the software, vulnerability response, and evidence. The operating organization owns host and
network, identity and key management in their environment, backups and availability, their own
compliance program, and monitoring and patching. State plainly that shipping the software confers no
certification on the operator: your attestation is an input to their assessment, never a substitute
for it. The register to use for that wording is on the site already -- built to, aligned with,
self-assessed against, never certified
([CI and standards](../CI-AND-STANDARDS.md#use-the-register-you-actually-have-aligned-built-to-self-assessed)).

### Roll a blocking verification control out in audit mode first

A control that rejects artifacts failing verification will also reject valid artifacts whenever its
*own* preconditions are unmet -- for instance when the enforcing component cannot reach the store
holding the signatures it must fetch.

**Rule.** Start any such control in a mode that reports but does not block, confirm it is resolving
what it needs, then switch to enforce. A control that blocks legitimate deployments on day one gets
switched off permanently, and the second attempt is much harder to fund than the first.

### State the objective honestly: detection, not prevention

On a host where the adversary has administrative privilege, every application-level control is
ultimately defeatable -- agents disabled, baselines altered, the interpreter patched, behavior hooked
at load time.

**Rule.** Say that in the documentation rather than letting the control list imply prevention. The
achievable objective is to make tampering noisy, costly and detectable, to produce audit evidence,
and to push the trust root as low as the operator is willing to go.

---

## Which rules are universal, and which are one ecosystem's mechanics

The failure shapes generalize. The mechanisms do not, and a document that implies otherwise sends a
reader looking for a guarantee their toolchain does not offer.

| Rule | Scope |
|---|---|
| Verify a dependency's identity before adding it; record a dated vet note | Universal |
| Manage third-party code as a black box; test the behavior you depend on at your boundary | Universal |
| Vendored code is owned code and must join every first-party gate | Universal |
| One surveillance net plus one blocking audit **per manifest** | Universal (the wiring is per ecosystem) |
| Pin the resolved graph by digest and enforce the pin at install | Universal as a property; **the guarantee is per ecosystem** |
| Lockfile format, digest recording, install-time enforcement flag | Ecosystem-specific -- verify what yours actually does |
| Advisory audit tool, its default severity threshold, install-free mode | Ecosystem-specific |
| Transitive-advisory override mechanism | Ecosystem-specific |
| Non-default dependency groups for CI-only tooling | Ecosystem-specific |
| Allowlist what the published artifact contains; gate before upload | Universal |
| Per-run, workflow-bound publishing credentials | **Registry-specific** -- available on some, absent on others |
| Registry-served attestation binding filename and digest to a commit | **Registry-specific** |
| Build provenance from the pipeline; assurance levels from a published framework | Universal in concept, forge-specific in tooling |
| Signed digest manifest, with documented offline verification | Universal, and the lowest common denominator |
| Component inventory per release, attached to the release and the archive | Universal (format choice is consumer-driven) |
| Archive artifact, build inputs and inventory per version | Universal |
| Runtime self-check is detection only; hardening is operator-owned | Universal |

Where the mechanics here have a shape, it is a Python-and-npm shape with a GitHub-flavoured pipeline
around it, because that is what was exercised. Read the *shape*; check the *guarantee* against your
own toolchain before repeating any of it as a claim.

---

## In one table

| When | Rule |
|---|---|
| Adding a dependency | Verify identity, not existence alone. Record a dated vet note. Never install ad hoc |
| Adding a dependency | On a security-critical seam, the widely reviewed library **is** the mitigation |
| Depending on behavior | Test it at your own integration boundary -- that is the black-box substitute for reading it |
| Pinning | Pin by digest and enforce at install. A version pin is not a hash pin |
| Pinning CI tooling | Keep its lock inside the same regenerate-and-diff machinery, or it rots into pinned-and-stale |
| Bumping | Read the changelog and the lock delta. Let the pipeline re-audit and re-test |
| Vendoring | It is owned code now. Tests, a mirrors-what header, and analysis scope, in the same change |
| Auditing | One surveillance net and one **blocking** audit per manifest; run on a schedule too |
| Auditing | Build-time-only trees are a different impact class, not an exemption |
| Containing | Least-privilege runtime; every inbound payload validated before it reaches anything |
| Publishing | Allowlist the contents, gate before upload, verify the published artifact once after |
| Publishing | Short-lived workflow-bound credentials; restrict the trigger; pin the publish action |
| Publishing | Publishing identity does not cover the artifact -- pair it with an attestation |
| Publishing | Measure signature coverage **and** verifiability before crediting a signing control |
| Releasing | Publish signed digests with documented offline verification. It is the baseline, not the extra |
| Releasing | Archive the artifact, its build inputs and its inventory, per version |
| Claiming | An inventory answers "do we ship X". It is not tamper detection |
| Claiming | Publish the producer/operator responsibility split before claiming any control |
| Runtime | A self-integrity check is detection. Document the limit in the same paragraph |
| Runtime | Obfuscation is not the integrity story for published source. Verification is |
| Rolling out | Any blocking verification control starts in audit mode |

---

## Adapting this to your project

**Change freely:**

- **The mechanics, everywhere they are tagged ecosystem-specific.** Substitute your lock format,
  your audit tool, your override mechanism, your registry's publishing model.
- **The order of adoption.** The list above is ordered by value per unit of effort in one setting.
  If your repository already hash-locks but publishes by hand, start at the outbound half.
- **How much of the outbound half you build.** Digests are cheap and universally useful. Provenance
  and attestation are worth more but depend on what your pipeline and registry support.
- **Whether you ship a self-integrity check at all.** It is the lowest-value control here, and it is
  reasonable to skip it and spend the effort on publishing controls instead.

**Do not weaken:**

- **Verify-before-add stays human.** Automation covers existence, age and canonical name. It does not
  cover *is this the project I meant*, and no amount of tooling will.
- **Every manifest keeps an audit.** A repository that reports coverage while a whole manifest goes
  unwatched is worse than one that admits the gap, because the gap is invisible.
- **The install step keeps enforcing the pin.** Dropping enforcement to unblock a build is how a
  hash-locked project silently becomes a version-pinned one.
- **Vendored code keeps the first-party gates.** The moment it is exempt, it is a blind spot with
  every dependency control still green.
- **The allowlist gate stays before the upload.** The upload is irreversible; the gate is the only
  point at which it is still a decision.
- **Do not let any control here be described as more than it is.** A self-check is not prevention, an
  inventory is not integrity evidence, a green audit is not a statement about a legitimate maintainer
  who was compromised, and none of it is certification. State what each gate does not prove
  ([CI and standards](../CI-AND-STANDARDS.md#state-what-a-gate-does-not-prove)), and prove a gate can
  see its own failure class before crediting a green result
  ([the leak gate](../LEAK-GATE.md#the-caveat-that-matters-most)).

---

## Related

- [CI and standards](../CI-AND-STANDARDS.md) -- dependency verification, install-site locking,
  scheduled supply-chain audits, package manifests as allowlists, and what a gate does not prove
- [The leak gate](../LEAK-GATE.md) -- fail-closed content scanning before publication, and the
  permanent blind spot a scanner cannot cover
- [Tips and tricks](../TIPS-AND-TRICKS.md) -- writing a guardrail, and measuring whether it works
- [Case study: auditing a multi-session estate as one system](../CASE-STUDY-drift-audit.md) --
  proving a fix by deliberately mutating the shipped artifact
