# Standards you can start from

**Starting points you adapt, not a compliance package.** These documents cover creating secure,
high-quality code using Claude Code.

**Nothing here certifies anything.** Nothing here is a certificate, an audit, or a scored verdict
about any codebase, and nothing here installs or enforces anything. Every one of them is meant to be
edited down to your setting before it is useful.

## The files

| Document | Read online | Markdown | Word |
|---|---|---|---|
| **The CISO summary** -- two pages, start here if you are deciding rather than adopting | [page](CISO-SUMMARY.md) | [.md](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/CISO-SUMMARY.md) | [.docx](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/CISO-SUMMARY.docx) |
| **Which security standards apply to you** -- routes your situation to the documents worth your attention, and to what to check next | [page](WHICH-STANDARDS-APPLY.md) | [.md](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/WHICH-STANDARDS-APPLY.md) | [.docx](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/WHICH-STANDARDS-APPLY.docx) |
| **What to ask a software vendor for** -- the mirror of that page: what to require of a vendor you are evaluating, and what each answer proves | [page](DILIGENCE-PACKET.md) | [.md](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/DILIGENCE-PACKET.md) | [.docx](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/DILIGENCE-PACKET.docx) |
| **Security standards reference** -- one row per document, and the reasoning behind the cuts they are sorted on | [page](STANDARDS-REFERENCE.md) | [.md](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/STANDARDS-REFERENCE.md) | [.docx](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/STANDARDS-REFERENCE.docx) |
| **How to adopt these** -- what to do with the rest of this section: five artifacts that either exist or do not, and the order to build them in | [page](ADOPTING-THESE.md) | [.md](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/ADOPTING-THESE.md) | [.docx](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/ADOPTING-THESE.docx) |
| **Automated compliance in CI** -- which of your rules a pipeline can enforce, which it can only report on, and what that is worth | [page](CI-ENFORCEMENT.md) | [.md](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/CI-ENFORCEMENT.md) | [.docx](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/CI-ENFORCEMENT.docx) |
| **AI-assisted development** -- the rigor dial: how much process a given change actually needs, and the floor that never scales down | [page](AI-ASSISTED-DEVELOPMENT.md) | [.md](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/AI-ASSISTED-DEVELOPMENT.md) | [.docx](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/AI-ASSISTED-DEVELOPMENT.docx) |
| **Dependency integrity** -- trusting code you did not write, and controlling what you publish | [page](DEPENDENCY-INTEGRITY.md) | [.md](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/DEPENDENCY-INTEGRITY.md) | [.docx](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/DEPENDENCY-INTEGRITY.docx) |
| **Human review of code** -- how much of it a human must read | [page](REVIEW-DEPTH.md) | [.md](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/REVIEW-DEPTH.md) | [.docx](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/REVIEW-DEPTH.docx) |
| **Code quality** -- is this good, or is it filler that looks finished: eleven signals, and which of them may decide a verdict | [page](CODE-QUALITY.md) | [.md](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/CODE-QUALITY.md) | [.docx](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/CODE-QUALITY.docx) |
| **Secure development** -- a starting point for your own standard, covering the process a build must satisfy from the threat model to the release gate, and what you may claim once it does | [page](SECURE-DEVELOPMENT.md) | [.md](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/SECURE-DEVELOPMENT.md) | [.docx](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/SECURE-DEVELOPMENT.docx) |
| **Use OWASP ASVS 5.0** -- assessing a codebase against a large standard | [page](../ASVS-ASSESSMENT.md) | [.md](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/ASVS-ASSESSMENT.md) | [.docx](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/ASVS-ASSESSMENT.docx) |
| This overview | -- | [.md](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/OVERVIEW.md) | [.docx](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/OVERVIEW.docx) |
| **A `CLAUDE.md` template** -- `CLAUDE.md` is the file Claude Code reads at the start of every session, so it is where a project's standing rules live. This one is a starting point. | -- | [CLAUDE.md.template](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/CLAUDE.md.template) | -- |

**Markdown is best for sharing with AI. Word is best for sharing with humans.**

**"The standards landscape" was split, and is the one name above that changed.** It did two jobs:
routing you to the documents worth your attention, and holding a reference table that was a verbatim
second copy of the reference page's rows. Two copies of one status is the failure both pages are
about, so the rows now live in the reference alone and the routing page points into it. What is left
at the old name is [a pointer](STANDARDS-LANDSCAPE.md) to the two rows above, kept so that links to
its URL still land somewhere useful. It is not a standard and is not offered for download.

## The order to read them in

1. **[AI-assisted development](AI-ASSISTED-DEVELOPMENT.md)** first. It is the one that changes
   tomorrow rather than next quarter, and its risk tier decides how much of the rest applies to any
   given change.
2. **[Human review of code](REVIEW-DEPTH.md)** second, and early on purpose. It answers the question
   a manager asks before any of this gets funded: how much of the code a human still has to read.
3. **[Dependency integrity](DEPENDENCY-INTEGRITY.md)** next. Its controls are the most mechanical of
   the set, and you probably already have half of them. It is the one most likely to be adopted
   close to whole.
4. **[Code quality](CODE-QUALITY.md)** fourth. It assumes you have somewhere to put a blocking
   check, which the first two get you thinking about.
5. **[Secure development](SECURE-DEVELOPMENT.md)** last. It is the widest and the most
   setting-specific, and the one you should expect to rewrite rather than adopt.

**Two are short enough to read straight through**: [the CISO summary](CISO-SUMMARY.md) and [Human
review of code](REVIEW-DEPTH.md).

**Read the scope-and-limits block first.** If you read only one paragraph of any of them, read that
one. It tells you whether the rest applies to you, and it is deliberately placed before the rules.

**Then write down what you actually built.** These become your rules once you adopt them, and Claude
Code reads a file called `CLAUDE.md` at the start of every session. That makes `CLAUDE.md` the place
a project keeps its standing rules.

The
[template above](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/CLAUDE.md.template)
carries a table for exactly that: which of these controls exist here, and when each was last proven
able to fail. A standard that no such file references is a document, not a practice.

## What these are not

- **No code ships with them.** These are rules and review procedures. Where one names a control, it
  is describing something you would build, not something in this repository.
- **No certification, and no attainment.** Following them confers nothing on you, on your product,
  or on anyone adopting your product. Where you need phrasing for that, they use "built to",
  "aligned with" and "self-assessed against", per
  [Say which kind of claim you are making](../CI-AND-STANDARDS.md).
- **Not exhaustive.** Each names at least the failure modes it was written against. None of them
  claims to be a complete account of its subject, and a completeness claim is the one thing you
  should not add when you adapt them.
- **Not independently reviewed.** No outside party has reviewed these. That is a real gap, and each
  document says where it bears on a rule.

## What each one buys you

Read the line, then the document that matches the argument you are currently losing.

| Document | What it buys you |
|---|---|
| [What to ask a software vendor for](DILIGENCE-PACKET.md) | The mirror of the routing page: not which documents apply to you, but which ones to require of a vendor you are evaluating. Evidence split by layer, because the commonest failure is accepting an organization-layer instrument as evidence about software. For each item: what it proves, what it does not, and what to ask. |
| [Which security standards apply to you](WHICH-STANDARDS-APPLY.md) | The front door, organized around your situation rather than around the documents. At least twelve situations, each naming what can apply and by which route, since these arrive attached to a contract rather than getting chosen. What the map does not cover, said out loud. It carries no reference table: every answer points into the reference below. On the served site it also carries an interactive selector: tick what is true of your business and it hides what cannot apply to you. It hides; it never computes, and it issues no verdict. |
| [Security standards reference](STANDARDS-REFERENCE.md) | Every row on the map, sorted by who each document is addressed to -- a software producer, an organization operating systems, an assessor, or nobody. What each one actually issues, since most issue nothing and people are routinely asked for certificates that do not exist. What triggers it. A check you can run yourself instead of trusting the page. Every status carries the date it was checked. Under the rows: why the cuts fall where they do, why an organization-layer certificate is not evidence about software, the routes any of this arrives by, and why a status without a date is worthless. |
| [How to adopt these](ADOPTING-THESE.md) | Five steps, each ending in an artifact rather than a resolution. An exception recorded as a documented deviation with a compensating control and a trigger that ends it, because an exception without an ending trigger is permanent by default. Automation stated the hard way: automate, then prove each check can still fail, and count only blocking checks as coverage. A worked example run end to end, and an answer for a reader who has one afternoon. |
| [AI-assisted development](AI-ASSISTED-DEVELOPMENT.md) | Five named process failure modes as an organizing spine. A tier ladder that says how much rigor this particular change needs. The hard line between a control and a wish: a gate is a deterministic check, and the model never certifies its own output. An adversarial verification pass written as a technique, including the cases where it is pure waste. |
| [Dependency integrity](DEPENDENCY-INTEGRITY.md) | Two directions in one document. Inbound: third-party code held as a black box you deliberately do not source-review, with the obligation made finite and the human effort concentrated at adoption and at each bump. Outbound: a published build that contains only what you declared, verifiable by the person installing it. |
| [Human review of code](REVIEW-DEPTH.md) | The answer to "how much of this must a human read" that is not a percentage. Depth resolved per change by risk tier, a sensitive-data ratchet that dominates size, and an unknown-clamps-up rule. Two conditions that force a full line-by-line read regardless. The contested question of whether explaining code with the AI coding assistant's help satisfies the floor. |
| [Use OWASP ASVS 5.0](../ASVS-ASSESSMENT.md) | A method for assessing a codebase against a standard with several hundred requirements. Verdict vocabularies that mean the same thing to two reviewers, and evidence anchors a machine can re-check. Pinning the standard's corpus so it cannot shift underneath you, and how to read a movement in a score. |
| [Code quality](CODE-QUALITY.md) | Rows that may decide a verdict, separated from rows that may only start a conversation. The published evidence behind refusing to gate on a single number. A map from each way machine-written code goes wrong to the control that neutralizes it. Review depth as a per-file decision, so a large diff stays finite. |
| [Secure development](SECURE-DEVELOPMENT.md) | A written producer-versus-operator ownership split. A per-boundary threat model that gives review something to check against, and a finite secure-coding list. An honest read of what a green pipeline has and has not established. A release gate that is a checklist rather than a debate. |

## Where these came from, and what they assume

They were assembled from material written across several months for one working codebase, then
merged and brought up to date.

**Corrections stay in place.** Where the source said something later shown to be wrong, it is
corrected in place and says so briefly. Several of the most useful rules in the set exist only
because something was published, believed, and then found not to hold. A cost model derived from a
tool that had crashed before doing any work is the shape of it.

Three assumptions ride along, and they are the first things to check against your own setting:

- **A small team, sometimes one person.** Where a mainstream standard assumes a second human
  reviewer, these record a documented deviation with a compensating control and a trigger that ends
  it, rather than redefining review until it looks satisfied. If you have a real second reviewer,
  several sections get shorter.
- **A code host with a blocking pipeline, and a repository several sessions push to at once.** The
  control placement advice assumes both. The failure shapes are not host-specific; the field names
  are.
- **The domain is stripped on purpose.** These were written in a setting with regulated data and a
  compliance regime, and the specifics of that setting are not here. Rules are expressed generically
  -- "regulated data", "an untrusted inbound payload", "a compliance regime the adopting
  organization operates". Where a rule could not be generalized it was dropped rather than
  disguised, so the set is not a complete account of the practice it came from.

## What is already elsewhere on this site

These documents link out rather than restate, and so should you when you adapt them. In particular:

- [CI and standards for agent-written code](../CI-AND-STANDARDS.md) owns claim honesty, judging
  tests and metrics, why a check that cannot fail is not a control, and the split between what the
  agent decides and what you decide. It is the largest overlap by far.
- [The leak gate](../LEAK-GATE.md) owns pre-publication content scanning, the three ways a scanner
  lies, and the blind spot no scanner can close.
- [Running a large security-standard assessment with AI agents](../ASVS-ASSESSMENT.md) owns verdict
  vocabularies, evidence anchors a machine can re-check, pinning a standard's corpus, and how to
  read a movement in a score.
- [Tips and tricks](../TIPS-AND-TRICKS.md) sections 4 and 5 own the hands-on version of writing a
  guardrail and proving it can see what it claims to.
