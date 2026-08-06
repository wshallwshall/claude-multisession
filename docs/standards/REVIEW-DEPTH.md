# How much of AI-generated code does a human have to read?

**The question every engineering manager asks once an AI coding assistant starts writing most of the
code, and the one where a wrong answer is expensive in both directions.**

> **Take a copy:**
> [markdown](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/REVIEW-DEPTH.md)
> or [Word document](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/standards/word/REVIEW-DEPTH.docx).
> [Every file, both formats](OVERVIEW.md#the-files).

---

## What you get

- **An answer that is not a percentage.** "Review 30 percent of AI-generated code" cannot be
  defended, audited, or complied with. What replaces it is a rule that decides depth per change, in
  one question, and gives the same answer to two different reviewers.
- **A defensible line to hold when someone asks to skip review** because the output looks finished.
  The rule does not care how finished it looks.
- **Two conditions that force a full line-by-line read regardless of tier**, so the hardest cases
  cannot be argued down.
- **A floor that survives every other dial being turned down**, stated in one sentence a whole
  organization can remember.
- **Questions to ask a team**, with what a good answer sounds like, so you can tell a real practice
  from a described one without reading the code yourself.

## What this costs you, and where it does not apply

- **It focuses your effort rather than reducing it.** Deciding the tier takes judgment at the start
  of each change, and that judgment is not free. What you get back is a deep read that lands only
  where it earns its cost, instead of attention spread evenly over code that does not need it.
- **It assumes you can tell what a change touches.** If your system has no clear boundary around
  restricted data or authorization, the rule clamps everything to the strictest tier, and that is
  expensive. Fixing the boundary is the cheaper project.
- **It confers no certification.** Following it is not an attestation, and no outside body issues
  one for it.
- **It is written for a small team, including a solo maintainer with no second reviewer.** Larger
  organizations should read the tier as a floor and add their own review policy on top.

---

## The wrong answers, first

Three answers circulate, and all three fail for the same reason: they are not decidable per change.

| Answer | Why it fails |
|---|---|
| **"A fixed percentage."** | Nobody can say which 30 percent, so in practice it means the easy 30 percent. It is also unauditable: no evidence distinguishes a project that did it from one that says it did. |
| **"All of it, unaided."** | The strongest possible guard, and the reason it fails is not laziness. A rule that is ignored under deadline pressure protects nothing, and this one is ignored first. |
| **"None, the tests cover it."** | Tests check what somebody thought to check. They do not tell you whether the code does something else as well, and an AI coding assistant is good at producing code that passes the test it was shown. |

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

1. **A security-critical seam you must fully own** -- authentication, authorization, cryptography, a
   network bind guard. Read every line by hand. Not because the AI coding assistant is unreliable here, but
   because this is the code you will have to defend later, in a room, from memory.
2. **Anything you cannot yet verify** -- no test you trust, no spec you can check it against. Depth
   substitutes for verification when verification is missing. Write the test instead if you can;
   read every line if you cannot.

---

## The floor: reject code you cannot explain

Below every tier sits one rule that never turns off:

> **Reject code you cannot explain, even if it works.**

This is the line between an AI coding assistant accelerating a team and an AI coding assistant quietly
filling a codebase with **code of unknown provenance** -- code whose behavior nobody on the team
can account for. The failure it prevents is a documented one: developers who can produce
working-looking code but cannot reason about, fix, or maintain it. You discover this during an
incident, which is the worst possible time.

### Does explaining it *with the AI coding assistant's help* count?

This is the genuinely contested question, and an honest standard should say so rather than pretend
it is settled.

**The position taken here: yes, with guardrails.** An explanation reached with AI assistance
satisfies the floor. The strict reading -- a human understands every line unaided -- is the stronger
anti-provenance guard, but for a small team it is the rule that gets quietly dropped first, and a
dropped rule protects nothing.

The guardrails are what make the looser reading defensible:

- The explanation must be **reached, not assumed**. Being able to ask for one later is not the same
  as having one now.
- It must survive **the next question**. If you cannot answer "what happens when this input is
  empty" without asking again, you have not met the floor.
- It does not apply to the two full-read conditions above. On a security seam, unaided is the bar.
- **Record where you took the looser reading**, so the deviation is visible rather than assumed.

If your organization wants the strict reading, take it. What matters is that the choice is written
down and the same for everyone, rather than decided per change by whoever is tired.

---

## What to ask a team, and what a good answer sounds like

You can assess this without reading the code.

| Ask | A good answer | A bad answer |
|---|---|---|
| **How do you decide how deeply to review a change?** | Names a tier and what set it | "Depends on the change" |
| **What forces a full line-by-line read here?** | Names the seams: auth, crypto, bind guards, unverifiable code | "Anything important" |
| **Show me a change that got the deepest review.** | Produces one, with the written intent it was checked against | Cannot find one |
| **What happens when nobody knows if a change touches sensitive data?** | It clamps up, automatically | "We ask around" |
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
- **Write down what "you can explain it" is allowed to mean here.** This document accepts an
  explanation you reached with the tool's help. The stricter alternative is that a person must be
  able to explain the code unaided. Either is defensible; pick one, record which one, and hold
  everyone to it. The failure is not choosing the looser reading -- it is different people applying
  different readings on different days, so nobody can say what the rule actually is.

## Related

| For | Read |
|---|---|
| The wider control set for AI-assisted work | [AI-assisted development](AI-ASSISTED-DEVELOPMENT.md) |
| Judging the resulting code | [Code quality](CODE-QUALITY.md) |
| Trusting code you did not write at all | [Dependency integrity](DEPENDENCY-INTEGRITY.md) |
| The two-page version for an executive | [The CISO summary](CISO-SUMMARY.md) |
