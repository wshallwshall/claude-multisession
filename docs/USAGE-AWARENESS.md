# Usage awareness: knowing when to stop, without lying about it

This document is about a hook that warns a session when the plan pool it bills is running out, and
about why that hook is much harder to get right than it looks. No such hook ships in this repo -- the
mechanism depends on client internals that are undocumented and can change without notice, so
shipping one would be shipping a control that breaks silently. What ships is the design, the failure
modes, and the rules, because those transfer and the code does not.

The lessons here are the sharpest instance in this repo of its recurring theme: **an instrument that
answers a narrower question than the one you asked, while looking completely healthy.**

---

## Why you want this at all

The purpose is **preventing lost work at a hard cutoff**. It is not budgeting.

That distinction decides everything downstream. A budgeting tool wants accuracy and can be wrong
quietly. A lost-work tool wants to fire *before* an agent is mid-refactor with nothing committed, and
must **refuse to report** rather than report wrongly, because the whole point is that somebody acts on
it.

When it fires, the correct response is not "stop". It is:

1. Commit what exists, even if partial. A checkpoint commit beats a clean tree you no longer have.
2. Push branches, or otherwise get the work somewhere that survives the session ending.
3. Write a handoff for whoever picks it up, including yourself in four hours.

## Rule 1: a percentage is meaningless without its account

This is the failure that forced the design.

An early version hardcoded which account to read. It reported **93 percent weekly** into a session
whose actual pool was at **5 percent**. Both the number and the account name were confident, formatted,
and wrong.

> **A hook that is confidently wrong is worse than no hook. It converts "I should check" into
> "I already know."**

And the obvious repair is not a repair. Pointing the hardcoded value at a different account does not
fix it; it relocates the same lie. A machine with several logins, where the client switches between
them, has no correct constant: any hardcoded account is wrong for every session on the others, and
wrong for all of them after the next switch.

**Resolve the pool per session, from the surface that actually knows which login the session bills.**
If you cannot resolve it, say so.

## Rule 2: several signals look authoritative and are wrong

Each of these was checked and each was wrong for the case it appeared to answer:

| Signal | Why it is wrong |
|---|---|
| The CLI's stored login | It is the *CLI's* login. A desktop session can bill a different account entirely, and did. |
| A cached utilization figure beside it | Wrong account **and** hours stale. Two independent defects in one field. |
| The CLI's credentials file | The CLI again. Same category error. |
| The per-session record on disk | Carries no account field at all, so it cannot answer the question. |
| Token-file modification times | They track whichever account the tool last polled, so they point at its own most recent behavior. **A signal derived from your own tool's activity is a mirror, not a measurement.** |

That last row is the general one. If your evidence for "which account is this" is a side effect of
your own polling, you have built a loop that confirms whatever it did last.

## Rule 3: cross-check against an independent sample, and refuse when they disagree

The reading is checked against a second, independently maintained sample for the same organization.
If the two disagree, the result is **UNKNOWN**, not the number.

Two design details matter more than they look:

- **Check the slow-moving figure, not the fast one.** The weekly percentage moves by single points per
  hour. The short-window figure does not: it drops to near zero the instant its window rolls, and was
  observed going from 22 percent to 2 percent across a single sample. Cross-checking on the fast
  figure would produce constant false disagreement; cross-checking on the slow one catches a
  wrong-account reading by construction. The original bug -- one account's 93 against the other's 5 --
  would have been caught on the first run.
- **Sample age is a validity condition.** Past a few missed sampling intervals, the second source is
  no longer evidence. Old enough, and it must stop being treated as a check at all.

## Rule 4: never print a band beside an account unless you established both

An UNKNOWN result names the pool by an opaque identifier and says the usage could not be determined.
It never names a login as "this session's" on the strength of a token file.

Half-established results are where confident wrongness comes from. If you know the account but not the
number, say that. If you know a number but not whose it is, that number is unusable -- do not print it
next to a name to make the output look complete.

## Rule 5: the diagnostics are the payload when something fails

A summary filter kept only lines containing the words for the two window names. It silently dropped
every refusal message the underlying tool produced -- which were exactly the sentences explaining
*why* the reading failed -- leaving an UNKNOWN with an empty reason.

**A filter written for the success case will strip the failure case.** When you filter output, check
what a failing run actually prints before deciding what to keep.

## Rule 6: a warning path must not be able to kill itself

Three constraints, each learned:

- **Never block or error a prompt.** Every path exits 0. A usage warning that breaks a session is
  worse than the cutoff it warns about.
- **ASCII output only.** A `UnicodeEncodeError` on print gets swallowed by the never-throw guard, so
  the warning vanishes *exactly when it was needed*. See [TIPS-AND-TRICKS.md](TIPS-AND-TRICKS.md) for
  why this is a general rule and not a style preference.
- **Persist the failure state too, with a short TTL.** An earlier version re-ran a 25-second
  subprocess on every prompt during an upstream outage, inside a hook with a 30-second budget. The
  failure mode of "retry until it works" is a hook that times out forever.

## Rule 7: cache per pool, never in one unlabeled slot

A single shared cache slot lets the first writer in a refresh window define what every later reader
reports, whatever account that reader asked about. Key the cache by pool. An unlabeled cache is an
unlabeled claim.

## Rule 8: a threshold is not a decision

**The one most likely to bite you, and the one two sessions here got wrong on the same day.**

A percentage alone cannot answer "should I stop". **7 percent remaining with 7 minutes until the
window resets is abundant. The same 7 percent with four hours left is scarce.** A rule that fires on
the number alone will pause work that had no reason to pause, and will fail to fire when the number is
comfortable but the reset is far away.

A peer instructed a pause at a threshold, then retracted it after checking the clock: the window was
minutes from resetting, which made the remaining budget effectively unlimited. Their own summary is
the better statement of it:

> The priority was right for a different reason than the one I gave. I conflated a genuine loss risk
> with a usage threshold and used the threshold to justify the priority.

So: **evaluate the number together with its time-to-reset, and say which one drove the decision.**
And note the corollary, which is the same shape as Rule 1: a percentage without its *account* does not
answer the question either. A usage figure needs three things to mean anything -- the number, whose
pool it is, and when the window rolls.

---

## Platform trap worth its own line

On Windows, a directory can be **visible to an interpreter launched by full path and invisible to the
same interpreter launched through an app-execution alias**, because of installer-level AppData
virtualization. A hook that works when you test it by hand can read an empty directory when the client
runs it.

Wire hooks by full interpreter path, and make a missing path report UNKNOWN rather than OK. "I could
not find the data" and "the data says you are fine" must never produce the same output.

## Related

- [TIPS-AND-TRICKS.md](TIPS-AND-TRICKS.md) -- the general form of most of the above
- [HOOKS.md](HOOKS.md) -- fail-open versus fail-closed, and declaring which you chose
- [CASE-STUDY-drift-audit.md](CASE-STUDY-drift-audit.md) -- auditing controls that look installed
