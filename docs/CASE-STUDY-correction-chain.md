# Case study: a finding that took four passes and two sessions

## TLDR/BLUF

**What this is.** One finding, recorded **2026-08-12**, restated four times across two sessions on one
repository. Three of the four statements were wrong. This is what the sequence licenses and what it
does not.

**Why you should care.** Each session produced a confident, checkable, wrong answer, and each was
wrong in a different direction. Neither reached the correct statement alone. Not for you if you run
one session at a time, where the second reading never happens.

**How to use it.** The actionable rule is one sentence, in [what to do with
this](#what-to-do-with-this). Everything above it is the evidence for that sentence.

---

The finding concerned a repository's always-loaded conventions file, and whether any automated check
read it. The subject does not matter. The sequence does.

## The four statements

| Pass | Session | The claim | Verdict |
|---|---|---|---|
| 1 | A | A docs-only pull request skips the suite, so any gate protecting the file would not run | Wrong |
| 2 | B | Nothing reads the file at all: 76 test files mention it, zero read it | Wrong |
| 3 | A | Two guards read it, both are allowlisted, both run, and neither checks content | Correct |
| 4 | Joint | The defect is that the allowlist is an enumeration, so a check landed outside it goes green by absence | Correct, narrower |

Passes 2 and 3 each contradicted their predecessor. Pass 4 did not: it narrowed a pass already marked
correct.

**Both sessions were about to file. Both are wrong.** Session A would have filed "unguarded". Session
B would have filed "no reader exists". A reviewer refutes either by opening one test file.

## What moved each pass

Every pass was moved by running a command. No pass was moved by re-reading, by reasoning about the
file, or by a session reconsidering its own claim.

Pass 2 is the instructive one. It came from a grep requiring the filename and a read verb on one
line. The one true positive builds the path on one line and reads it later through a variable, so the
filter could not match it.

An empty result read as "no such code exists". The instrument was structurally incapable of seeing
the case it was searching for, and it reported that as an absence.

## What the sequence does not establish

| Not established | Why |
|---|---|
| A rate | One finding is one finding. Nothing here says how often a first statement is wrong |
| That two sessions are better than one reader | The comparison was never run. A single session that re-measured might have reached pass 3 |
| That the channel caused it | How the corrections travelled between sessions was not measured |
| That the correct statement is final | Passes 3 and 4 are verdicts as of the date above, and nothing here re-establishes them |

## The errors were all one shape

Recorded the same day, across the same two sessions: two false zeros came from commands that failed
rather than scanned. A separate error tested one regex of a three-rule precedence chain and reported
the result as the chain's behaviour.

A further error reported a breakdown whose eight figures summed to 1202, from a tool whose own output
read `found 646 section citations`. Written up under
[reconcile the parts against the total](TIPS-AND-TRICKS.md#reconcile-the-parts-against-the-total-the-tool-already-printed).

Every one was a number from an instrument nobody had validated, and in each case a positive control
was available and free.

## What to do with this

**Treat a single session's finding as a hypothesis until a second session runs the command.**

That is cheap where sessions already exist and costs one message. It is not a claim that peer review
finds everything, and it does not replace the mechanical checks in
[when you write a guardrail](TIPS-AND-TRICKS.md).

The corollary is the one that saved this finding: **enumerate from the callee.** Asking "which files
does this guard read" opens one file and answers it. Asking "does anything read this file" needs a
filter over every caller, and that is the filter that failed.
