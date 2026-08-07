# The CISO summary

**Your developers are building with AI coding assistants. A short guide to what to require of them,
and how to tell whether you got it.**

> **Take a copy:**
> [markdown](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/CISO-SUMMARY.md)
> or [Word document](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/CISO-SUMMARY.docx).
> [Every file, both formats](OVERVIEW.md#the-files).

---

## In short

**Nothing new is going wrong with your code. There is just far more of it, arriving faster, and
looking finished before anyone has checked it.** Injection, weak authorization, bad dependencies,
leaked secrets -- the categories have not moved.

Reviewing more code is not the answer: review effort scales with the volume, and the volume is what
moved. Three moves instead, in this order:

1. **Fund structural controls** -- checks that run on every change and whose verdict does not change
   because the output looks finished. What counts as one is listed below.
2. **Put a human arbiter where it cannot be skipped** -- above all where a change touches restricted
   data or an authorization path.
3. **Measure last, and never gate on measurement alone.**

Then ask each control owner one question: **when did you last prove this can fail?** A gate nobody
has ever watched go red is not evidence of anything.

**None of this certifies anything.** These documents are a bar to set. No badge comes with them.

---

## What changes with an AI coding assistant in the loop

The five modes below are the ones this control set was written against. They are not a complete
taxonomy and they overlap in practice. Their use is as a test on a proposed control: one that
neutralizes none of them is ceremony, and ceremony is what gets dropped first under pressure --
usually taking whatever load-bearing rule sat next to it in the same document.

| Failure mode | What you would see |
|---|---|
| **Intent drift** | The change does something adjacent to what was asked, and no written statement of the ask exists to compare it against |
| **Context degradation** | Confident, wrong edits late in a long session; the same files read over and over; an earlier decision quietly reversed |
| **Error accumulation** | A long unsupervised run compounds one bad assumption across many files. The spend compounds with it |
| **Fast but flawed** | Review gets skipped because the output looks finished. Over a longer horizon: people who can produce a change but cannot debug one |
| **Misplaced trust** | Confidence rises faster than correctness, and furthest when the person reviewing the assisted work is the person who prompted it |

The last one is why self-review of assisted work is the step to protect. It is also the step teams
volunteer to give up when they are behind schedule.

---

## Five questions, and what a good answer sounds like

The weak answers below are the plausible ones. That is the point -- none of them is obviously
evasive, and each is what a competent team says when the underlying control is thinner than the
process around it.

| Ask | A good answer | A weak answer |
|---|---|---|
| **How do you know that gate works?** | "We turned the rule off on a branch, watched the build go red, and put the date in the commit" | "It has been green all quarter" |
| **What did that check actually examine?** | The check prints its own scope -- files scanned, rules applied -- so a run that measured nothing is visible as one | "It runs on every pull request" |
| **What was this change measured against?** | A written statement of intent, predating the code, specific enough that the code could fail it | "Two engineers approved it" |
| **Where did this dependency come from?** | Confirmed to exist and to be the intended package before adoption, then pinned by hash | "It has a lot of stars and a recent release" |
| **What is in the release?** | An allowlist of files, checked before publishing | "Whatever the build produces" |

If an answer arrives as a percentage -- coverage, a complexity score, an issue count -- treat it as a
conversation starter rather than a verdict. These track real defect rates loosely at best, and a
team measured on one will move the number without moving the risk underneath it. Gating on it buys
the appearance of rigor, and the structural controls are what goes unfunded instead.

---

## What to fund first

1. **Structural controls that cannot be argued with**: enforced architecture and layer boundaries,
   strict type checking, dependency verification and hash pinning, blocking security scanners, and
   an allowlist on what gets published.
2. **A human arbiter who cannot be skipped**, especially where a change touches restricted data or
   an authorization path.
3. **Measurement, last, and never as a gate on its own.** Mutation testing, coverage visibility,
   duplication detection and complexity triage all inform a person. None of them certifies
   anything.

The order matters. Reversed, you get a dashboard and no controls.

---

## What this is not

- **Not a certification, and not an audit.** There is no badge and no pass mark. A completed
  self-assessment is an argued position with pointers to evidence, and nothing here should be
  presented as more than that.
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
| What to require of a vendor you are evaluating | [What to ask a software vendor for](DILIGENCE-PACKET.md) |
| All of it, and how to adopt | [Overview](OVERVIEW.md) |

**MIT licensed.** Adapt this, put your own name on it, and delete anything you cannot stand behind.
