---
title: "Case study: A claim three verifiers refuted, and the source confirms"
layout: default
---

# Case study: A claim three verifiers refuted, and the source confirms

## TLDR/BLUF

**What this is.** On 2026-08-15 a research pass sent 23 claims to three verifiers each, every
verifier told to disprove rather than confirm. It killed 13. One kill was wrong: the primary source
states the claim verbatim, in a file in the repository the pass was already reading.

**Why you should care.** A wrong claim that survives gets argued with. A true claim wrongly killed
reads as rigour and is filed as a finding nobody reopens. Not for you if you never fan work out to
verifiers.

**How to use it.** The fix is one schema change. It is in
[Separate refuted from could-not-establish](#separate-refuted-from-could-not-establish). Everything
above that section is why the obvious version does not work.

---

## What happened

A pass verified claims about `spec-kit-arch-governance`, a third-party extension. Among them: that
it is compatible with Spec Kit v0.16.x.

Three verifiers read that claim, each prompted to refute rather than confirm. All three voted to
kill it. The pass recorded the vote as `0-3`: no votes for the claim, three against.

The extension's catalog entry in the Spec Kit repository reads:

```json
"arch-governance": { "version": "1.2.2", "author": "Ash Brener",
                     "requires": { "speckit_version": ">=0.1.0" } }
```

`>=0.1.0` admits every 0.16 release. **The claim was true**, stated plainly, in a machine-readable
file in the repository the pass was already reading.

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

Four verifiers produce the same output, and only one of them has refuted anything:

- it could not reach the source
- it hit a rate limit
- it searched badly and found nothing
- it read the source, and the source contradicted the claim

All four come back `refuted: true`.

This is [`HS-9`](HOUSE-STYLE.md) applied to a research harness rather than a diagnostic: a result
must not be phrasable as an answer when the tool could not determine one. It is the same rule that
makes a skipped check exit 2 in `bin/ccx-doctor.ps1` rather than pass.

---

## Separate refuted from could-not-establish

**The goal.** A verdict that can say "could not tell" out loud, so a retrieval failure never lands
in the kill pile. That means one thing: stop asking verifiers for a boolean.

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
`NO_SOURCE_ADDRESSES_IT`. The harness could express the distinction where it collected evidence, and
threw it away where it judged evidence.

**What to do.** Use that enum in the verdict phase too:

```js
verdict: { type: 'string', enum: ['REFUTED', 'SURVIVED', 'COULD_NOT_ESTABLISH'] }
```

**What happens next.** Only `REFUTED` counts toward a kill. `COULD_NOT_ESTABLISH` is reported as its
own pile rather than folded into either of the others, so a kill list now holds only claims a
verifier argued down.

The bundled `/deep-research` workflow already does a narrow version of this. It lists a claim as
unverified rather than refuted when a verifier hits a rate limit or an API error. The gap is the
case where the verifier ran fine and found nothing.

---

## What to do with a kill list you already have

**The goal.** Find the wrong kills in a list you have already filed, without rerunning the pass.

**Do not treat a refuted list as established fact.** That applies to any pass whose verdicts were
booleans, including every one this repository has run.

**What to do.** Three checks, in descending order of yield:

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

**What happens next.** Expect a mechanical kill to be the cheapest to recheck, and expect some of
them to come back. Auditing the kill below took one read of a README, and that verdict held.

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

**A different fix, for a failure the arch-governance kill does not cover.** Split a claim into
atomic assertions before verifying. A verifier can then reject the unsupported half without taking
the confirmed one with it.

Both failures share a cause. A verdict field narrower than the thing being judged forces a verifier
to round its answer, and the rounding always goes the same way.

---

## The narrower lesson

Adversarial verification is still worth running. This pass killed 12 claims that deserved it, and
the material that survived is stronger for the pass having happened.

What it cannot do is tell you which pile a claim landed in *because of the evidence* rather than
because of the tie-break. That is a property of the schema, not of the verifiers, and it costs one
enum to fix.
