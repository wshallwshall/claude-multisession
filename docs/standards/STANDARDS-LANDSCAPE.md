# Which security standards actually apply to you?

**The question a security executive answers before funding anything, and the one buried under
encyclopedias that explain what each standard says rather than whether it applies to you.**

> **Take a copy:** [markdown](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/STANDARDS-LANDSCAPE.md) or
> [Word document](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/STANDARDS-LANDSCAPE.docx).
> [Every file, both formats](OVERVIEW.md#the-files).
> Interactive version:
> <https://wshallwshall.github.io/claude-multisession/standards/STANDARDS-LANDSCAPE.html> --
> written out in full, because a relative link is dead in a downloaded Word file.

Three parts, in the order you need them:

1. **[Routing](#if-this-is-your-situation)** -- which of these apply to your situation
2. **[Reference](#every-document-on-this-map)** -- one row per document, for when you already know
   what you are after
3. **[Why](#why-this-page-is-organized-the-way-it-is)** -- where the cuts and the vocabulary are
   argued; skippable

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

At least twelve situations. Column three points into this page, not out of the site. Matching no row
here is not evidence that nothing applies to you -- see
[what this page did not assess](#what-this-page-did-not-assess).

| Your situation | What applies to you, and how it arrives | Read next |
|---|---|---|
| **You sell software, not a hosted service, to a US federal agency** | Since 2026-01-23 there is no government-wide attestation mandate. What applies to you is whatever an individual agency writes into a contract | [The reference](#every-document-on-this-map), and [why every status carries a date](#why-every-status-carries-a-date) |
| **You sell a hosted service to a US federal agency** | A government program certification for the offering, as a condition of the sale. It arrives as a procurement rule | [The reference](#every-document-on-this-map) |
| **You sell to a US state, local, tribal or education buyer** | A separate program with its own statuses and tiers, arriving as a procurement requirement that varies by jurisdiction | [The reference](#every-document-on-this-map) |
| **You place a product with digital elements on the EU market** | A regulation that binds producers directly, with no customer asking -- the only such item mapped here. Its reporting obligations apply from 2026-09-11, ahead of the rest of it. Whether what you place is a product with digital elements in the regulation's own sense is the thing to check, and this page cannot settle it | [How these actually arrive](#how-these-actually-arrive) |
| **A prime contractor flowed a security requirement down to you** | A clause, not a publication. Ask which contract and which clause number, and whether a deviation modifies it | [How these actually arrive](#how-these-actually-arrive) |
| **A commercial customer requires a certificate or an audit report before signing** | An instrument that does exist, unlike most of this page. It is evidence about the ORGANIZATION and not about the software, and what it is worth turns on scope, accreditation, and which criteria were elected | [The organization layer is not the software layer](#the-organization-layer-is-not-the-software-layer) |
| **A customer questionnaire asks you for a certificate** | A questionnaire is not a regulator. Most items here issue no certificate, so name what does exist: a scoped certificate for something else, a report, a self-attestation, provenance, or named control correspondences | [What each one issues](#what-each-one-issues) |
| **A contract clause names a ranking, such as free of OWASP Top 10 issues** | A clause with no completion condition. Convert it into a requirement set while the clause is being agreed, not when the assessment is due | [The reference](#every-document-on-this-map) |
| **You operate systems holding data covered by a sector regime** | A regulator's rule on the organization, not on a product. It arrives at a supplier as contract text rather than as regulation | [The reference](#every-document-on-this-map) |
| **You are in the payment card chain** | An agreement with an acquirer or a brand. The body that writes the standard is not the body that sets your validation requirement | [The reference](#every-document-on-this-map) |
| **You supply software to an organization in scope of a regime, and you are not** | A supplier-risk questionnaire generated by their obligation. The contract text governs what you owe, not the underlying regime | [How these actually arrive](#how-these-actually-arrive) |
| **Your developers build with AI coding assistants** | Nothing mapped here governs it. Three documents are routinely offered as though they do, and each is about something else | [Where an AI coding assistant sits](#where-an-ai-coding-assistant-sits-in-all-this) |

---

## Where an AI coding assistant sits in all this

**Nothing mapped on this page currently governs a developer using an AI coding assistant.** That is a
finding about the landscape, stated as an absence rather than as a gap somebody has filled. It is the
one situation above whose answer will not fit in a table cell, because the answer is a correction to
three specific documents rather than a list.

- **The SSDF community profile for AI models** addresses producing models: data sourcing, training,
  fine-tuning, evaluation. Its one sentence on the subject says the practices do not distinguish
  AI-generated source code from human-written code, which is a scoping exclusion rather than
  guidance.
- **The LLM application ranking** addresses securing an application that calls a language model at
  run time. That is a different subject from governing what an AI coding assistant writes for you, and the two
  are conflated constantly.
- **The NIST control overlays for securing AI systems** are in development, with no draft overlay
  published as of 2026-08-06, so nothing can be aligned with them today.

All three carry their full rows in [the reference](#every-document-on-this-map). No claim is made
here that anything published on this site fills that gap: the control set this site does publish for
AI-assisted work is [AI-assisted development](AI-ASSISTED-DEVELOPMENT.md), and it claims
correspondence with nothing.

---

## Every document on this map

**One row per document, sorted alphabetically for lookup.** Consult this when you already know what
you are looking for. Read the "what it issues" column first when somebody asks you for an artifact:
most of these issue nothing at all, and being asked for a certificate that does not exist is the
routine case rather than the unusual one. **At least these** -- the list is not complete, and
[what this page did not assess](#what-this-page-did-not-assess) names what is missing on purpose.

Every status was checked on **2026-08-06**, stated once in the column heading rather than repeated in
every cell. Where a cell says "the check date", it means that date.

**The second column asks whose conduct a document's sentences purport to govern** -- not whether
anything obliges you to follow them, which is what the trigger column answers. Several rows below
issue nothing and demand nothing on their own; the column still says who they are written at.

| What it is | Makes demands of | What it issues | What triggers it | Status, checked 2026-08-06 | The check you can run yourself |
|---|---|---|---|---|---|
| **CISA 2026 Minimum Elements for an SBOM** | A software producer | Nothing. It defines fields, states that it creates no new requirements, and places accuracy, coverage and completeness out of its own scope. | A contract term requiring an SBOM. In US federal contracting that is now each agency's own choice. | Published 2026-07-29, replacing the minimum elements of 2021-07-12. | "Generate SBOMs to the NTIA 2021 minimum elements." Those were replaced on 2026-07-29. Separately, a conforming SBOM can still be inaccurate and incomplete -- the 2026 elements say so themselves and point at a signature, at binary analysis, and at exploitability advisories as separate mechanisms. |
| **CISA Known Exploited Vulnerabilities catalog, and BOD 26-04** | An organization, not a product | Nothing to a private organization. A directive binds only the agencies it names. | Being an agency a directive names, a contract flowing it down, or your own policy adopting the catalog. | BOD 26-04, issued 2026-06-10, supersedes and revokes the 2021 and 2019 directives. The catalog itself is unchanged. | "Catalog inclusion means a fixed federal patch deadline." The directive setting flat due dates was revoked on 2026-06-10 and replaced by a risk model. The catalog is unchanged, and the revoked directive's own page is titled as revoked. |
| **CISA Secure Software Development Attestation Form** | A software producer | A self-attestation signed by an executive, or, on an alternative route the form itself permits, a third-party assessment attached in place of the signature. Not a certificate and not an audit. | An individual agency's contract term or request. | Still published, with clearance to 2027-03-31. Optional for agencies since the memoranda requiring it were rescinded on 2026-01-23. | "Sign the federal attestation form to sell software to the US government." The memoranda requiring agencies to collect it were rescinded on 2026-01-23. Agencies may still ask; none must. Read the rescinding memorandum at the publisher, then read your own contract's clauses. |
| **CJIS Security Policy** | An organization, not a product | No central certificate. An audit by the relevant authority, with the finding landing on the agency. | An agreement giving access to the covered data. The policy names contractors within its own scope. | v6.0 issued 2024-12-27, v6.1 dated 2026-06-25. Secondary reporting says audits continue against an earlier version; confirm with the auditing authority. | A central certificate is assumed to exist, and the version being audited is assumed to be the newest published one. Confirm the audit baseline with the authority that will actually audit, on the date it will happen. |
| **CVE Program** | Input you use, not a rule you meet | Identifiers and records. Not severity, not exploitability, not priority. | A dependency policy, a customer contract or support agreement, or your own vulnerability management -- covering both what you consume and what you ship. The program demands nothing itself: what obliges anyone to act on a published identifier is the policy or the clause that quotes it. | Operating. The 2025 contract lapse was averted by an extension, and the program board was told on 2026-01-21 there is no funding cliff in March. Replacement terms are not public. | No published vulnerability identifiers is not a security property: it can equally mean nobody is looking, or that there is no route to publish one. |
| **CWE 4.20** | Input you use, not a rule you meet | An identifier for a class of mistake. Not a severity and not a priority. | Tool output, vulnerability records that map to it, and contracts asking for findings with mappings. | Version 4.20 released 2026-04-30, on a continuing versioned release cadence. | A weakness identifier is not a severity: it says what kind of mistake a finding is, not whether it matters where you run. |
| **CWE Top 25, 2025 edition** | A software producer -- a ranking, not a requirement set | Nothing. | A policy or questionnaire naming it, and occasionally procurement language asking for coverage. | 2025 edition announced 2025-12-11, project page updated 2026-01-29. Any reference to a 2026 edition is unconfirmed. | Same completion-condition problem as any ranking: it cannot be discharged as written. |
| **EPSS** | An organization, not a product | A daily probability and percentile per published CVE, for exploitation in the wild within thirty days. | A remediation policy that consumes it, or a risk model using exploitation likelihood as an input. | Version 4 deployed 2025-03-17; a version 5 was announced 2026-05-13. Which model generates the published scores was not confirmed. | Read as a verdict rather than as data. Which model version is actually generating the published scores is not confirmed here -- read the comment line in the published data file, not a blog post. |
| **EU Cyber Resilience Act, Regulation (EU) 2024/2847** | A software producer | A declaration of conformity and a mark you affix yourself after your own assessment. Some product classes require a notified body. | Placing a product with digital elements on the EU market. The trigger is where the product goes, not who buys it. | In force 2024-12-10. Reporting obligations apply from 2026-09-11, ahead of the rest of it; the main body of obligations from 2027-12-11. | Routinely treated as something a customer asks for. It is a market-access rule you satisfy before you ship, and the owner is engineering and release, not the compliance function. |
| **FedRAMP** | An organization, not a product | A program certification for a service offering, listed publicly. An agency's own authorization stays a separate decision. | Selling a cloud service to a US federal agency. | Founding 2011 memorandum rescinded 2024-07-25. Phase 3 of the replacement model active since 2026-04. Rev5 intake closes 2027-06-11. | "It is an authorization not a certification, at low, moderate or high, via the JAB or an agency." The program uses certification vocabulary and lettered classes, and the board that granted provisional authorizations no longer does so. Delivering the old correction now makes you the out-of-date party. Read the program's own definitions page. |
| **FERPA (20 U.S.C. 1232g; 34 CFR Part 99)** | An organization, not a product | Nothing. No certificate, no assessor, no registry. Enforcement runs through federal funding. | Receiving the covered federal funds, or a contract with an institution that does. | Statute in force since 1974; the regulations were substantially amended in 2008. No status change in the last 24 months. | Sought as a compliance artifact. There is no assessor and no registry to be listed in. |
| **FTC Safeguards Rule under GLBA (16 CFR Part 314)** | An organization, not a product | Nothing. A written program, a named accountable individual, and a reporting duty. | Meeting the rule's statutory definition of a covered institution, which is wider than self-image. | Substantive requirements fully effective 2023-06-09. The breach-reporting amendment became effective 2024-05-13. | Organizations that do not think of themselves as financial institutions assume it does not apply to them. The definition is statutory, not a matter of self-description. |
| **GovRAMP (formerly StateRAMP)** | An organization, not a product | A verification status granted by the program office and published on a participants list. | A US state, local, tribal or education procurement requirement, varying by jurisdiction. | Rebranded 2025-02-14. StateRAMP remains the legal entity name, operating as GovRAMP, so both names are legitimately live. | "Ask the supplier for their StateRAMP status." The program has operated under the new name since 2025-02-14 while the old one remains the legal entity name. A search on one name alone stops working. |
| **HIPAA Security Rule (45 CFR Part 164 Subpart C)** | An organization, not a product | Nothing. The enforcing agency has stated since 2003 that it recognizes no certification. | Being a covered organization, or an agreement flowing the obligation down a contract chain. | In force, operative text unchanged. A proposed overhaul published 2025-01-06 is not final; the projected final action has moved to July 2027, per secondary reporting. | Suppliers are asked to produce a certificate against it. None exists, and the enforcing agency has said so for over twenty years. It also binds an organization, not a product. |
| **HITRUST CSF (e1, i1, r2)** | An organization, not a product | A validated assessment result for an organization. There is no path by which distributable software is certified; the environment operating it can be. | A customer or procurement requirement naming it. The sources behind this page state no independent trigger, so confirm it in the contract. | Three tiers, and they are not interchangeable: e1 (essentials, one year, foundational controls), i1 (one year, established programs, middle assurance), r2 (highest, tailored and risk-based, for complex environments). The tier detail rests on secondary sources; verify anything more specific than the tier names and the scope-variance point at the publisher. | Which tier, and what was in scope. "We are certified" stated without both tells a reader very little: scope drives control count enormously, and the same highest-tier result can be a few hundred controls for one organization and a few thousand for another. |
| **in-toto attestations and Sigstore signing** | A software producer | Sigstore issues identity-bound short-lived certificates plus a public transparency log entry. These evidence who signed and when, and nothing about what was signed. Its public instances are community-operated with no service level. | A provenance or signing requirement from a customer or a package ecosystem. | No separate status is recorded here beyond the facts in this row. | Offered as a choice against build provenance. Provenance is written as an in-toto attestation, so the two are layered rather than rival options; a requirements document offering a choice between them was written by someone who had not read either. |
| **ISO/IEC 5055:2021 and OMG ASCQM 1.1** | A software producer | Nothing. Defined counts of severe structural weaknesses, once a tool implements them. | An enterprise or supplier contract specifying automated source code measures. | ISO adoption announced 2021-04-07; ASCQM 1.1 formal since July 2022. One measure family in two venues, not two obligations. | Read as two separate requirements because it appears under two publisher names. |
| **ISO/IEC 25010:2023** | Input you use, not a rule you meet | A vocabulary of quality characteristics. It states no requirement a product could meet or fail. | Requirements documents and procurement specifications that need both parties to mean the same thing. | Second edition published November 2023, cancelling and replacing the 2011 edition. Usability and portability no longer exist as top-level names. | "Usability is a characteristic." It was replaced in the 2023 edition, so a requirements document written against the 2011 names no longer resolves. |
| **ISO/IEC 27001:2022 (plus Amendment 1:2024)** | An organization, not a product | A third-party certificate from a certification body, for a stated scope. ISO itself issues nothing. | A customer or procurement requirement, most often in vendor onboarding. | Published 2022-10; Amendment 1 published 2024-02-23. The 2013-edition transition ended 2025-10-31, per secondary reporting. | Read the scope statement on the certificate. A certificate whose scope covers one office or one business unit is common, and is not what the reader assumes. Called "the international SOC 2" universally, and it is a different instrument with a different failure mode: SOC 2 gives you an opinion plus exceptions, this gives you a certificate plus a scope statement. |
| **ISO/IEC 27002:2022** | An organization, not a product | Nothing. It explains how to implement the controls the certifiable standard lists. | No independent trigger. It arrives beside a certification program, or in error on a questionnaire. | Published 2022-02. It received a climate-related amendment in the same 2024 cycle; the designation was not confirmed. | Named on a questionnaire as though a supplier could be certified or attest to it. Conformance to a guide is not a thing that exists. |
| **ISO/IEC 27006-1:2024** | An assessor | Nothing to the audited organization. It governs the auditor. | It affects you through changed audit conduct: refined remote-audit rules and a revised audit-time calculation. | Published 2024, replacing the 2015 edition. One accreditation body required use for all clients by 2026-03-31; other bodies may differ. Ask your own certification body which date applies to it. | Read as a requirement on yourself, which manufactures controls the standard never asked for. An unexplained change in audit shape or duration usually starts here rather than in your auditor's temperament. |
| **NIS2 Directive ((EU) 2022/2555)** | An organization, not a product | Nothing at EU level. Obligations, deadlines and penalties come from a member state's transposing law. | Sector plus size thresholds under national law, which has to be tested per member state. | Transposition was due 2024-10-17 and remains incomplete. The Commission referred four member states to the Court of Justice in 2026. | Read as a single EU-wide obligation with one set of thresholds. It is national law that binds, and transposition is incomplete, so the answer differs by member state and in some cases does not exist yet. |
| **NIST control overlays for securing AI systems** | An organization, not a product | Nothing today. | Nothing today. | In development, with no draft overlay published as of the check date, so nothing can be aligned with them today. | Cited in roadmaps as though alignment were possible now. No draft exists to align with. |
| **NIST SP 800-53 Rev. 5 (Release 5.2.0), with SP 800-53B and FIPS 199** | An organization, not a product | Nothing. A baseline is selected and an authorizing official decides. NIST certifies nobody. | A federal contract, a program requirement, or a customer questionnaire mapping its control set onto you. | Release 5.2.0 issued 2025-08-27 and added three controls; the baselines were not changed. FIPS 199 unchanged since February 2004. | Questions arrive attached to the wrong link in the chain. The chain worth carrying: FIPS 199 categorizes, SP 800-60 Rev. 1 guides the categorizing, FIPS 200 sets a floor, SP 800-53B selects a baseline, SP 800-53 supplies the control text, and SP 800-53A assesses it. A release is also not a revision. |
| **NIST SP 800-53A Rev. 5 (Release 5.2.0)** | An assessor | Nothing to the audited organization. | It affects you as the source of the questions an assessor asks about a deployed instance. | Release 5.2.0 issued 2025-08-27, adding assessment procedures for three controls. | "Addressed to an assessor" does not mean "what an auditor will ask you for". It tells someone how to conduct an examination. Building to it produces controls nothing ever required. |
| **NIST SP 800-122** | An organization, not a product | Nothing. Guidance. | No independent trigger. It sits beside the federal control chain, covering personally identifiable information (PII). | Still Final. Its withdrawal exists only as intent inside an unfinished working draft. | "SP 800-122 was withdrawn." It is still Final, and the publication's own record page shows status and date. |
| **NIST SP 800-161 Rev. 1 (upd 1)** | An organization, not a product | Nothing. Guidance, structured as an overlay on the control catalog. | A federal contract flow-down, or a prime pushing supply chain terms down. | Revision 1 published May 2022; update 1 issued 2024-11-01. No Revision 2 exists in any form, draft or final. | "Revision 2 is out." There is no Revision 2. The 2024-11-01 date people cite is an update to Revision 1, and the publication's own record page shows status and date. |
| **NIST SP 800-171A Rev. 3 and SP 800-172A Rev. 3** | An assessor | Nothing to the audited organization. A CUI assessment run to these procedures carries findings only, and there is no pass mark. | An assessment somebody else scopes and runs. | 800-171A Rev. 3 final 2024-05-14; 800-172A Rev. 3 final 2026-05-13. The defense program rule still names the June 2018 and March 2022 versions. | The newest published procedure is assumed to be the one being assessed against. The program rule still names earlier versions. |
| **NIST SP 800-218 v1.1 (SSDF)** | A software producer | Nothing. No conformance criteria, no levels, no assessment procedure. | A contract clause, an agency assurance policy, or a questionnaire quoting practice identifiers. | Final since 2022-02-03 and not withdrawn. A draft successor, SP 800-218r1 (v1.2), has been open since 2025-12-17 and is not final. | "Map controls to the current SSDF, or to SSDF 1.2." v1.1 of 2022 is the only final version. The publisher's own publications listing shows Final against one and Draft against the other. |
| **NIST SP 800-218A (SSDF community profile for AI models)** | A software producer | Nothing. | Building or fine-tuning generative AI or dual-use foundation models, when a contract names it. | Final 2024-07-26. The executive order that commissioned it was revoked 2025-01-20; the publication itself stands. | Its declared scope is producing AI models. Its single sentence on assisted code says the practices do not distinguish it from human-written code, which is a scoping exclusion rather than guidance. Search the publication for that sentence -- it is the whole of the coverage. |
| **OWASP ASVS 5.0.0** | A software producer | Nothing. Its own assessment chapter states that OWASP certifies no vendor or software. | A customer contract or questionnaire naming a verification level. | Released 2025-05-30, superseding 4.0.3 of 2021-10-28. Identifiers were reorganized rather than carried across. | Cited as though a level could be certified. Identifiers from the prior edition do not carry across either, so a policy quoting an old identifier resolves to something different or to nothing. |
| **OWASP SAMM v2.0** | An organization, not a product | Nothing. A self-assessed score from 0 to 3 per practice, plus a community Benchmark for comparison. | Internal program work, board reporting, or a customer asking how mature your program is. | Released February 2020 and still current on the check date. The Benchmark was first published June 2024. | A self-assessed score is offered as though it were an independent finding. |
| **OWASP Top 10 for LLM Applications, 2026 edition** | A software producer -- a ranking, not a requirement set | Nothing. | An AI feature review, a customer AI questionnaire, or an internal policy naming it. | Dated 2026-08-03 on the project's own resource page, with press coverage on 2026-08-04. The prior edition dates from 2024-11-18. | Offered as governance for what an AI coding assistant writes for you. It addresses securing an application that calls a language model at run time, which is a different subject, and the two are conflated constantly. |
| **OWASP Top 10:2025** | A software producer -- a ranking, not a requirement set | Nothing. OWASP calls it an awareness document. | A contract clause or questionnaire saying a product was tested against it, and scanner report headings. | The 2025 edition is current on the project's own page, which stamps no final publication date. A release candidate in November 2025 and finalization in January 2026, per secondary coverage. Two categories are new, and an older category was absorbed into another. | A ranking has no completion condition and cannot be discharged as written. Convert it into a requirement-set clause while the clause is being agreed; by assessment time the only remaining options are to argue or to over-deliver. |
| **PCI DSS v4.0.1** | An organization, not a product | A report or a self-assessment questionnaire, plus a signed attestation. No certificate exists. | An agreement with an acquirer or a brand, arriving through the payment chain rather than a regulator. | v4.0.1 published 2024-06; v4.0 retired 2024-12-31; the future-dated requirements became mandatory 2025-03-31. | "We are working toward 4.0, and the future-dated requirements are still future." v4.0 retired 2024-12-31, leaving v4.0.1, and the future-dated requirements became mandatory 2025-03-31. The body that writes the standard is not the body that sets your validation requirement. |
| **SBOM formats: SPDX (ISO/IEC 5962:2021) and CycloneDX (ECMA-424, 2nd edition)** | Input you use, not a rule you meet | A machine-readable document a parser accepts. No conformance mark exists for either. | A customer or a regime asking for an SBOM in a commonly used machine-readable format. | ISO/IEC 5962:2021 describes SPDX 2.2.1, which current tooling has moved past; SPDX 3.0 sat at draft stage on the check date. ECMA-424 2nd edition was adopted December 2025 and defines CycloneDX v1.7. | "Prefer SPDX because it is the ISO standard." A format's standards-body lineage is not a compliance grade, and the widely quoted ISO number attaches to a 2021-era version rather than to what current tooling emits. Choosing on lineage answers a question nobody in the transaction asked. |
| **SEC cybersecurity disclosure rules (17 CFR Parts 229, 232, 239, 240, 249)** | An organization, not a product | Nothing. The output is a filing. No assessor and no examination. | Being a registrant of the relevant class. Nothing about your stack changes the answer. | Adopted 2023-07-26, effective 2023-09-05. A rescission petition was filed 2025-05-22; no adopting release was found as of the check date. | Treated as a security control requirement that engineering choices can satisfy or avoid. It is a disclosure duty attached to registrant status. Nothing asked here establishes that status, so this is a fact about your organization to go and check, never an inference drawn from your answers. |
| **SLSA v1.2** | A software producer | Nothing. Machine-readable provenance the consumer verifies. There is no register of levels. | A customer or a package ecosystem asking for build provenance. | Approved 2025-11-12, released 2025-11-24. It restored a Source track with four levels; there is still no Build L4. | "Require SLSA Level 4." There is no Build L4. Since v1.2 there is a Source L4, so a bare level number no longer identifies a requirement. Read the specification's own track pages and write the track beside the level. |
| **SOC 2 (Type 1 and Type 2)** | An organization, not a product | An examination report carrying a licensed firm's opinion. Restricted use, no pass mark, no certificate. | A customer questionnaire or contract clause, overwhelmingly in US business-to-business sales. | Criteria are the 2017 Trust Services Criteria with 2022 revised points of focus, posted 2023-09-30. The governing attestation standard applies to reports dated on or after 2022-06-15. | Read the scope statement and the listed exceptions. A report with no exceptions over twelve months is unusual enough to be worth asking about, and the cover page tells you nothing. Type 2 covers operating effectiveness over a period, typically six to twelve months; Type 1 is a point-in-time design opinion only. If what you sell is distributed software rather than a hosted service, the product can sit entirely outside the report's scope boundary. |
| **The US defense CUI chain: SP 800-171 as pinned by contract, the CMMC program, the DFARS clauses** | An organization, not a product | Depends on the rung: a self-scored assessment, an annual affirmation, a third-party certificate, or a government assessment result. | A contracting officer inserting a clause, or a prime flowing it down. Nothing here arrives on its own. | Program rule effective 2024-12-16; acquisition rule effective 2025-11-10; phases beyond the first suspended by policy on 2026-07-13, per secondary reporting. | Two of them. "Defense work has to move to Revision 3": a class deviation issued 2024-05-02 pins the safeguarding clause to Revision 2 and stands until rescinded, per secondary reporting, so the clause text alone gives the wrong revision. And "third-party certification becomes a condition of award in November 2026": Phase 2 and later milestones were suspended by policy on 2026-07-13, per secondary reporting, and neither rule was amended or repealed. Ask the contracting officer which level the solicitation requires, and check the rulemaking index. |

[The reference table](STANDARDS-REFERENCE.md) is these same rows in a file of their own, grouped by
addressee rather than sorted alphabetically, for anyone who wants the lookup without the guide around
it. It carries the same statuses and the same check date.

---

## Why this page is organized the way it is

**Skip this section without losing anything above it.** It explains the two cuts the reference uses,
the routes by which any of this arrives, and the reason every status carries a date. If the routing
answered your question, you are done.

### Who a document is addressed to

The addressee is the most stable fact about a document. Status, trigger and enforcement machinery
change constantly; the audience almost never does. That is why the reference sorts on it, and why the
column sits second rather than last. The column is headed **makes demands of**, and the test it runs
is whose conduct a document's sentences purport to govern -- not whether the document succeeds in
obliging anyone on its own, which most of them do not. What obliges you is the clause, the policy or
the regime that quotes the document, and that is the trigger column's question rather than this one.

**This is about who the sentences bind, not what the document is about.** The two come apart, and
that is the whole value of the cut. A publication can be entirely about how software gets built and
still be addressed to an organization, not a product -- its development controls are written
to bind an entity with personnel, facilities and an authorization boundary, not to bind a build.
Sorting by subject matter puts such a document next to a producer framework and invites a producer to
answer requirements that were never asked of them.

**"Addressed to an assessor" does not mean "what an auditor will ask you for".** It means the
document tells someone how to conduct an examination -- the procedure, and who may run it. These are
method manuals for the examiner, not the evidence you hand over. Read the other way, the natural next
move is to build to them, which manufactures controls nothing ever required. The selector puts every
such item in its own block, under that label, for exactly this reason.

**The fourth label names a use rather than an audience, and that is deliberate.** Nothing in that
group is written at anybody: its documents define the terms other documents' sentences are written
in, rather than governing anyone's conduct. That is what separates it from the other three, and it
is a fact about normative status rather than about importance -- a producer uses every item in the
group. A dependency policy is written in vulnerability identifiers, a scanner reports in weakness
identifiers, an SBOM is emitted in one of two formats, and a requirements document borrows the
quality vocabulary. Labeling the group by the absence invites a reader to skip it, which is the
wrong move for material their own policies are written in. Where a demand does exist it comes from
the policy, the contract or the vulnerability management program that quotes the document, never
from the document, so each row's trigger cell names that source instead.

| Makes demands of | What it is describing | The failure when you get it wrong |
|---|---|---|
| **A software producer** | How code is built, reviewed, released and evidenced | An operating-environment instrument offered as evidence about a build practice it never examined |
| **An organization, not a product** | How an entity runs, governs and secures itself -- its program, people, processes and, where it has them, the systems it operates and its authorization boundary | A management-system or program instrument offered as evidence that a product is secure |
| **An assessor** | How an audit or examination is conducted, and by whom | Assessor rules read as requirements on yourself, producing controls the standard never asked for |
| **Input you use, not a rule you meet** | Identifier spaces, formats and vocabularies that policies, scanners and contracts are written in. A producer uses all of them and conforms to none of them | Read as "skip this". Also an identifier read as a severity, or a format's standards-body lineage read as a compliance grade |

**One row, one place.** Every item appears exactly once in the reference. An item addressing two
audiences is placed where the cost of acting lands.

### The organization layer is not the software layer

**This is the single most useful sentence on the subject.** A buyer asks a software vendor for a
certificate or an audit report and reads the answer as evidence about the SOFTWARE. Those instruments
are evidence about the ORGANIZATION. A vendor can hold every one of them and still ship insecure
code, because none of them looked at the code.

That does not make them worthless. They establish that a company has a functioning security program,
which is a real thing to know and worth paying for. They simply do not answer "is this product
secure", and the failure is reading them as though they did.

Three of them below, presented as members of a set alongside the payment-chain validation
instruments, the two cloud program authorizations, and the law-enforcement-data policy that sit in
the same layer. Full rows, with statuses and the check date, are in
[the reference above](#every-document-on-this-map).

| The instrument | What it actually is | The question that makes it useful |
|---|---|---|
| **An examination report on a service organization** | A licensed firm's opinion against elected criteria, restricted in use, with no pass mark and no certificate. Type 2 covers operating effectiveness over a period, typically six to twelve months; Type 1 is a point-in-time design opinion only | Read the scope statement and the listed exceptions. A report with no exceptions over twelve months is unusual enough to be worth asking about. The cover page tells you nothing |
| **A management-system certificate from an accredited body** | A certificate for a stated scope, issued by a certification body rather than by the standards publisher. Universally called "the international" version of the report above, and it is a different instrument with a different failure mode | Read the scope statement on the certificate. A certificate whose scope covers one office or one business unit is common, and is not what the reader assumes |
| **A validated assessment of an organization's controls and environment** | A third-party validated result at one of several named tiers, which are not interchangeable. Explicitly not a software product certification: there is no path by which distributable software is certified, though the environment operating it can be | Which tier, and what was in scope. Scope drives control count enormously -- the same highest tier can be a few hundred controls for one organization and a few thousand for another |

**If what you sell is distributed software rather than a hosted service, the product can sit entirely
outside the scope boundary of every row above.** That is not a loophole and not an accusation; it is
what the scope statement says, and it is why the third column of that table is the column that
matters.

The cloud program authorizations belong in this layer for the same reason: they assess a service
offering you operate, which is why they sit with the operating organization even though a software
company usually pays for them.

### What each one issues

Read this before answering any request for an artifact. The category decides whether the request can
be satisfied at all.

- **Nothing.** There is no artifact to obtain. Offer what exists instead: named control
  correspondences, your own evidence, a written program. This covers most items in the reference,
  including every framework and every control catalog.
- **A self-attestation you sign yourself.** The signature is the instrument and the exposure is
  yours. Nobody independent looked.
- **An assessment or examination report.** Usually restricted in use, and there is no pass mark. One
  kind carries a licensed firm's opinion; a controlled-information assessment carries findings only.
- **A third-party certificate from an accredited body.** A certificate for a stated scope. The
  accreditation is what gives it weight, and the scope statement is what limits it.
- **A government program status or certification.** Recorded and published by the program, for a
  named offering rather than for a company.
- **A conformity mark you affix yourself after your own assessment.** You assess, declare and mark. A
  third body is involved only for some product classes.
- **Identifiers, a score, or a measurement definition.** Data, not a verdict. A measurement
  definition produces a number only once some tool implements it.

### How these actually arrive

At least five routes. This is the part that decides where budget and ownership land, because the
route determines the owner far more reliably than the subject does.

| Route in | What it looks like on the day | What actually governs | Who owns the response internally |
|---|---|---|---|
| **Direct binding on a producer** | A market-access rule you satisfy before you ship, with no customer asking | The regulation and the conformity route it sets | Engineering and release, not the compliance function |
| **A clause in one specific contract, or a flow-down from a prime** | A clause number in a solicitation or an award | The clause text, plus any deviation that modifies it. Not the publication it cites | Contracts, with security supplying the evidence |
| **A supplier-risk clause inside somebody else's regime -- the questionnaire** | A spreadsheet quoting identifiers drawn from several unrelated documents | Their obligation, not yours. It never binds you; it obliges them to ask | Security with sales, and it is the largest recurring cost in this table |
| **A procurement or payment-chain agreement** | A program status or a validation requirement as a condition of the deal | The program's or the counterparty's own rules, which may not be the standard author's | The program owner, usually outside security |
| **Your own risk decision** | Nobody asked. You adopted it | Your own written scope, and nothing else | Whoever proposed it, and that should be written down |

**Exactly one item in the reference takes the first route.** The market-access regulation binds a
producer with nobody asking: placing a product with digital elements on that market is the trigger,
so where the product goes decides it and who buys it does not. Everything else arrives because
somebody asked -- a contracting officer inserted a clause, a prime flowed one down, a customer sent a
questionnaire, an acquirer set a validation requirement, or you adopted it yourself. So the first
question about any named standard is never "what does it say". It is **who is asking, and in which
document**.

The routine consequence is a budget in the wrong place. A market-access rule has to be satisfied
before shipping, so it is owned by engineering and release. Everything else is owned by whoever holds
the contract, with security supplying evidence. Sorting a program by subject matter puts both in the
same pile and gives them to the same team.

**A defense-style obligation begins with a clause number, not a publication.** Ask which solicitation,
which contract and which clause number, and check whether a deviation modifies the clause -- the
clause text alone can name the wrong revision.

### Why every status carries a date

Staleness takes at least five shapes. Naming them is worth more than any individual fact, because you
will meet a sixth.

1. **A mandate rescinded while its artifacts survive.** The instruction goes; the form, the signature
   and any standing duty attached to it do not.
2. **A draft cited as though final.** The most common shape and the hardest to see, because a draft
   and a final look identical once quoted in a policy.
3. **A published version that is not the version being audited.** The newest file on a publisher's
   site is not automatically the assessment baseline.
4. **A rename.** Search stops working, and both names are often legitimately live at once.
5. **A milestone suspended by policy while the rule that set it stands unamended.** The rule text and
   the operative position then disagree, and only one of them is in the publication. The defense
   program's phases beyond the first, suspended on 2026-07-13 with neither rule amended nor repealed,
   are the live example; its row above carries the full correction.

The worked example for the first shape is the federal software attestation story, told as one event
when it was two, seven months apart. EO 14028 (2021) directed the guidance. OMB M-22-18 and M-23-16
turned it into a collection requirement. EO 14144 (January 2025) would have added submission to a
repository, central verification and referral of failures -- and EO 14306, on 2025-06-06, struck that
apparatus. Then OMB M-26-05, on 2026-01-23, rescinded the collection mandate itself. Anyone
describing a single January 2026 event has lost the fact that the verification model was already gone
in mid-2025. The status of the federal repository that received submissions is unknown as of
2026-08-06: not reported running, not reported gone. And a signed self-attestation is a different
instrument from a certificate -- rescinding the instruction that prompted a signature is prospective,
and unsigns nothing.

**The instrument check.** What binds you is a clause, and a clause pins a dated version. So "use the
current publication" is frequently the wrong instruction: a regulation citing a publication by date
keeps citing it after the publisher supersedes it, which is how a rule stays stable rather than an
error in it. It is also why no identifier here appears without its version, revision, edition or
release -- a bare identifier resolves differently depending on when and where you look it up.
[The assessment method page](../ASVS-ASSESSMENT.md) covers pinning a standard's corpus so it cannot
shift underneath an assessment already in progress.

---

## What this page did not assess

This page maps at least the items in [the reference above](#every-document-on-this-map). It is not a
complete map of the security standards landscape and does not claim to be. The selector carries this
same list as a permanent card, in every state including a result with nothing in it, because a short
result is exactly where a reader misreads silence as clearance.

**What is absent entirely.** Jurisdictions outside the US and the EU. US state privacy laws. The
rest of the ISO/IEC 27000 series and the AI management-system standards. The NIST Cybersecurity
Framework and the NIST AI Risk Management Framework. Common Criteria and product evaluation schemes.
Proprietary assurance schemes and regional cloud programs. Safety-oriented standards for industrial
and vehicle software. Sector regimes beyond the several named here as a set. Also absent: the
enforcement and liability exposure that attaches to a signature or a representation, which is a
question for counsel and not for this page. **If what applies to your situation sits in one of these,
this page will tell you nothing about it, and you should not read its silence as coverage.**

**What is covered but not primary-verified** is listed row by row in
[the reference file](STANDARDS-REFERENCE.md#what-is-not-primary-verified-here), each with the check to
run instead of trusting this page. One limit covers a whole class and is stated once rather than
repeated per row: several US regulator and agency sites refused automated requests on the check date,
so claims sourced to them were read through search results rather than end to end.

**Questions this page structurally does not answer.** Whether any of this binds your organization: a
clause number decides that, not a web page, and a document that applies to your situation may still
not oblige you. Whether you must comply with anything: no legal advice is given here. Which tool,
scanner, format or assessor to use: none is named. Whether anything published on this site conforms
to, aligns with or partially satisfies anything named here: it does not, and no such claim is made.
And how much any of it costs, in money, effort or time: not assessed.

---

## Sources, and how to re-check them

A status is authoritative in at least these four places:

- **The publisher's own publications listing**, which shows Final, Draft, Withdrawn or Superseded
  against a dated record. For the NIST items that is the
  [CSRC publication records](https://csrc.nist.gov/publications); for the EU items, the
  [Commission's own policy pages](https://digital-strategy.ec.europa.eu/en/policies/cyber-resilience-act);
  for the US federal memoranda and rules, the issuing office and the
  [Federal Register](https://www.federalregister.gov/).
- **The program's own definitions page**, for anything whose vocabulary has moved. The
  [cloud program's definitions](https://www.fedramp.gov/2026/definitions/) is the live example.
- **The clause, plus any deviation that modifies it.** A publication database answers a different
  question from the one your contract asks.
- **The data file's own header**, for a generated score. The published exploit-probability data
  carries a comment line naming the generating model.

Where a status would otherwise be unverifiable, read the primary document: the
[January 2026 memorandum that rescinded the federal attestation mandate](https://www.whitehouse.gov/wp-content/uploads/2026/01/M-26-05-Adopting-a-Risk-based-Approach-to-Software-and-Hardware-Security.pdf),
the [2026 SBOM minimum elements](https://www.cisa.gov/resources-tools/resources/2026-minimum-elements-software-bill-materials-sbom),
the [SSDF publication listing](https://csrc.nist.gov/Projects/ssdf/publications), and the
[build and source track specifications](https://slsa.dev/spec/v1.2/build-requirements).

---

## Related pages on this site

| If you need | Read |
|---|---|
| The same rows as a standalone lookup file, grouped by addressee | [The reference table](STANDARDS-REFERENCE.md) |
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

**Every status on this page was checked on 2026-08-06.** This is a snapshot, not a maintained
register: several of those facts changed within the twelve months before that date, and some will
have changed since. Re-check anything you intend to rely on at the four places named in
[Sources](#sources-and-how-to-re-check-them) before quoting it.

**MIT licensed.** Adapt this, put your own name on it, and delete anything you cannot stand behind.
Re-date it when you do: a status claim inherits the date it was checked, not the date it was copied.
