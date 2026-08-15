---
title: "Case study: a claim three verifiers refuted, and the source confirms"
layout: default
---

# Case study: a claim three verifiers refuted, and the source confirms

## TLDR/BLUF

**What this is.** A research pass on 2026-08-15 put 23 claims through 3-vote adversarial refutation
and killed 13. One of the kills was wrong: the primary source confirms the claim verbatim. This is
what that failure costs and how to stop paying it.

**Why you should care.** A false positive gets argued with. A false negative reads as rigour and is
filed as a finding nobody revisits. Not for you if you never fan work out to verifiers.

**How to use it.** The fix is one schema change, in
[Separate refuted from could-not-establish](#separate-refuted-from-could-not-establish). Everything
before that is why the obvious version does not work.

---

## What happened

A pass verified claims about `spec-kit-arch-governance`, a third-party extension. Among them: that
it is compatible with Spec Kit v0.16.x.

Three verifiers, each prompted to refute rather than confirm, killed it `0-3`.

The extension's catalog entry in the Spec Kit repository reads:

```json
"arch-governance": { "version": "1.2.2", "author": "Ash Brener",
                     "requires": { "speckit_version": ">=0.1.0" } }
```

`>=0.1.0` admits every 0.16 release. The claim was true, stated plainly, in a machine-readable file
in the repository the pass was already reading.

---

## Why this kind of error survives review

**A refuted claim looks like the system working.** The pass reported 13 kills out of 23, and a high
kill rate is the evidence people cite that verification is doing something. Nobody audits the
kills, because auditing them means redoing the verification the kills were supposed to replace.

The two error directions are not symmetric:

| | A false positive | A false negative |
|---|---|---|
| How it presents | A claim someone acts on | A claim quietly dropped |
| Who notices | Whoever the claim fails for | Nobody |
| What it looks like | A mistake | Diligence |

The asymmetry is the whole problem. Wrongly surviving claims meet reality. Wrongly killed claims
never do.

---

## The mechanism, and it is in the recommended pattern

The adversarial-verify pattern is usually written with a tie-breaking default, in this shape:

```
Try to refute this finding. Default to refuted=true if you cannot find solid support.
```

That default is load-bearing and it points the wrong way. It converts **"I searched and found
nothing"** into **"this is established false"**, which are different claims about the world.

A verifier that cannot reach a source, hits a rate limit, or searches badly produces the same output
as one that read the source and found it contradicted. Both come back `refuted: true`.

This is [`HS-9`](HOUSE-STYLE.md) applied to a research harness rather than a diagnostic: a result
must not be phrasable as an answer when the tool could not determine one. It is the same rule that
makes a skipped check exit 2 in `bin/ccx-doctor.ps1` rather than pass.

---

## Separate refuted from could-not-establish

The fix is to stop asking verifiers for a boolean.

**Measured on this repository's own runs.** Three verification workflows were run on 2026-08-15, and
each used this verdict schema:

```js
const VERDICT = {
  type: 'object',
  required: ['refuted', 'why'],
  properties: { refuted: { type: 'boolean' }, why: { type: 'string' } },
}
```

A boolean cannot carry "could not tell". A verifier that wanted to report an unreachable source had
no field to report it in, so every such case was recorded as a kill.

The same runs used a three-valued enum in the *establish* phase, which could say
`NO_SOURCE_ADDRESSES_IT`. So the harness could express the distinction where it collected evidence
and threw it away where it judged evidence. Use the enum in both:

```js
verdict: { type: 'string', enum: ['REFUTED', 'SURVIVED', 'COULD_NOT_ESTABLISH'] }
```

Then count only `REFUTED` toward a kill, and report `COULD_NOT_ESTABLISH` separately rather than
folding it into either pile.

The bundled `/deep-research` workflow already does a narrow version of this. It lists a claim as
unverified rather than refuted when a verifier hits a rate limit or an API error. The gap is the
case where the verifier ran fine and found nothing.

---

## What to do with a kill list you already have

**Do not treat a refuted list as established fact.** That is the operational consequence, and it
applies to any pass whose verdicts were booleans, including every one this repository has run.

Three checks worth spending, in descending order of yield:

- **Re-read the primary source for any kill that would change a decision.** The wrong kill here was
  a semver range in a JSON file, which takes seconds to check and was never checked because the
  vote looked decisive.
- **Distrust unanimous kills on mechanical claims most.** A `0-3` on a file path, a version pin or a
  command inventory means three verifiers failed to find something checkable. That is more often a
  retrieval failure than a fact.
- **Trust kills on judgment claims more.** In the same pass, everything mechanically checkable
  survived and everything about promotion criteria and conventions died. That split is credible:
  those claims were killed because nobody has published them, not because a verifier could not
  reach a file.

---

## A second kill, audited, and it failed a different way

The same pass killed `0-3`: *"adrkit keeps ADRs in `docs/adr/NNNN-title.md` with a status lifecycle
and supersession-cycle linting."* Read against that tool's own README on 2026-08-15:

| Conjunct | What the source says |
|---|---|
| Defaults to `docs/adr` | True. `ADRKIT_DIR` defaults to `docs/adr` |
| Names files `NNNN-title.md` | Unstated. No naming convention documented |
| Status lifecycle, supersession linting | Not described anywhere |

So the verdict was defensible and the claim still lost a true fact. **A compound claim is only as
verifiable as its weakest conjunct**, and one boolean discards the parts that held.

This is the failure the arch-governance kill does not cover, and it needs a different fix. Split a
claim into atomic assertions before verifying, so a verifier can reject the unsupported half without
taking the confirmed one with it.

Both failures share a cause. A verdict field narrower than the thing being judged forces a verifier
to round its answer, and the rounding always goes the same way.

## The narrower lesson

Adversarial verification is still worth running. This pass killed 12 claims that deserved it, and
the material that survived is stronger for the pass having happened.

What it cannot do is tell you which pile a claim landed in *because of the evidence* rather than
because of the tie-break. That is a property of the schema, not of the verifiers, and it costs one
enum to fix.
