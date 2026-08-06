# The CISO summary

**Your developers are building with AI assistants. Here's a two-page guide on what to require they
do, and how to tell whether you actually got it.**

> **This one is written to be read.** So is [Human review of code](REVIEW-DEPTH.md). The other
> standards are different: most of their content is a base for Claude Code, or another AI-assisted
> coding tool, to apply to a repository, and that is how your teams should expect to use them.
>
> The fastest way in: give the tool the
> [markdown](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/CISO-SUMMARY.md), ask it to
> **summarize the document against your repository**, and then ask it questions. What here
> already holds? What would have to change? What would each gap cost? That conversation is
> worth more than reading top to bottom, because the answers are about your code rather than
> about the document.
>
> Reading or circulating instead? [Word document](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/CISO-SUMMARY.docx).
> [Every file, both formats](OVERVIEW.md#the-files).

---

## The bottom line

- **The risk categories are not new.** Injection, weak authorization, bad dependencies and leaked
  secrets are the same list as last year. What changed is **volume, speed, and confidence**.
- **Reviewing more code is not the answer.** The answer is controls that do not care how finished
  the output looks, because looking finished is precisely what assisted output is good at.
- **Ask for receipts, not assurances.** A control that has never been proven able to fail is
  indistinguishable from no control. That single question separates real programs from theatre.
- **None of this certifies anything.** These documents are a bar to set, not an attestation to
  present. Anyone who tells you otherwise is selling something.

---

## What actually changes with an assistant in the loop

Five failure modes cover it. Every control worth funding neutralizes at least one of them; a
proposed control that answers none is ceremony, and ceremony is what gets dropped first under
pressure -- taking the load-bearing rules beside it.

| Failure mode | What you would see |
|---|---|
| **Intent drift** | Code diverges from what was asked, with no written intent to check it against |
| **Context degradation** | Confidently wrong edits late in a long session; the same files re-read |
| **Error accumulation** | Mistakes compound across a long unsupervised run, and so does spend |
| **Fast but flawed** | Review skipped because the output looks finished; people who can build but cannot debug |
| **Misplaced trust** | Confidence rises faster than correctness -- worst when the author reviews their own assisted work |

The last one is the expensive one. It is the strongest argument for keeping the review step your
teams will offer to drop for speed.

---

## Five questions, and what a good answer sounds like

| Ask | A good answer | A bad answer |
|---|---|---|
| **How do you know a gate works?** | "We broke it on purpose and watched it fail, on this date" | "It is green" |
| **What did the check actually examine?** | A count of files or lines scanned, printed by the check itself | "It passed" |
| **Who approved this change, and against what?** | A written, testable intent that predates the code | "It was reviewed" |
| **Where did this dependency come from?** | Verified to exist before adoption, version pinned by hash | "It is popular" |
| **What is in the release?** | An allowlist checked before publishing, not a sweep of the build directory | "Only what we built" |

If an answer arrives as a percentage -- coverage, complexity, issue counts -- treat it as
conversation, not verdict. Those numbers are weak or invertible predictors of real defects, and
gating on them buys the appearance of rigor while the structural controls go unfunded.

---

## What to fund first

1. **Structural controls that cannot be argued with**: enforced architecture and layer boundaries,
   strict type checking, dependency verification and hash pinning, blocking security scanners, and
   an allowlist on what gets published.
2. **A human arbiter who cannot be skipped**, especially where a change touches restricted data or
   an authorization path.
3. **Measurement, last, and never as a gate on its own.** Mutation testing, coverage visibility,
   duplication detection and complexity triage inform a person. They do not certify anything.

The order matters. Reversed, you get a dashboard and no controls.

---

## What this is not

- **Not a certification, and not an audit.** No badge, no pass mark. A completed self-assessment is
  an argued position with pointers, and calling it more than that is the failure these documents
  are most concerned with.
- **Not independently reviewed.** No outside party has reviewed this material.
- **Not exhaustive.** It names at least the failure modes it was written against, not every risk
  your program carries.
- **Not a substitute for your own threat model.** Nothing here knows what your systems do.

---

## Where to go next

| If you need | Read |
|---|---|
| The full control set for AI-assisted work | [AI-assisted development](AI-ASSISTED-DEVELOPMENT.md) |
| How much of the code a human must actually read | [Human review of code](REVIEW-DEPTH.md) |
| How to judge whether code is good, whoever wrote it | [Code quality](CODE-QUALITY.md) |
| The process a build must satisfy | [Secure development](SECURE-DEVELOPMENT.md) |
| Trusting what you did not write, and controlling what you ship | [Dependency integrity](DEPENDENCY-INTEGRITY.md) |
| All of it, and how to adopt | [Overview](OVERVIEW.md) |

**MIT licensed.** Adapt this, put your own name on it, and delete anything you cannot stand behind.
