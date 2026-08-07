# How much of AI-generated code does a human have to read?

**The question every engineering manager asks once an AI coding assistant starts writing most of the
code, and the one where a wrong answer is expensive in both directions.**

> **Take a copy:**
> [markdown](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/REVIEW-DEPTH.md)
> or [Word document](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/REVIEW-DEPTH.docx).
> [Every file, both formats](OVERVIEW.md#the-files).

---

## TLDR/BLUF

**Every answer that fails here is a quantity -- some share of the code a human reads.** A percentage
cannot be assigned to the change in front of you, so "review 30 percent" means the easy 30 percent,
and no evidence separates a team that did it from one that says it did. Depth is not a share of the
code to divide up. It is a decision, taken per change, before the code exists.

So resolve every change to a tier before work starts, and do three things:

1. **Ask what the change touches.** Restricted data, an authorization path, or something a customer
   depends on? Unknown counts as yes, and so does not knowing whether the change reaches beyond the
   local machine. That answer sets the tier -- *Exploratory*, *Guarded*, *Governed* or *Regulated
   release* -- and with it the depth, from a skim on a throwaway to every changed line reconciled
   against a written intent that predates it. It also outranks size: a one-line change to an
   authorization path is not a one-line-change review.
2. **Override the tier on two conditions.** A security seam you have to own -- at least
   authentication, authorization, cryptography, a network bind guard -- and any change you have no
   way to verify. Either one takes every line whatever the tier said.
3. **Hold one floor under all of it.** Reject code you cannot explain, even if it works. This is the
   rule that has to survive every other dial being turned down under deadline pressure, which is
   why it is one sentence.

Each of the three is decidable before the code exists, and two reviewers running them against the
same change get the same answer. **None of it certifies anything** -- this is a bar to set and hold,
not an attestation to present.

---

## What this costs you, and where it does not apply

- **It focuses your effort rather than reducing it.** Deciding the tier takes judgment at the start
  of each change, and that judgment is not free. What you get back is a deep read that lands only
  where it earns its cost. It is not attention spread evenly over code that does not need it.
- **It assumes you can tell what a change touches.** If your system has no clear boundary around
  restricted data or authorization, the rule clamps everything to the strictest tier, and that is
  expensive. Fixing the boundary is the cheaper project.
- **It confers no certification.** Following it is not an attestation, and no outside body issues
  one for it.
- **It is written for a small team, including a solo maintainer with no second reviewer.** Larger
  organizations should read the tier as a floor and add their own review policy on top.

---

## The wrong answers, first

At least three answers circulate, and each fails for a different reason.

| Answer | Why it fails |
|---|---|
| **"A fixed percentage."** | Nobody can say which 30 percent, so in practice it means the easy 30 percent. It is also unauditable: no evidence distinguishes a project that did it from one that says it did. |
| **"All of it, unaided."** | The strongest possible guard, and the reason it fails is not laziness. A rule that is ignored under deadline pressure protects nothing, and this one is ignored first. |
| **"None, the tests cover it."** | Tests check what somebody thought to check. They do not tell you whether the code does something else as well. An AI coding assistant is good at producing code that passes the test it was shown. |

The useful answer is not a quantity at all. It is a **decision procedure**.

---

## Human review depth follows risk and is decided per change

Resolve every change to a tier before work starts. The tier sets how deeply a human reads, along
with which gates and which provenance records are mandatory.

| Tier | Typical change | Human review depth |
|---|---|---|
| **Exploratory** | A spike, a throwaway script, a local experiment that ships nothing | Skim. Confirm it ships nothing and touches no real data |
| **Guarded** | Ordinary feature work on non-sensitive paths | Read the diff. Understand what each hunk does and why |
| **Governed** | Anything on a path that carries or protects restricted data, or that a customer depends on | Read every changed line. Reconcile the change against a written intent that predates it |
| **Regulated release** | What you publish, sign, or hand to an adopter | Every changed line, plus the release contents themselves, against an allowlist |

Two properties make this work, and they are worth stating to whoever asks for an exception:

- **The sensitive-data ratchet dominates.** A change that touches or protects restricted data lands
  at the higher tiers no matter how small it is. Size scales the lower tiers only. A one-line change
  to an authorization path is not a one-line-change review.
- **Unknown clamps up, and fails closed.** If nobody can say whether a change touches restricted
  data, or whether it is exposed beyond the local machine, it resolves to the stricter tier. The
  cheap answer is the strict one, so the incentive to leave the question open is removed.

### Two conditions that force a full read regardless of tier

These are not negotiable by tier, and both come from experience rather than theory:

1. **A security-critical seam you must fully own** -- at least authentication, authorization,
   cryptography, a network bind guard. Read every line by hand. Not because the AI coding assistant
   is unreliable here, but because this is the code you will have to defend later, in a room, from
   memory.
2. **Anything you cannot yet verify** -- no test you trust, no spec you can check it against. Depth
   substitutes for verification when verification is missing. Write the test instead if you can;
   read every line if you cannot.

---

## The floor: reject code you cannot explain

Below every tier sits one rule that never turns off:

> **Reject code you cannot explain, even if it works.**

This is the line between an AI coding assistant that accelerates a team and one that quietly fills
a codebase with **code of unknown provenance**. That is code whose behavior nobody on the team can
account for.

The failure it prevents is a documented one: developers who can produce working-looking code but
cannot reason about, fix, or maintain it. You discover this during an incident, which is the worst
possible time.

### AI-assisted explanation is contested, and accepted here with guardrails

Whether an AI-assisted explanation satisfies the floor is genuinely contested. An honest standard
should say so rather than pretend it is settled.

**The position taken here: yes, with guardrails.** An explanation reached with AI assistance
satisfies the floor. The strict reading -- a human understands every line unaided -- is the stronger
guard against code of unknown provenance. For a small team, though, it is the rule that gets quietly
dropped first, and a dropped rule protects nothing.

The guardrails are what make the looser reading defensible:

- The explanation must be **reached, not assumed**. Being able to ask for one later is not the same
  as having one now.
- It must survive **the next question**. If you cannot answer "what happens when this input is
  empty" without asking again, you have not met the floor.
- It does not apply to the two full-read conditions above. On a security seam, unaided is the bar.
- **Record where you took the looser reading**, so the deviation is visible rather than assumed.

If your organization wants the strict reading, take it.

---

## What to ask a team, and what a good answer sounds like

You can assess this without reading the code.

| Ask | A good answer | A bad answer |
|---|---|---|
| **How do you decide how deeply to review a change?** | Names a tier and what set it | "Depends on the change" |
| **What forces a full line-by-line read here?** | Names the seams: auth, crypto, bind guards, unverifiable code | "Anything important" |
| **Show me a change that got the deepest review.** | Produces one, with the written intent it was checked against | Cannot find one |
| **What happens when nobody knows if a change touches restricted data?** | It clamps up, automatically | "We ask around" |
| **Has anyone rejected code recently for being unexplainable?** | A specific instance | "It has not come up" |

That last one is the tell. A floor nobody has ever hit is either a team that never sees difficult
output, or a floor nobody enforces. It is worth knowing which.

---

## Adapting this to your project

- **Rename the tiers** to whatever your organization already uses. The names do not matter; the
  ratchet and the clamp do.
- **Define "restricted data" for your setting** in one sentence, in your own working agreement.
  Everything above depends on that line being drawn somewhere findable.
- **Do not weaken the two full-read conditions.** They are the part that pays for itself.
- **Write down which reading of "you can explain it" applies here.** Both readings, and the
  guardrails this document puts on the looser one, are under *AI-assisted explanation is contested,
  and accepted here with guardrails* above.

Either reading is defensible. The failure is not choosing the looser one. It is different people
applying different readings on different days, so nobody can say what the rule actually is.

## Related

| For | Read |
|---|---|
| The wider control set for AI-assisted work | [AI-assisted development](AI-ASSISTED-DEVELOPMENT.md) |
| Judging the resulting code | [Code quality](CODE-QUALITY.md) |
| Trusting code you did not write at all | [Dependency integrity](DEPENDENCY-INTEGRITY.md) |
| The two-page version for an executive | [The CISO summary](CISO-SUMMARY.md) |
