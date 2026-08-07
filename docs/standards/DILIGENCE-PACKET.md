# What to ask a software vendor for, and what each answer proves

**The mirror of the standards map: that one answers which of these reach your own organization, this
one answers what to require of a vendor you are evaluating -- and what each answer actually
proves.**

> **Take a copy:**
> [markdown](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/DILIGENCE-PACKET.md)
> or [Word document](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/DILIGENCE-PACKET.docx).
> [Every file, both formats](OVERVIEW.md#the-files).

---

## In short

**The commonest mistake in vendor diligence is reading an audit report or a certificate as an answer
about the product.** Those instruments examine how a company governs
itself -- its policies, its access reviews, its change management. They never open the code. A
vendor can hold a clean report across a full twelve-month period, ship software with an
authorization flaw in it, and have said nothing false.

So sort the evidence by layer -- the company, the software, the contract -- and ask three things
before anything else:

1. **The scope statement** of whatever organization-layer instrument they offered. Not the
   certificate, not the cover page. The scope alone decides whether the thing you are buying was
   inside the examination, and for software you install and run yourself the answer is frequently
   no.
2. **An SBOM of what you will actually run.** For an installed product that is the released
   artifact; for a hosted service it is the runtime production environment. A build-time source
   manifest answers a different question.
3. **Two dates and a name:** the last dynamic test, the last incident response exercise, and who ran
   the test. Both dates are trivial to supply if they happened, and neither can be produced
   retrospectively. The name decides whether you are holding an independent look or the output of
   the vendor's own tooling.

Each of the three is a document, a date or a name. None can be answered with an adjective.

---

## How this page is organized

The three groups below are sorted by layer, which is the cut that makes the mistake visible:

- **Organization layer** -- evidence about the company.
- **Software layer** -- evidence about the thing you are buying.
- **Legal instruments** -- evidence about who pays when it goes wrong.

None of this is a reason to dismiss the organization-layer instruments. What they establish -- that
somebody outside the company examined how it governs itself, grants access and manages change, and
wrote down what they found -- is worth having, and a vendor holding none of them is a different risk
entirely. The failure is
narrower than that: reading a program attestation as an answer to "is this product secure", when no
part of it asked that question.

Every row carries what it proves, what it does not prove, and what to ask. Statuses, versions and
dates live on the landscape and reference pages, each carrying the date it was checked; this page
carries none, on purpose, so that it does not rot. For the producer's side of the same cut, see [the
organization layer is not the software
layer](STANDARDS-LANDSCAPE.md#the-organization-layer-is-not-the-software-layer).

---

## Organization layer: evidence about the company

Procurement already knows how to ask for these, and most are issued by a party other than the vendor
-- which is where their weight comes from, and none of that weight is about the product. One caveat
governs the whole group: an examination or a certification has a boundary, and software you install
and run yourself frequently falls outside it. The boundary appears in the scope statement and
nowhere else.

| The item | What it proves | What it does not prove | What to ask |
|---|---|---|---|
| **SOC 2 Type I** -- an examination report, point-in-time | A licensed firm's opinion that controls were suitably designed as of one date | That any control ever operated. It observed a design, not a period of behavior, and it looked at the organization rather than the code | Why Type I rather than Type II, and when does the first Type II period end? |
| **SOC 2 Type II** -- an examination report over a period | A licensed firm's opinion on operating effectiveness across a period, typically six to twelve months, against the Trust Services Criteria the vendor elected | That distributed software was examined; it commonly sits outside the scope boundary. The report is an attestation, not a certificate -- there is no pass mark | What did the scope cover, and what exceptions did the firm list? |
| **ISO/IEC 27001** -- a management-system certificate | That an accredited certification body certified an information security management system for a stated scope | That a product was certified. It is not "the international SOC 2" -- that instrument is an opinion plus exceptions, this one a certificate plus a scope statement | What scope is printed on the certificate, and who accredited the body that issued it? |
| **HITRUST CSF** -- a validated assessment of controls and environment | A third-party validated result at one of three named tiers -- e1, i1 and r2 -- which are not interchangeable | That distributable software was assessed. What is assessed is an organization's controls and environment, which can include the environment operating the software | Which tier was assessed, and what did the assessment take in? |
| **Sector and program instruments** -- a PCI DSS validation document, a FedRAMP or StateRAMP authorization, a CJIS policy audit | That the operating environment for a named offering was assessed against that program's own rules | Anything about software you install and run yourself. Nor that a third party did the assessing: a PCI DSS self-assessment questionnaire is completed and signed by the vendor | Which offering was in scope, was it independently assessed or self-assessed, and is the offering you are buying the one that was named? |

Three things that trip people up here:

- **An examination period that produced no exception at all is worth a question of its own.** The
  scope passage and the exceptions passage are the report; the rest is structure.
- **A certificate scope of one office or one business unit is entirely ordinary,** and narrower than
  a reader takes it to be. The standards publisher itself issues nothing -- the accredited body
  does.
- **HITRUST sits in the same set as the program instruments, and none of them outranks the others.**
  Its two lower tiers are published as fixed core control sets while the highest is tailored and
  risk-based, so a tier name on its own does not say how much was looked at. Ask for tier and scope,
  never control text: the framework's text is licensed. And the body that writes a program standard
  is often not the body that sets your validation requirement.

---

## Software layer: evidence about the thing you are buying

Nothing in the group above examined the code or the build. These four are about the code and the
build, and the question is always how each one was produced. Three of them the vendor writes about
its own system, so their weight comes from the discipline behind them rather than from who issued
them. Testing evidence is the exception and the strongest item in the group, but only in one form:
an external assessment or a penetration test, which is the one software-layer artifact a third party
issues. Ask for it by those names, because a vendor asked for "testing evidence" will usually hand
over the output of its own tooling.

| The item | What it proves | What it does not prove | What to ask |
|---|---|---|---|
| **A software bill of materials** | Which components are in the build | Whether any of it is exploitable in the configuration you will run. A conforming SBOM can still be inaccurate | Is it generated by the build for the exact released artifact, or hand-maintained? |
| **A data flow diagram** | Where data crosses a trust boundary -- which is where a control has to exist, and where a threat model becomes checkable | Anything at all, if the boundaries are not marked. Unmarked, it is a diagram rather than a security artifact | Which boundaries are marked, and which control sits on each one? |
| **Cryptography documentation** | Which algorithms and modes are used, and where data is encrypted in transit and at rest | Key management. "AES-256" names an algorithm, not a key lifecycle | Who holds the keys, where do they live, and what happens on rotation and on revocation? |
| **Testing evidence** | That a named class of defect was looked for, by a named method, on a named date and against a named version | The absence of anything. Static analysis and dynamic testing find different classes of defect, and neither substitutes for the other | Who ran it, and were they independent of the team that wrote the code? |

Two follow-ups worth the time:

- **For testing evidence:** what was in scope, which version was tested, and what triggers the next
  run -- a change, or a date on the calendar?
- **For a hosted platform's SBOM:** does it describe the runtime production environment, or a
  build-time source manifest? Those answer different questions, and only one of them describes what
  is running.

Producer side for three of these rows: [Secure development](SECURE-DEVELOPMENT.md) carries the data
flow diagram and the testing regime; [Dependency integrity](DEPENDENCY-INTEGRITY.md) carries the
SBOM, with the dated citation behind the runtime-versus-build distinction.

---

## Legal instruments: evidence about who pays when it goes wrong

These allocate liability; they do not establish security. A complete set of them tells you what
happens after a failure and nothing about its likelihood. Read them for their clock definitions and
notification paths, which is where they are weakest and always checkable.

| The item | What it proves | What it does not prove | What to ask |
|---|---|---|---|
| **A vulnerability remediation commitment (the SLA)** | An agreed maximum elapsed time, and a contractual remedy if it is missed | That anything is fixed faster | When does the clock start, when does it stop, and how does a reporter reach a human outside business hours? |
| **An incident response plan** | That a written plan exists, with named roles and a notification path | That anyone has ever executed it | The date of the last exercise, and what changed as a result |
| **Data-handling agreements** -- a data processing agreement and its sector equivalents, such as a business associate agreement | Who may process the data, for what purpose, through which subprocessors, and who must notify whom within what time | That the processing is secure. It allocates duty and liability, which is a different thing | The current subprocessor list, how you are told when it changes, and where the breach-notification clock starts |

Two failure points, both common:

- **An SLA fails at the clock's start point, not at the number.** A commitment whose clock starts
  when the vendor accepts triage is unbounded, whatever the number on it. And "patch released" is
  not "patch deployed" -- for software you run yourself, the deployment is your side of the line.
- **A plan with no exercise date is a document, not a capability.**

Producer side: [Secure development](SECURE-DEVELOPMENT.md) carries the disclosure path and the
remediation clock.

---

## What this page does not do

- **It lists at least the items a buyer commonly asks for, and is not a complete diligence list.**
  Matching nothing here is not clearance, and producing everything here is not approval.
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
