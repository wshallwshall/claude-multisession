# Security standards reference: what each one issues, and what triggers it

**One row per document. Consult this while working, already knowing what you are looking for.** If
instead you are trying to work out which of these applies to you at all, read
[the guide](STANDARDS-LANDSCAPE.md) -- it is the same facts organized around your situation rather
than around the documents, and it carries an interactive selector on the served site.

> **Take a copy:**
> [markdown](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/STANDARDS-REFERENCE.md)
> or [Word document](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/STANDARDS-REFERENCE.docx).
> [Every file, both formats](OVERVIEW.md#the-files).

**Every status below was checked on 2026-08-06, and that date is stated once rather than repeated in
every cell.** Where a cell says "the check date", it means that date. This is a snapshot, not a
maintained register: several of these facts changed within the twelve months before it, and some will
have changed since.

**At least these items.** This is not a complete map of the security standards landscape and does not
claim to be. [What the guide did not assess](STANDARDS-LANDSCAPE.md#what-this-page-did-not-assess)
names what is missing on purpose, and you should not read its silence as coverage. Nothing here is
legal advice, and nothing here says that any of it binds your organization -- a clause number
decides that, and applying to your situation is not the same thing as binding you.

**Sorted by who each document makes demands of**, which is the most stable fact about it: status,
trigger and enforcement machinery change constantly, and the audience almost never does. The column
asks whose conduct a document's sentences purport to govern, not whether anything obliges you to
follow them -- that is the trigger column's question, and most of the documents here oblige nobody
on their own. The last section is the one whose documents govern no one's conduct at all: they
define the terms other documents are written in, so it is named for what they are used for instead.
The cut is explained in
[the guide](STANDARDS-LANDSCAPE.md#who-a-document-is-addressed-to). Every item appears in exactly one
table.

---

## What each one issues

Read this column first when somebody asks you for an artifact. Most of the documents on this page
issue nothing at all, and being asked for a certificate that does not exist is the routine case
rather than the unusual one.

| It issues | What that means when somebody asks you for it | Examples below |
|---|---|---|
| **Nothing** | There is no artifact to obtain. Offer what exists: named control correspondences, your own evidence, a written program | Most items here, including every framework and every control catalog |
| **A self-attestation you sign yourself** | The signature is the instrument, and the exposure is yours. Nobody independent looked | The federal attestation form; the defense self-assessment score and annual affirmation |
| **An assessment or examination report** | Usually restricted in use, and there is no pass mark. One carries a licensed firm's opinion; a CUI assessment carries findings only | SOC 2; a CUI assessment run to the published procedures |
| **A third-party certificate from an accredited body** | A certificate for a stated scope. The accreditation is what gives it weight | ISO/IEC 27001; one rung of the defense program |
| **A government program status or certification** | A status recorded and published by the program, for a named offering rather than for a company | FedRAMP, GovRAMP |
| **A conformity mark you affix yourself after your own assessment** | You assess, declare and mark. A third body is involved only for some product classes | The EU Cyber Resilience Act |
| **Identifiers, a score, or a measurement definition** | Data, not a verdict. A measurement definition produces a number only once some tool implements it | CWE, CVE, EPSS, the automated source code measures |

---

## Addressed to a software producer

These describe how software is built and released. One of them binds a producer directly; the rest
arrive only when a customer, a contract or a package ecosystem names them.

### Requirement-shaped items

| What it is | What it issues | What triggers it | Status (checked 2026-08-06) | The check you can run yourself |
|---|---|---|---|---|
| **EU Cyber Resilience Act, Regulation (EU) 2024/2847** | A declaration of conformity and a mark you affix yourself after your own assessment. Some product classes require a notified body. | Placing a product with digital elements on the EU market. The trigger is where the product goes, not who buys it. | In force 2024-12-10. Reporting obligations apply from 2026-09-11, ahead of the rest of it; the main body of obligations from 2027-12-11. | Routinely treated as something a customer asks for. It is a market-access rule you satisfy before you ship, and the owner is engineering and release, not the compliance function. |
| **NIST SP 800-218 v1.1 (SSDF)** | Nothing. No conformance criteria, no levels, no assessment procedure. | A contract clause, an agency assurance policy, or a questionnaire quoting practice identifiers. | Final since 2022-02-03 and not withdrawn. A draft successor, SP 800-218r1 (v1.2), has been open since 2025-12-17 and is not final. | "Map controls to the current SSDF, or to SSDF 1.2." v1.1 of 2022 is the only final version. The publisher's own publications listing shows Final against one and Draft against the other. |
| **NIST SP 800-218A (SSDF community profile for AI models)** | Nothing. | Building or fine-tuning generative AI or dual-use foundation models, when a contract names it. | Final 2024-07-26. The executive order that commissioned it was revoked 2025-01-20; the publication itself stands. | Its declared scope is producing AI models. Its single sentence on assisted code says the practices do not distinguish it from human-written code, which is a scoping exclusion rather than guidance. Search the publication for that sentence -- it is the whole of the coverage. |
| **CISA Secure Software Development Attestation Form** | A self-attestation signed by an executive, or, on an alternative route the form itself permits, a third-party assessment attached in place of the signature. Not a certificate and not an audit. | An individual agency's contract term or request. | Still published, with clearance to 2027-03-31. Optional for agencies since the memoranda requiring it were rescinded on 2026-01-23. | "Sign the federal attestation form to sell software to the US government." The memoranda requiring agencies to collect it were rescinded on 2026-01-23. Agencies may still ask; none must. Read the rescinding memorandum at the publisher, then read your own contract's clauses. |
| **OWASP ASVS 5.0.0** | Nothing. Its own assessment chapter states that OWASP certifies no vendor or software. | A customer contract or questionnaire naming a verification level. | Released 2025-05-30, superseding 4.0.3 of 2021-10-28. Identifiers were reorganized rather than carried across. | Cited as though a level could be certified. Identifiers from the prior edition do not carry across either, so a policy quoting an old identifier resolves to something different or to nothing. |
| **SLSA v1.2** | Nothing. Machine-readable provenance the consumer verifies. There is no register of levels. | A customer or a package ecosystem asking for build provenance. | Approved 2025-11-12, released 2025-11-24. It restored a Source track with four levels; there is still no Build L4. | "Require SLSA Level 4." There is no Build L4. Since v1.2 there is a Source L4, so a bare level number no longer identifies a requirement. Read the specification's own track pages and write the track beside the level. |
| **CISA 2026 Minimum Elements for an SBOM** | Nothing. It defines fields, states that it creates no new requirements, and places accuracy, coverage and completeness out of its own scope. | A contract term requiring an SBOM. In US federal contracting that is now each agency's own choice. | Published 2026-07-29, replacing the minimum elements of 2021-07-12. | "Generate SBOMs to the NTIA 2021 minimum elements." Those were replaced on 2026-07-29. Separately, a conforming SBOM can still be inaccurate and incomplete -- the 2026 elements say so themselves and point at a signature, at binary analysis, and at exploitability advisories as separate mechanisms. |
| **ISO/IEC 5055:2021 and OMG ASCQM 1.1** | Nothing. Defined counts of severe structural weaknesses, once a tool implements them. | An enterprise or supplier contract specifying automated source code measures. | ISO adoption announced 2021-04-07; ASCQM 1.1 formal since July 2022. One measure family in two venues, not two obligations. | Read as two separate requirements because it appears under two publisher names. |
| **in-toto attestations and Sigstore signing** | Sigstore issues identity-bound short-lived certificates plus a public transparency log entry. These evidence who signed and when, and nothing about what was signed. Its public instances are community-operated with no service level. | A provenance or signing requirement from a customer or a package ecosystem. | No separate status is recorded here beyond the facts in this row. | Offered as a choice against build provenance. Provenance is written as an in-toto attestation, so the two are layered rather than rival options; a requirements document offering a choice between them was written by someone who had not read either. |

**The federal attestation chain, because the cell cannot carry it.** EO 14028 (2021) directed the
guidance. OMB M-22-18 and M-23-16 turned it into a collection requirement. EO 14144 in January 2025
would have added submission to a repository, central verification and referral of failures, and EO
14306 struck that apparatus on 2025-06-06. OMB M-26-05 then rescinded the collection mandate itself
on 2026-01-23. Anyone describing a single January 2026 event has lost the fact that the verification
model was already gone in mid-2025. The status of the federal repository that received submissions is
unknown as of the check date: not reported running, not reported gone.

Component inventory and build provenance as controls -- rather than as any named framework -- are
covered in [Dependency integrity](DEPENDENCY-INTEGRITY.md), which names no baseline and claims
correspondence with none.

### Rankings and awareness lists

**A ranking has no completion condition and cannot be discharged as written.** A clause requiring
software to be free of the issues in an ordered list of categories never says when verification is
finished, so a program scoped that way finishes when the scanner stops printing. A requirement set is
verifiable item by item and has a defensible done. Convert a ranking clause into a requirement-set
clause **while the clause is being agreed**: by assessment time the only remaining options are to
argue or to over-deliver. That conversation is the cheapest thing on this page.

| What it is | What it issues | What triggers it | Status (checked 2026-08-06) | The check you can run yourself |
|---|---|---|---|---|
| **OWASP Top 10:2025** | Nothing. OWASP calls it an awareness document. | A contract clause or questionnaire saying a product was tested against it, and scanner report headings. | The 2025 edition is current on the project's own page, which stamps no final publication date. A release candidate in November 2025 and finalization in January 2026, per secondary coverage. Two categories are new, and an older category was absorbed into another. | A ranking has no completion condition and cannot be discharged as written. Convert it into a requirement-set clause while the clause is being agreed; by assessment time the only remaining options are to argue or to over-deliver. |
| **OWASP Top 10 for LLM Applications, 2026 edition** | Nothing. | An AI feature review, a customer AI questionnaire, or an internal policy naming it. | Dated 2026-08-03 on the project's own resource page, with press coverage on 2026-08-04. The prior edition dates from 2024-11-18. | Offered as governance for what an AI coding assistant writes for you. It addresses securing an application that calls a language model at run time, which is a different subject, and the two are conflated constantly. |
| **CWE Top 25, 2025 edition** | Nothing. | A policy or questionnaire naming it, and occasionally procurement language asking for coverage. | 2025 edition announced 2025-12-11, project page updated 2026-01-29. Any reference to a 2026 edition is unconfirmed. | Same completion-condition problem as any ranking: it cannot be discharged as written. |

---

## Addressed to an organization, not a product

None of these certifies a product, and all of them are routinely offered as product evidence. Where
one applies to a software producer, it arrives through a contract rather than through the regime.
Why that distinction is the most useful sentence on the whole subject is in
[the guide](STANDARDS-LANDSCAPE.md#the-organization-layer-is-not-the-software-layer).

### Certification and program regimes

| What it is | What it issues | What triggers it | Status (checked 2026-08-06) | The check you can run yourself |
|---|---|---|---|---|
| **ISO/IEC 27001:2022 (plus Amendment 1:2024)** | A third-party certificate from a certification body, for a stated scope. ISO itself issues nothing. | A customer or procurement requirement, most often in vendor onboarding. | Published 2022-10; Amendment 1 published 2024-02-23. The 2013-edition transition ended 2025-10-31, per secondary reporting. | Read the scope statement on the certificate. A certificate whose scope covers one office or one business unit is common, and is not what the reader assumes. Called "the international SOC 2" universally, and it is a different instrument with a different failure mode: SOC 2 gives you an opinion plus exceptions, this gives you a certificate plus a scope statement. |
| **ISO/IEC 27002:2022** | Nothing. It explains how to implement the controls the certifiable standard lists. | No independent trigger. It arrives beside a certification program, or in error on a questionnaire. | Published 2022-02. It received a climate-related amendment in the same 2024 cycle; the designation was not confirmed. | Named on a questionnaire as though a supplier could be certified or attest to it. Conformance to a guide is not a thing that exists. |
| **SOC 2 (Type 1 and Type 2)** | An examination report carrying a licensed firm's opinion. Restricted use, no pass mark, no certificate. | A customer questionnaire or contract clause, overwhelmingly in US business-to-business sales. | Criteria are the 2017 Trust Services Criteria with 2022 revised points of focus, posted 2023-09-30. The governing attestation standard applies to reports dated on or after 2022-06-15. | Read the scope statement and the listed exceptions. A report with no exceptions over twelve months is unusual enough to be worth asking about, and the cover page tells you nothing. Type 2 covers operating effectiveness over a period, typically six to twelve months; Type 1 is a point-in-time design opinion only. If what you sell is distributed software rather than a hosted service, the product can sit entirely outside the report's scope boundary. |
| **HITRUST CSF (e1, i1, r2)** | A validated assessment result for an organization. There is no path by which distributable software is certified; the environment operating it can be. | A customer or procurement requirement naming it. The sources behind this page state no independent trigger, so confirm it in the contract. | Three tiers, and they are not interchangeable: e1 (essentials, one year, foundational controls), i1 (one year, established programs, middle assurance), r2 (highest, tailored and risk-based, for complex environments). The tier detail rests on secondary sources; verify anything more specific than the tier names and the scope-variance point at the publisher. | Which tier, and what was in scope. "We are certified" stated without both tells a reader very little: scope drives control count enormously, and the same highest-tier result can be a few hundred controls for one organization and a few thousand for another. |
| **FedRAMP** | A program certification for a service offering, listed publicly. An agency's own authorization stays a separate decision. | Selling a cloud service to a US federal agency. | Founding 2011 memorandum rescinded 2024-07-25. Phase 3 of the replacement model active since 2026-04. Rev5 intake closes 2027-06-11. | "It is an authorization not a certification, at low, moderate or high, via the JAB or an agency." The program uses certification vocabulary and lettered classes, and the board that granted provisional authorizations no longer does so. Delivering the old correction now makes you the out-of-date party. Read the program's own definitions page. |
| **GovRAMP (formerly StateRAMP)** | A verification status granted by the program office and published on a participants list. | A US state, local, tribal or education procurement requirement, varying by jurisdiction. | Rebranded 2025-02-14. StateRAMP remains the legal entity name, operating as GovRAMP, so both names are legitimately live. | "Ask the supplier for their StateRAMP status." The program has operated under the new name since 2025-02-14 while the old one remains the legal entity name. A search on one name alone stops working. |
| **PCI DSS v4.0.1** | A report or a self-assessment questionnaire, plus a signed attestation. No certificate exists. | An agreement with an acquirer or a brand, arriving through the payment chain rather than a regulator. | v4.0.1 published 2024-06; v4.0 retired 2024-12-31; the future-dated requirements became mandatory 2025-03-31. | "We are working toward 4.0, and the future-dated requirements are still future." v4.0 retired 2024-12-31, leaving v4.0.1, and the future-dated requirements became mandatory 2025-03-31. The body that writes the standard is not the body that sets your validation requirement. |

**The cloud programs assess a service offering you operate**, which is why they sit here rather than
with the producer items even though a software company usually pays for them. One cloud program has
begun leveraging an external framework for its lightest class only, and calls that class transitory:
narrow, and not a shortcut. A discrepancy between one cloud program's claim of recognition by another
and that other program's own published outcome is left open here rather than resolved -- read both
programs' own notices before repeating either claim.

### Sector and jurisdiction regimes

Six regimes, presented as members of a set. None gets a worked example, and the operational
vocabulary of each is deliberately absent.

| What it is | What it issues | What triggers it | Status (checked 2026-08-06) | The check you can run yourself |
|---|---|---|---|---|
| **HIPAA Security Rule (45 CFR Part 164 Subpart C)** | Nothing. The enforcing agency has stated since 2003 that it recognizes no certification. | Being a covered organization, or an agreement flowing the obligation down a contract chain. | In force, operative text unchanged. A proposed overhaul published 2025-01-06 is not final; the projected final action has moved to July 2027, per secondary reporting. | Suppliers are asked to produce a certificate against it. None exists, and the enforcing agency has said so for over twenty years. It also binds an organization, not a product. |
| **FTC Safeguards Rule under GLBA (16 CFR Part 314)** | Nothing. A written program, a named accountable individual, and a reporting duty. | Meeting the rule's statutory definition of a covered institution, which is wider than self-image. | Substantive requirements fully effective 2023-06-09. The breach-reporting amendment became effective 2024-05-13. | Organizations that do not think of themselves as financial institutions assume it does not apply to them. The definition is statutory, not a matter of self-description. |
| **FERPA (20 U.S.C. 1232g; 34 CFR Part 99)** | Nothing. No certificate, no assessor, no registry. Enforcement runs through federal funding. | Receiving the covered federal funds, or a contract with an institution that does. | Statute in force since 1974; the regulations were substantially amended in 2008. No status change in the last 24 months. | Sought as a compliance artifact. There is no assessor and no registry to be listed in. |
| **CJIS Security Policy** | No central certificate. An audit by the relevant authority, with the finding landing on the agency. | An agreement giving access to the covered data. The policy names contractors within its own scope. | v6.0 issued 2024-12-27, v6.1 dated 2026-06-25. Secondary reporting says audits continue against an earlier version; confirm with the auditing authority. | A central certificate is assumed to exist, and the version being audited is assumed to be the newest published one. Confirm the audit baseline with the authority that will actually audit, on the date it will happen. |
| **NIS2 Directive ((EU) 2022/2555)** | Nothing at EU level. Obligations, deadlines and penalties come from a member state's transposing law. | Sector plus size thresholds under national law, which has to be tested per member state. | Transposition was due 2024-10-17 and remains incomplete. The Commission referred four member states to the Court of Justice in 2026. | Read as a single EU-wide obligation with one set of thresholds. It is national law that binds, and transposition is incomplete, so the answer differs by member state and in some cases does not exist yet. |
| **SEC cybersecurity disclosure rules (17 CFR Parts 229, 232, 239, 240, 249)** | Nothing. The output is a filing. No assessor and no examination. | Being a registrant of the relevant class. Nothing about your stack changes the answer. | Adopted 2023-07-26, effective 2023-09-05. A rescission petition was filed 2025-05-22; no adopting release was found as of the check date. | Treated as a security control requirement that engineering choices can satisfy or avoid. It is a disclosure duty attached to registrant status. Nothing asked here establishes that status, so this is a fact about your organization to go and check, never an inference drawn from your answers. |

**A resource guide to a rule is not the rule.** Several of the regimes above have a publisher's
implementation guide sitting beside them, and the two get cited identically. A guide states no
requirement and issues nothing, so conformance to one is not a thing that exists, and a questionnaire
asking a supplier to attest to a guide is asking for something no party can supply.

### Control catalogs and operational inputs

The chain worth carrying, because it tells you which document a question belongs to: FIPS 199
categorizes, SP 800-60 Rev. 1 guides the categorizing, FIPS 200 sets a floor, SP 800-53B selects a
baseline, SP 800-53 supplies the control text, and SP 800-53A assesses it. SP 800-122 sits to the
side, covering personally identifiable information (PII). Most questions arrive attached to the
wrong link.

| What it is | What it issues | What triggers it | Status (checked 2026-08-06) | The check you can run yourself |
|---|---|---|---|---|
| **NIST SP 800-53 Rev. 5 (Release 5.2.0), with SP 800-53B and FIPS 199** | Nothing. A baseline is selected and an authorizing official decides. NIST certifies nobody. | A federal contract, a program requirement, or a customer questionnaire mapping its control set onto you. | Release 5.2.0 issued 2025-08-27 and added three controls; the baselines were not changed. FIPS 199 unchanged since February 2004. | Questions arrive attached to the wrong link in the chain. The chain worth carrying: FIPS 199 categorizes, SP 800-60 Rev. 1 guides the categorizing, FIPS 200 sets a floor, SP 800-53B selects a baseline, SP 800-53 supplies the control text, and SP 800-53A assesses it. A release is also not a revision. |
| **NIST SP 800-161 Rev. 1 (upd 1)** | Nothing. Guidance, structured as an overlay on the control catalog. | A federal contract flow-down, or a prime pushing supply chain terms down. | Revision 1 published May 2022; update 1 issued 2024-11-01. No Revision 2 exists in any form, draft or final. | "Revision 2 is out." There is no Revision 2. The 2024-11-01 date people cite is an update to Revision 1, and the publication's own record page shows status and date. |
| **The US defense CUI chain: SP 800-171 as pinned by contract, the CMMC program, the DFARS clauses** | Depends on the rung: a self-scored assessment, an annual affirmation, a third-party certificate, or a government assessment result. | A contracting officer inserting a clause, or a prime flowing it down. Nothing here arrives on its own. | Program rule effective 2024-12-16; acquisition rule effective 2025-11-10; phases beyond the first suspended by policy on 2026-07-13, per secondary reporting. | Two of them. "Defense work has to move to Revision 3": a class deviation issued 2024-05-02 pins the safeguarding clause to Revision 2 and stands until rescinded, per secondary reporting, so the clause text alone gives the wrong revision. And "third-party certification becomes a condition of award in November 2026": Phase 2 and later milestones were suspended by policy on 2026-07-13, per secondary reporting, and neither rule was amended or repealed. Ask the contracting officer which level the solicitation requires, and check the rulemaking index. |
| **CISA Known Exploited Vulnerabilities catalog, and BOD 26-04** | Nothing to a private organization. A directive binds only the agencies it names. | Being an agency a directive names, a contract flowing it down, or your own policy adopting the catalog. | BOD 26-04, issued 2026-06-10, supersedes and revokes the 2021 and 2019 directives. The catalog itself is unchanged. | "Catalog inclusion means a fixed federal patch deadline." The directive setting flat due dates was revoked on 2026-06-10 and replaced by a risk model. The catalog is unchanged, and the revoked directive's own page is titled as revoked. |
| **EPSS** | A daily probability and percentile per published CVE, for exploitation in the wild within thirty days. | A remediation policy that consumes it, or a risk model using exploitation likelihood as an input. | Version 4 deployed 2025-03-17; a version 5 was announced 2026-05-13. Which model generates the published scores was not confirmed. | Read as a verdict rather than as data. Which model version is actually generating the published scores is not confirmed here -- read the comment line in the published data file, not a blog post. |
| **OWASP SAMM v2.0** | Nothing. A self-assessed score from 0 to 3 per practice, plus a community Benchmark for comparison. | Internal program work, board reporting, or a customer asking how mature your program is. | Released February 2020 and still current on the check date. The Benchmark was first published June 2024. | A self-assessed score is offered as though it were an independent finding. |
| **NIST SP 800-122** | Nothing. Guidance. | No independent trigger. It sits beside the federal control chain, covering personally identifiable information (PII). | Still Final. Its withdrawal exists only as intent inside an unfinished working draft. | "SP 800-122 was withdrawn." It is still Final, and the publication's own record page shows status and date. |
| **NIST control overlays for securing AI systems** | Nothing today. | Nothing today. | In development, with no draft overlay published as of the check date, so nothing can be aligned with them today. | Cited in roadmaps as though alignment were possible now. No draft exists to align with. |

**A defense-style obligation begins with a clause number, not a publication.** Ask which
solicitation, which contract and which clause number, and check whether a deviation modifies the
clause. The release-versus-revision trap in the control catalog, with the producer-versus-operator
split that decides who owns a control at all, sits in
[Secure development](SECURE-DEVELOPMENT.md) rather than here.

---

## Addressed to an assessor

Three rows and one lesson: **these change what an audit looks like and impose nothing on the audited
organization.** An unexplained change in audit shape or duration usually starts here rather than in
your auditor's temperament. Reading them as requirements on yourself manufactures controls nothing
ever asked for.

| What it is | What it issues | What triggers it | Status (checked 2026-08-06) | The check you can run yourself |
|---|---|---|---|---|
| **ISO/IEC 27006-1:2024** | Nothing to the audited organization. It governs the auditor. | It affects you through changed audit conduct: refined remote-audit rules and a revised audit-time calculation. | Published 2024, replacing the 2015 edition. One accreditation body required use for all clients by 2026-03-31; other bodies may differ. Ask your own certification body which date applies to it. | Read as a requirement on yourself, which manufactures controls the standard never asked for. An unexplained change in audit shape or duration usually starts here rather than in your auditor's temperament. |
| **NIST SP 800-53A Rev. 5 (Release 5.2.0)** | Nothing to the audited organization. | It affects you as the source of the questions an assessor asks about a deployed instance. | Release 5.2.0 issued 2025-08-27, adding assessment procedures for three controls. | "Addressed to an assessor" does not mean "what an auditor will ask you for". It tells someone how to conduct an examination. Building to it produces controls nothing ever required. |
| **NIST SP 800-171A Rev. 3 and SP 800-172A Rev. 3** | Nothing to the audited organization. A CUI assessment run to these procedures carries findings only, and there is no pass mark. | An assessment somebody else scopes and runs. | 800-171A Rev. 3 final 2024-05-14; 800-172A Rev. 3 final 2026-05-13. The defense program rule still names the June 2018 and March 2022 versions. | The newest published procedure is assumed to be the one being assessed against. The program rule still names earlier versions. |

---

## Input you use, not a rule you meet

You cannot conform to any of these, and knowing that ends several arguments. It does not mean skip
them: a software producer uses every one. A dependency policy is written in vulnerability
identifiers, a scanner reports in weakness identifiers, an SBOM is emitted in one of two formats,
and a requirements document borrows the quality vocabulary. What can put you under an obligation is
the policy, the contract or the vulnerability management program that quotes one of these, never the
document itself -- so use them, and look elsewhere for the demand.

| What it is | What it issues | What triggers it | Status (checked 2026-08-06) | The check you can run yourself |
|---|---|---|---|---|
| **CWE 4.20** | An identifier for a class of mistake. Not a severity and not a priority. | Tool output, vulnerability records that map to it, and contracts asking for findings with mappings. | Version 4.20 released 2026-04-30, on a continuing versioned release cadence. | A weakness identifier is not a severity: it says what kind of mistake a finding is, not whether it matters where you run. |
| **CVE Program** | Identifiers and records. Not severity, not exploitability, not priority. | A dependency policy, a customer contract or support agreement, or your own vulnerability management -- covering both what you consume and what you ship. The program demands nothing itself: what obliges anyone to act on a published identifier is the policy or the clause that quotes it. | Operating. The 2025 contract lapse was averted by an extension, and the program board was told on 2026-01-21 there is no funding cliff in March. Replacement terms are not public. | No published vulnerability identifiers is not a security property: it can equally mean nobody is looking, or that there is no route to publish one. |
| **SBOM formats: SPDX (ISO/IEC 5962:2021) and CycloneDX (ECMA-424, 2nd edition)** | A machine-readable document a parser accepts. No conformance mark exists for either. | A customer or a regime asking for an SBOM in a commonly used machine-readable format. | ISO/IEC 5962:2021 describes SPDX 2.2.1, which current tooling has moved past; SPDX 3.0 sat at draft stage on the check date. ECMA-424 2nd edition was adopted December 2025 and defines CycloneDX v1.7. | "Prefer SPDX because it is the ISO standard." A format's standards-body lineage is not a compliance grade, and the widely quoted ISO number attaches to a 2021-era version rather than to what current tooling emits. Choosing on lineage answers a question nobody in the transaction asked. |
| **ISO/IEC 25010:2023** | A vocabulary of quality characteristics. It states no requirement a product could meet or fail. | Requirements documents and procurement specifications that need both parties to mean the same thing. | Second edition published November 2023, cancelling and replacing the 2011 edition. Usability and portability no longer exist as top-level names. | "Usability is a characteristic." It was replaced in the 2023 edition, so a requirements document written against the 2011 names no longer resolves. |

[Code quality](CODE-QUALITY.md) already cites the current edition of the product quality model for
its own purposes.

---

## What is not primary-verified here

Each row names the check to run instead of trusting this page. One limit covers a whole class and is
stated once rather than repeated per row: several US regulator and agency sites refused automated
requests on the check date, so claims sourced to them were read through search results rather than
end to end.

| What is not primary-verified | What to do instead |
|---|---|
| The audit baseline version and dates for the law-enforcement-data policy, which rest on secondary reporting that disagrees with itself | Confirm with the authority that will actually audit, on the date it will happen |
| The primary text of the July 2026 defense phase suspension, which was not readable | Confirm with the contracting officer before acting on it |
| Whether the class deviation pinning the safeguarding clause to an earlier revision is still standing. It has no stated expiry, but the deviation document itself was not readable | Ask the contracting officer, and check the current consolidated class deviation listing |
| The model version currently generating the published exploit-probability scores | Read the comment line in the published data file, not a blog post |
| The field-level changes in the 2026 SBOM minimum elements | Read the document, which is freely published |
| The ISO catalog entries, and any clause-level ISO content | Nothing to do without buying the text: automated requests are refused and the content is paywalled |
| Whether any rescission of the securities disclosure rules has been adopted since the petition | The publisher's own site refused automated requests, so no page was read end to end. Check the rulemaking index and the adopting-release listing directly |
| The final publication date of the current web application ranking | Read the project's own edition page, which carries the edition as current without stamping a date |
| The audit-transition date for certification bodies, which comes from one accreditation body | Ask your own certification body which date applies to it |
| Whether any agency has issued replacement software assurance terms since the January 2026 rescission | Ask the agency and read the contract. Nobody has consolidated this publicly, and it is where the practical answer now lives |
| The tier detail for the validated-assessment program, which rests on secondary sources | Verify anything more specific than the tier names and the scope-variance point at the publisher |
| The discrepancy between one cloud program's claim of recognition by another and that other program's own published outcome | Left open rather than resolved. Read both programs' own notices before repeating either claim |

**At least these claims rest on secondary analysis rather than a primary source**, each also marked in
its own cell: the suspension of the defense program phases beyond the first; the standing of the class
deviation that pins the safeguarding clause to an earlier revision; the audit baseline for the
law-enforcement-data policy; the certificate transition end date for the 2013 management-system
edition; the projected date for the pending sector-rule overhaul; the finalization date of the current
web application ranking; the tier detail for the validated-assessment program; and the model version
behind the published exploit-probability scores.

Where a claim on this page could not be confirmed at a primary source it is listed above rather than
smoothed over, and the page prefers "at least these" to an enumeration everywhere it can.

---

## Where to re-check a status

A status is authoritative in at least four places, listed with their live examples in
[the guide](STANDARDS-LANDSCAPE.md#sources-and-how-to-re-check-them): the publisher's own
publications listing, the program's own definitions page, the clause plus any deviation that modifies
it, and the data file's own header for a generated score.

**MIT licensed.** Adapt this, put your own name on it, and delete anything you cannot stand behind.
Re-date it when you do: a status claim inherits the date it was checked, not the date it was copied.
