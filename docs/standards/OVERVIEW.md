# Standards you can start from

A set of documents for creating secure, high-quality code using Claude Code:

- what counts as quality
- what counts as secure
- how to hold third-party code you will never read
- how to govern the assistant writing much of it

Plus [a two-page summary](CISO-SUMMARY.md) for a security executive who has to decide whether any of
it is being done, rather than adopt it.

They are **starting points you adapt**, not a compliance package. Nothing here is a certificate, an
audit, or a scored verdict about any codebase, and nothing here installs or enforces anything. Every
one of them is meant to be edited down to your setting before it is useful.

## Download every file

| Document | Read online | Markdown | Word |
|---|---|---|---|
| **The CISO summary** -- two pages, start here if you are deciding rather than adopting | [page](CISO-SUMMARY.md) | [.md](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/CISO-SUMMARY.md) | [.docx](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/CISO-SUMMARY.docx) |
| **AI-assisted development** | [page](AI-ASSISTED-DEVELOPMENT.md) | [.md](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/AI-ASSISTED-DEVELOPMENT.md) | [.docx](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/AI-ASSISTED-DEVELOPMENT.docx) |
| **Dependency integrity** | [page](DEPENDENCY-INTEGRITY.md) | [.md](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/DEPENDENCY-INTEGRITY.md) | [.docx](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/DEPENDENCY-INTEGRITY.docx) |
| **Code quality** | [page](CODE-QUALITY.md) | [.md](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/CODE-QUALITY.md) | [.docx](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/CODE-QUALITY.docx) |
| **Secure development** | [page](SECURE-DEVELOPMENT.md) | [.md](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/SECURE-DEVELOPMENT.md) | [.docx](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/SECURE-DEVELOPMENT.docx) |
| This overview | -- | [.md](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/OVERVIEW.md) | [.docx](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/OVERVIEW.docx) |
| A working agreement that adopts them | -- | [CLAUDE.md.template](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/CLAUDE.md.template) | -- |

Rows are in [the order worth reading them in](#the-order-to-read-them-in).

**Putting these to work, or passing them around? That decides the format.**

- **It is plain text.** It drops into a repository as-is, and it diffs cleanly once you start
  editing it -- which you will, because none of these are usable unedited.
- **The four main documents are a base for an agent, not prose to work through.** Most of their
  content exists to be applied to a repository. So:
  1. Give Claude Code, or another agent, the markdown.
  2. Ask it to **summarize the document against your repository**.
  3. Then ask questions. What already holds? What would have to change? What would each gap cost?

  Those answers are about your code. A careful read of a document about nobody's code in particular
  is worth less. [The CISO summary](CISO-SUMMARY.md) is the exception: it is written to be read.
- **The Word files are the same content**, generated from the same markdown. Take those for
  circulating to people who will read or mark up rather than adopt.

The [working agreement template](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/CLAUDE.md.template) is where a project records which of these
controls it actually built, and when each was last proven able to fail. A standard that no working
agreement references is a document rather than a practice.

**MIT licensed** -- adapt them, publish the result, drop the attribution.

## What you get

- **A rubric you can run against your own repository at each release**, split into controls that may
  decide a verdict and measurements that may only start a conversation. So an argument about "is
  this good enough" resolves against structure rather than against whoever quotes the largest
  number.
- **A discipline for third-party code that never asks you to read it.** The human effort lands at
  exactly two moments -- adopting a dependency and bumping one -- and the rest is machinery that
  runs unattended until it raises something.
- **A release an adopter can verify without trusting your account of your own process**, and an
  allowlist checked before the upload rather than after it, because the upload is the irreversible
  step.
- **A written split between what you own and what an adopter owns**, before you claim any control.
  That gap is where a control ends up unowned by both sides, each assuming the other had it.
- **A risk tier you can resolve in one question**, so a one-line fix does not carry the same
  obligation as a change to an authorisation path, and so the cheap answer errs strict rather than
  convenient.
- **Wording you can actually publish.** Approved phrasings next to the overclaims they replace, and
  a rule for saying what a gate does not prove -- which is what stops a document being rejected by
  the first reader who checks its sources.
- **The claims that failed verification, published next to the ones that survived.** Specific
  numbers to stop repeating, including several that circulate widely and did not survive the filter.

## What these are not

- **No code ships with them.** These are rules and review procedures. Where one names a control, it
  is describing something you would build, not something in this repository.
- **No certification, and no attainment.** Following them confers nothing on you, on your product,
  or on anyone adopting your product. Where you need phrasing for that, the four use "built to",
  "aligned with" and "self-assessed against", per
  [Say which kind of claim you are making](../CI-AND-STANDARDS.md).
- **Not exhaustive.** Each names at least the failure modes it was written against. None of them
  claims to be a complete account of its subject, and a completeness claim is the one thing you
  should not add when you adapt them.
- **Not independently reviewed.** No outside party has reviewed these. That is a real gap, and each
  document says where it bears on a rule.

## The four documents

Each one buys you something different. Read the line, then the document that matches the argument
you are currently losing.

| Document | What it buys you |
|---|---|
| [AI-assisted development](AI-ASSISTED-DEVELOPMENT.md) | Five named process failure modes as an organising spine, a tier ladder that says how much rigor this particular change needs, the hard line between a control and a wish -- a gate is a deterministic check, and the model never certifies its own output -- and an adversarial verification pass written as a technique, including the cases where it is pure waste. |
| [Dependency integrity](DEPENDENCY-INTEGRITY.md) | Two directions in one document. Inbound: third-party code held as a black box you deliberately do not source-review, with the obligation made finite and the human effort concentrated at adoption and at each bump. Outbound: a published build that contains only what you declared, verifiable by the person installing it. |
| [Code quality](CODE-QUALITY.md) | Rows that may decide a verdict separated from rows that may only start a conversation, the published evidence behind refusing to gate on a single number, a map from each way machine-written code goes wrong to the control that neutralises it, and review depth as a per-file decision so a large diff stays finite. |
| [Secure development](SECURE-DEVELOPMENT.md) | A written producer-versus-operator ownership split, a per-interface threat model that gives review something to check against, a finite secure-coding list, an honest read of what a green pipeline has and has not established, and a release gate that is a checklist rather than a debate. |

## Fetch the whole set in one command

Individual links are in [Download every file](#download-every-file) at the top. This section is
only for pulling all of them at once, into a `standards/` directory below wherever you run it:

```sh
for f in OVERVIEW CISO-SUMMARY CODE-QUALITY SECURE-DEVELOPMENT AI-ASSISTED-DEVELOPMENT DEPENDENCY-INTEGRITY; do
  curl -fsSL --create-dirs -o "standards/$f.md" \
    "https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/$f.md"
done
```

```powershell
$base = 'https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards'
New-Item -ItemType Directory -Force standards | Out-Null
'OVERVIEW','CISO-SUMMARY','CODE-QUALITY','SECURE-DEVELOPMENT','AI-ASSISTED-DEVELOPMENT','DEPENDENCY-INTEGRITY' |
  ForEach-Object { Invoke-WebRequest "$base/$_.md" -OutFile "standards/$_.md" }
```

The one thing not to carry over is a claim these documents decline to make -- see *What these are
not* above, and keep your edits honest about which controls you have actually built.

## The order to read them in

1. **[AI-assisted development](AI-ASSISTED-DEVELOPMENT.md)** first, because it is the one that
   changes tomorrow rather than next quarter, and because its risk tier decides how much of the
   other three applies to any given change.
2. **[Dependency integrity](DEPENDENCY-INTEGRITY.md)** next. Its controls are the most mechanical of
   the four, and you probably already have half of them; it is the one most likely to be adopted
   close to whole.
3. **[Code quality](CODE-QUALITY.md)** third. It assumes you have somewhere to put a blocking check,
   which the first two get you thinking about.
4. **[Secure development](SECURE-DEVELOPMENT.md)** last. It is the widest and the most
   setting-specific, and it is the one you should expect to rewrite rather than adopt.

If you read only one paragraph of any of them, read its scope-and-limits block. That block is what
tells you whether the rest applies to you, and it is deliberately placed before the rules.

## Where these came from, and what they assume

They were assembled from material written across several months for one working codebase, then
merged and brought up to date. **Where the source said something later shown to be wrong, it is
corrected in place and says so briefly**, because several of the most useful rules in the set exist
only because something was published, believed, and then found not to hold. A cost model derived
from a tool that had crashed before doing any work is the shape of it.

Three assumptions ride along, and they are the first things to check against your own setting:

- **A small team, sometimes one person.** Where a mainstream standard assumes a second human
  reviewer, these record a documented deviation with a compensating control and a trigger that ends
  it, rather than redefining review until it looks satisfied. If you have a real second reviewer,
  several sections get shorter.
- **A forge with a blocking pipeline, and a repository several sessions push to at once.** The
  control placement advice assumes both. The failure shapes are not forge-specific; the field names
  are.
- **The domain is stripped on purpose.** These were written in a setting with regulated data and a
  compliance regime, and the specifics of that setting are not here. Rules are expressed generically
  -- "regulated data", "an untrusted inbound payload", "a compliance regime the adopting
  organisation operates". **Where a rule could not be generalised it was dropped rather than
  disguised**, so the set is not a complete account of the practice it came from.

## What is already elsewhere on this site

The four documents link out rather than restate, and so should you when you adapt them. In
particular:

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
