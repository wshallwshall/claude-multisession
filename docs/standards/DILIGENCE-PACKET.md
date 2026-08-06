# What to ask a software vendor for, and what each answer proves

**The mirror of the standards map: that one answers which of these reach you, this one answers what
a buyer will ask you to produce -- and what each item actually proves.**

> **Take a copy:**
> [markdown](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/DILIGENCE-PACKET.md)
> or [Word document](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/DILIGENCE-PACKET.docx).
> [Every file, both formats](OVERVIEW.md#the-files).

---

## The mistake this page exists to prevent

The commonest failure in vendor diligence is accepting organization-layer evidence as software-layer
evidence. A buyer asks for an audit report or a certificate, receives one, and reads it as an answer
about the product. It is not. The examination looked at how a company runs itself -- its policies,
its access reviews, its change management -- and never opened the code. A vendor can hold a flawless
report across a full twelve-month period and ship software with an authorization flaw in it, and
nothing in the report is false.

That is not a reason to dismiss these instruments. What they establish -- that somebody outside the
company examined how it governs itself, grants access and manages change, and wrote down what they
found -- is worth having, and a vendor holding none of them is a different risk entirely. The
failure is narrower: reading a program attestation as an answer to "is this product secure", when no
part of it asked that question.

So the groups below are sorted by layer, which is the cut that makes the mistake visible:

- **Organization layer** -- evidence about the company.
- **Software layer** -- evidence about the thing you are buying.
- **Legal instruments** -- evidence about who pays when it goes wrong.

Every row carries what it proves, what it does not prove, and the one question that makes it useful.
These are at least the items a buyer commonly asks for, not a complete list. Statuses, versions and
dates live on the landscape and reference pages, each carrying the date it was checked; this page
carries none, on purpose, so that it does not rot. For the producer's side of the same cut, see [the
organization layer is not the software
layer](STANDARDS-LANDSCAPE.md#the-organization-layer-is-not-the-software-layer).

---

## Organization layer: evidence about the company

These are the instruments a procurement team already knows how to ask for, and each is issued by a
party other than the vendor -- which is where their weight comes from, and none of that weight is
about the product. At least these five. One caveat governs all of them: an examination or a
certification has a boundary, and software you install and run yourself frequently falls outside it.
That shows in the scope statement and nowhere else, which is why every row's last column sends you
to a document rather than to a claim.

| The item | What it proves | What it does not prove | The one question that makes it useful |
|---|---|---|---|
| **An examination report, point-in-time (SOC 2 Type I)** | A licensed firm's opinion that controls were suitably designed as of one date | That any control ever operated. It observed a design, not a period of behavior, and it looked at the organization rather than the code | Why Type I rather than Type II, and when does the first Type II period end? |
| **An examination report over a period (SOC 2 Type II)** | A licensed firm's opinion on operating effectiveness across a period, typically six to twelve months, against the Trust Services Criteria the vendor elected | It is an attestation report, not a certificate -- there is no pass mark. If what you buy is distributed software rather than a hosted service, the product can sit outside the scope boundary | What did the scope cover, and what exceptions did the firm list? Those two passages are the report; an examination period that produced no exception at all is itself worth a question |
| **A management-system certificate (ISO/IEC 27001)** | That an accredited certification body certified an information security management system for a stated scope. The standards publisher itself issues nothing | It is not "the international SOC 2" -- a different instrument with a different failure mode, an opinion plus exceptions versus a certificate plus a scope statement. It certifies a management system, not a product | What scope is printed on the certificate, and who accredited the body that issued it? A single office or one business unit is an ordinary scope to hold, and it is narrower than a reader takes it to be |
| **A validated assessment of controls and environment (HITRUST CSF)** | A third-party validated result at one of three named tiers -- e1, i1 and r2 -- which are not interchangeable | What is assessed is an organization's controls and environment. The environment operating software can be assessed; distributable software itself is not what gets certified | Which tier was assessed, and what did the assessment take in? The lower tiers are published as fixed core control sets while the highest is tailored and risk-based, so a tier name on its own does not say how much was looked at. Ask for tier and scope, never control text -- the framework's text is licensed. It sits in the same set as the row below, and no more should be read into it than into any of them |
| **Sector and program instruments, as a set** | That the operating environment for a named offering was assessed against that program's own rules. At least these four sit in this set together and none of them outranks the others: a PCI DSS validation document, a FedRAMP authorization, a StateRAMP authorization, and a CJIS policy audit -- alongside the row above | Anything about software you install and run yourself. The body that writes such a standard is often not the body that sets your validation requirement | Which offering was in scope, and is the offering you are buying the one that was named? |

---

## Software layer: evidence about the thing you are buying

Nothing in the group above examined the code or the build. These four are about the code and the
build, and the question is always how each one was produced. Three of them the vendor writes about
its own system, so their weight comes from the discipline behind them rather than from who issued
them. Testing evidence is the exception, and it is why that row is the strongest thing in this
group: an external assessment or a penetration test is written by somebody independent of the team
that wrote the code, which makes it the one software-layer item a third party issues. You have to
ask for it by name, because a vendor asked for "testing evidence" will usually hand over the output
of its own tooling. At least these four. This site publishes the producer-side control behind three
of them; the rows link out rather than restating it here.

| The item | What it proves | What it does not prove | The one question that makes it useful |
|---|---|---|---|
| **A software bill of materials** | Which components are in the build | Whether any of it is exploitable in the configuration you will run. An SBOM establishes what is in the build, never that it is safe, and a conforming one can still be inaccurate | Is it generated by the build for the exact released artifact, or hand-maintained? And for a hosted platform, is it an SBOM of the runtime production environment rather than a build-time source manifest? Those two answer different questions, and only one of them describes what is running. Producer side, with the dated citation behind that distinction: [Dependency integrity](DEPENDENCY-INTEGRITY.md) |
| **A data flow diagram** | Where data crosses a trust boundary, which is where a control has to exist and where a threat model becomes checkable | Anything at all, if the boundaries are not marked. A data flow diagram without marked trust boundaries is a diagram, not a security artifact | Which boundaries are marked, and which control sits on each one? Producer side: [Secure development](SECURE-DEVELOPMENT.md) |
| **Cryptography documentation** | Which algorithms and modes are used, and where data is encrypted in transit and at rest | Key management. "AES-256" names an algorithm, not a key lifecycle | Who holds the keys, where do they live, and what happens on rotation and on revocation? |
| **Testing evidence** | That a named class of defect was looked for, by a named method, on a named date and against a named version | The absence of anything. Static analysis and dynamic testing find different classes of defect, and neither substitutes for the other | Who ran it, and were they independent of the team that wrote the code? Then: what was in scope, which version was tested, and what triggers the next run -- a change, or a date on a calendar? Producer side: [Secure development](SECURE-DEVELOPMENT.md) |

---

## Legal instruments: evidence about who pays when it goes wrong

These allocate liability; they do not establish security. A complete set of them tells you what
happens after a failure and nothing about its likelihood. Read them for their clock definitions and
notification paths, which is where they are weakest and always checkable. At least these three.

| The item | What it proves | What it does not prove | The one question that makes it useful |
|---|---|---|---|
| **A vulnerability remediation commitment (the SLA)** | An agreed maximum elapsed time, and a contractual remedy if it is missed | That anything is fixed faster. An SLA fails at the clock's start point, not at the number: a commitment whose clock starts when the vendor accepts triage is unbounded, whatever the number on it. And "patch released" is not "patch deployed" -- for software you run yourself, the deployment is your side of the line | When does the clock start, when does it stop, and how does a reporter reach a human outside business hours? Producer side: [Secure development](SECURE-DEVELOPMENT.md) |
| **An incident response plan** | That a written plan exists, with named roles and a notification path | That anyone has ever executed it | The date of the last exercise, and what changed as a result. A plan with no exercise date is a document, not a capability |
| **Data-handling agreements** | Who may process the data, for what purpose, through which subprocessors, and who must notify whom within what time. One row for a data processing agreement and its sector equivalents, such as a business associate agreement | That the processing is secure. It allocates duty and liability, which is a different thing | The current subprocessor list, how you are told when it changes, and where the breach-notification clock starts |

---

## If you only ask three things

1. **The scope statement of whatever organization-layer instrument they offered.** Not the
   certificate, not the cover page -- the scope. It alone decides whether the thing you are buying
   was inside the examination at all, and for distributed software the answer is frequently no.
2. **An SBOM of the artifact or environment you will actually run.** For an installed product that
   is the released artifact; for a hosted service it is the runtime production environment, not a
   build-time manifest. Those answer different questions, and only one describes what is running.
3. **Two dates: the last dynamic test, and the last incident response exercise -- and who ran the
   first one.** Both dates are trivial to supply if they happened, and neither can be produced
   retrospectively. The name behind the test decides whether you have vendor tooling output or an
   independent look.

The reason these three and not others: each is a document or a date that either exists or does not,
and none of them can be answered with an adjective.

---

## What this page does not do

- **At least these, and not a complete diligence list.** Matching nothing here is not clearance, and
  producing everything here is not approval.
- **Not legal advice.** What you are able to require is decided by a contract clause, not by a web
  page. Nothing here has been reviewed by counsel.
- **No assessor, tool, format or vendor is named.** The rows describe instruments, not the market
  that sells them.
- **No status, version or edition claim appears here.** Those live on the landscape and reference
  pages, each carrying the date it was checked, so a stale fact is visible as one.
- **A complete packet is not a secure product, and a thin packet is not an insecure one.** Both are
  evidence about what you are able to check, which is a more modest thing than either side of a
  procurement conversation usually wants it to be.

---

## Where to go next

| If you need | Read |
|---|---|
| Which of these reach your own organization, with statuses and dates | [Which standards apply to you](STANDARDS-LANDSCAPE.md) |
| One row per document, as a lookup | [Security standards reference](STANDARDS-REFERENCE.md) |
| What to require of your own developers | [The CISO summary](CISO-SUMMARY.md) |
| The process a build must satisfy, including dynamic testing, the data flow diagram and disclosure | [Secure development](SECURE-DEVELOPMENT.md) |
| SBOM, provenance, and what gets published | [Dependency integrity](DEPENDENCY-INTEGRITY.md) |
| Whether a written rule can actually stop a change | [What is actually enforced](CI-ENFORCEMENT.md) |

**None of this certifies anything.** MIT licensed. Adapt it, put your own name on it, and delete
anything you cannot stand behind.
