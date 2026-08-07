# Which security standards actually apply to you?

**The question a security executive answers before funding anything, and the one buried under
encyclopedias that explain what each standard says rather than whether it applies to you.**

> **Take a copy:** [markdown](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/WHICH-STANDARDS-APPLY.md) or
> [Word document](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/WHICH-STANDARDS-APPLY.docx).
> [Every file, both formats](OVERVIEW.md#the-files).
> Interactive version:
> <https://wshallwshall.github.io/claude-multisession/standards/WHICH-STANDARDS-APPLY.html> --
> written out in full, because a relative link is dead in a downloaded Word file.

**This page routes, and carries no reference table.** One question, answered at least twelve ways.
Every answer points into
[the reference](https://wshallwshall.github.io/claude-multisession/standards/STANDARDS-REFERENCE.html),
which holds one row per document -- what it issues, what triggers it, the status with the date it was
checked, and a check you can run yourself -- along with the reasoning behind the cuts it sorts on.

The served page adds a selector above the routing table. It only hides rows: it computes nothing and
holds no fact this document does not. A downloaded copy gives you the same routing unfiltered --
printable, forwardable to counsel, markable.

**Two things this never does.** It will not tell you that you must comply: that a document applies to
your situation does not mean it binds you, what binds you is a clause in a contract, a statute or a
procurement rule, and nothing here is legal advice. And it will not give you a complete list. *"At
least these"* is the only claim available, so matching nothing here is not evidence that nothing
applies -- [the gaps are named on purpose](#what-this-page-did-not-assess).

---

<!--
  The line below is a sentinel. _layouts/default.html splits the rendered page on it and injects
  _includes/standards-selector.html at that point, so the interactive selector lands here without
  this markdown file carrying any HTML or template syntax. It renders as nothing on GitHub and
  pandoc emits nothing for it, so the markdown and the Word copy are unaffected. If you move it,
  move the matching string in the layout, and see tests/test_the_selector_matches_the_routing_table.
-->

<!-- STANDARDS-SELECTOR -->

## If this is your situation

At least twelve situations. Matching no row here is not evidence that nothing applies to you -- see
[what this page did not assess](#what-this-page-did-not-assess).

<!--
  COLUMN THREE IS WRITTEN OUT IN FULL, AND THAT IS NOT AN OVERSIGHT. It used to point at sections
  of this page, which stopped being true when the reference table and the reasoning moved to
  STANDARDS-REFERENCE.md. A relative link would resolve on the site and be dead in the .docx a
  reader downloaded and forwarded to counsel, which is the copy this column exists to serve. So the
  target is absolute. Column two carries the answer; column three is where to go for the row.
-->

| Your situation | What applies to you, and how it arrives | Read next |
|---|---|---|
| **You sell software, not a hosted service, to a US federal agency** | Since 2026-01-23 there is no government-wide attestation mandate. What applies to you is whatever an individual agency writes into a contract | [The producer rows](https://wshallwshall.github.io/claude-multisession/standards/STANDARDS-REFERENCE.html#requirement-shaped-items), and [why every status carries a date](https://wshallwshall.github.io/claude-multisession/standards/STANDARDS-REFERENCE.html#why-every-status-carries-a-date) |
| **You sell a hosted service to a US federal agency** | A government program certification for the offering, as a condition of the sale. It arrives as a procurement rule | [The program regimes](https://wshallwshall.github.io/claude-multisession/standards/STANDARDS-REFERENCE.html#certification-and-program-regimes) |
| **You sell to a US state, local, tribal or education buyer** | A separate program with its own statuses and tiers, arriving as a procurement requirement that varies by jurisdiction | [The program regimes](https://wshallwshall.github.io/claude-multisession/standards/STANDARDS-REFERENCE.html#certification-and-program-regimes) |
| **You place a product with digital elements on the EU market** | A regulation that binds producers directly, with no customer asking -- the only such item mapped here. Its reporting obligations apply from 2026-09-11, ahead of the rest of it. Whether what you place is a product with digital elements in the regulation's own sense is the thing to check, and this page cannot settle it | [How these actually arrive](https://wshallwshall.github.io/claude-multisession/standards/STANDARDS-REFERENCE.html#how-these-actually-arrive) |
| **A prime contractor flowed a security requirement down to you** | A clause, not a publication. Ask which contract and which clause number, and whether a deviation modifies it | [How these actually arrive](https://wshallwshall.github.io/claude-multisession/standards/STANDARDS-REFERENCE.html#how-these-actually-arrive) |
| **A commercial customer requires a certificate or an audit report before signing** | An instrument that does exist, unlike most of the reference. It is evidence about the ORGANIZATION and not about the software, and what it is worth turns on scope, accreditation, and which criteria were elected | [The organization layer is not the software layer](https://wshallwshall.github.io/claude-multisession/standards/STANDARDS-REFERENCE.html#the-organization-layer-is-not-the-software-layer) |
| **A customer questionnaire asks you for a certificate** | A questionnaire is not a regulator. Most items in the reference issue no certificate, so name what does exist: a scoped certificate for something else, a report, a self-attestation, provenance, or named control correspondences | [What each one issues](https://wshallwshall.github.io/claude-multisession/standards/STANDARDS-REFERENCE.html#what-each-one-issues) |
| **A contract clause names a ranking, such as free of OWASP Top 10 issues** | A clause with no completion condition. Convert it into a requirement set while the clause is being agreed, not when the assessment is due | [Rankings and awareness lists](https://wshallwshall.github.io/claude-multisession/standards/STANDARDS-REFERENCE.html#rankings-and-awareness-lists) |
| **You operate systems holding data covered by a sector regime** | A regulator's rule on the organization, not on a product. It arrives at a supplier as contract text rather than as regulation | [The sector regimes](https://wshallwshall.github.io/claude-multisession/standards/STANDARDS-REFERENCE.html#sector-and-jurisdiction-regimes) |
| **You are in the payment card chain** | An agreement with an acquirer or a brand. The body that writes the standard is not the body that sets your validation requirement | [The program regimes](https://wshallwshall.github.io/claude-multisession/standards/STANDARDS-REFERENCE.html#certification-and-program-regimes) |
| **You supply software to an organization in scope of a regime, and you are not** | A supplier-risk questionnaire generated by their obligation. The contract text governs what you owe, not the underlying regime | [How these actually arrive](https://wshallwshall.github.io/claude-multisession/standards/STANDARDS-REFERENCE.html#how-these-actually-arrive) |
| **Your developers build with AI coding assistants** | Nothing mapped in the reference governs it. Three documents are routinely offered as though they do, and each is about something else | [Where an AI coding assistant sits](#where-an-ai-coding-assistant-sits-in-all-this) |

---

## Where an AI coding assistant sits in all this

**Nothing mapped in the reference currently governs a developer using an AI coding assistant.** That
is a finding about the landscape, stated as an absence rather than as a gap somebody has filled. It
is the one situation above whose answer will not fit in a table cell, because the answer is a
correction to three specific documents rather than a list.

- **The SSDF community profile for AI models** addresses producing models: data sourcing, training,
  fine-tuning, evaluation. Its one sentence on the subject says the practices do not distinguish
  AI-generated source code from human-written code, which is a scoping exclusion rather than
  guidance.
- **The LLM application ranking** addresses securing an application that calls a language model at
  run time. That is a different subject from governing what an AI coding assistant writes for you, and the two
  are conflated constantly.
- **The NIST control overlays for securing AI systems** are in development. Nothing can be aligned
  with them until a draft exists, and the reference row carries the status as at the date it was
  checked.

All three carry their full rows in
[the reference](https://wshallwshall.github.io/claude-multisession/standards/STANDARDS-REFERENCE.html).
No claim is made here that anything published on this site fills that gap: the control set this site
does publish for AI-assisted work is [AI-assisted development](AI-ASSISTED-DEVELOPMENT.md), and it
claims correspondence with nothing.

---

## What this page did not assess

The routing above covers at least the items in
[the reference](https://wshallwshall.github.io/claude-multisession/standards/STANDARDS-REFERENCE.html).
That is not a complete map of the security standards landscape and does not claim to be. The selector
carries this same list as a permanent card, in every state including a result with nothing in it,
because a short result is exactly where a reader misreads silence as clearance.

**What is absent entirely.** Jurisdictions outside the US and the EU. US state privacy laws. The
rest of the ISO/IEC 27000 series and the AI management-system standards. The NIST Cybersecurity
Framework and the NIST AI Risk Management Framework. Common Criteria and product evaluation schemes.
Proprietary assurance schemes and regional cloud programs. Safety-oriented standards for industrial
and vehicle software. Sector regimes beyond the several named here as a set. Also absent: the
enforcement and liability exposure that attaches to a signature or a representation, which is a
question for counsel and not for this page. **If what applies to your situation sits in one of these,
this page will tell you nothing about it, and you should not read its silence as coverage.**

**What is covered but not primary-verified** is listed row by row in
[the reference](https://wshallwshall.github.io/claude-multisession/standards/STANDARDS-REFERENCE.html#what-is-not-primary-verified-here),
each with the check to run instead of trusting the page. One limit covers a whole class and is stated
once rather than repeated per row: several US regulator and agency sites refused automated requests
on the check date, so claims sourced to them were read through search results rather than end to end.

**Questions this page structurally does not answer.** Whether any of this binds your organization: a
clause number decides that, not a web page, and a document that applies to your situation may still
not oblige you. Whether you must comply with anything: no legal advice is given here. Which tool,
scanner, format or assessor to use: none is named. Whether anything published on this site conforms
to, aligns with or partially satisfies anything named here: it does not, and no such claim is made.
And how much any of it costs, in money, effort or time: not assessed.

---

## Related pages on this site

| If you need | Read |
|---|---|
| One row per document, with statuses, and the reasoning behind the cuts | [The standards reference](STANDARDS-REFERENCE.md) |
| Whether your teams already do this, rather than which standards apply to you | [The CISO summary](CISO-SUMMARY.md) |
| The control set for AI-assisted work | [AI-assisted development](AI-ASSISTED-DEVELOPMENT.md) |
| How much of the code a human must read | [Human review of code](REVIEW-DEPTH.md) |
| The process a build must satisfy, and who owns which control | [Secure development](SECURE-DEVELOPMENT.md) |
| Trusting code you did not write, and controlling what you publish | [Dependency integrity](DEPENDENCY-INTEGRITY.md) |
| Judging code, whoever wrote it | [Code quality](CODE-QUALITY.md) |
| Running an assessment against a standard with several hundred requirements | [Use OWASP ASVS 5.0](../ASVS-ASSESSMENT.md) |
| Saying which kind of claim you are making | [CI and standards](../CI-AND-STANDARDS.md) |
| All of it, and how to adopt | [Overview](OVERVIEW.md) |

---

**The dated facts in the routing table were checked on 2026-08-06**, the same date the reference
carries against every status. This is a snapshot, not a maintained register: several of those facts
changed within the twelve months before that date, and some will have changed since. Re-check
anything you intend to rely on at the four places named in
[Sources](https://wshallwshall.github.io/claude-multisession/standards/STANDARDS-REFERENCE.html#sources-and-how-to-re-check-them)
before quoting it.

**MIT licensed.** Adapt this, put your own name on it, and delete anything you cannot stand behind.
Re-date it when you do: a status claim inherits the date it was checked, not the date it was copied.
