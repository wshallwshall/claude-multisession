# Usage awareness: Knowing when to stop, without lying about it

## TLDR/BLUF

**What this is.** Eight rules for a hook that warns a session when the plan pool it bills is running
out. They cover what it must resolve, what it must refuse to say, and the failure behind each one.

**Why you should care.** Each rule came from **an instrument that answered a narrower question than
the one you asked, while looking completely healthy.** Not for you if you want something to install:
**no hook ships here**, because it would break silently on internals that change.

**How to use it.** Take the rules, not the implementation -- those transfer and the code does not.
Start at [Why you want this at all](#why-you-want-this-at-all): the purpose decides the rules below.

---

## Why you want this at all

The purpose is **preventing lost work at a hard cutoff**. It is not budgeting. That decides
everything downstream.

A budgeting tool wants accuracy and can be wrong quietly. A lost-work tool has to fire *before* an
agent is mid-refactor with nothing committed. It must **refuse to report** rather than report
wrongly, because the point is that somebody acts on it.

When it fires, the correct response is not "stop". It is:

1. Commit what exists, even if partial. A checkpoint commit beats a clean tree you no longer have.
2. Push branches, or otherwise get the work somewhere that survives the session ending.
3. Write a handoff for whoever picks it up, including yourself in four hours.

## Rule 1: A percentage is meaningless without its account

This is the failure that forced the design. An early version hardcoded which account to read. It
reported **93 percent weekly** into a session whose actual pool was at **5 percent**. Both the
number and the account name were confident, formatted, and wrong.

> **A hook that is confidently wrong is worse than no hook. It converts "I should check" into
> "I already know."**

Pointing the hardcoded value at a different account relocates the same lie. A machine with several
logins the client switches between has no correct constant. Any hardcoded account is wrong for every
session on the others, and wrong for all of them after the next switch.

**Resolve the pool per session, from the config root that session runs under.** Each login owns a
root, and the account is in that path rather than in any record
([Desktop accounts](DESKTOP-ACCOUNTS.md)). If you cannot resolve it, say so.

## Rule 2: Several signals look authoritative and are wrong

Each of these was checked and each was wrong for the case it appeared to answer:

| Signal | Why it is wrong |
|---|---|
| The CLI's stored login | It is the *CLI's* login. A desktop session can bill a different account entirely, and did. |
| A cached utilization figure beside it | Wrong account **and** hours stale. Two independent defects in one field. |
| The CLI's credentials file | The CLI again. Same category error. |
| The per-session liveness record on disk (pid, start time, session id, cwd) | Carries no account field, so the file's *contents* name no login. Its path does ([Token accounting](TOKEN-ACCOUNTING.md)). |
| Token-file modification times | They track whichever account the tool last polled, so they point at its own most recent behavior. **A signal derived from your own tool's activity is a mirror, not a measurement.** |

**That last row is the general one.** If your evidence for "which account is this" is a side effect
of your own polling, you have built a loop that confirms whatever it did last.

## Rule 3: Cross-check against an independent sample, and refuse when they disagree

The reading is checked against a second, independently maintained sample for the same organization.
If the two disagree, the result is **UNKNOWN**, not the number.

Two design details matter more than they look:

- **Check the slow-moving figure, not the fast one.** The short-window figure drops to near zero
  when its window rolls -- 22 percent to 2 percent in one sample -- so it disagrees constantly. The
  weekly one moves single points per hour, and would have caught the 93-against-5 bug on its first
  run.
- **Sample age is a validity condition.** Past a few missed sampling intervals the second source is
  no longer evidence, and the result is **UNKNOWN** with staleness as the reason. It never falls
  back to the unchecked number, which would look exactly like a passed check.

## Rule 4: Never print a band beside an account unless you established all three

An UNKNOWN result names the pool by an opaque identifier and says the usage could not be determined.
It never names a login as "this session's" on the strength of a token file.

Half-established results are where confident wrongness comes from. If you know the account but not
the number, say that. If you know a number but not whose it is, that number is unusable. Do not
print it next to a name to make the output look complete.

If you know the account and the number but not when the window rolls, print both and say the reset
time is unknown. Rule 8 cannot be decided without it, and output that omits it reads as a decision
already made.

## Rule 5: The diagnostics are the payload when something fails

A summary filter kept only lines containing the words for the two window names. It silently dropped
every refusal message the underlying tool produced -- exactly the sentences explaining *why* the
reading failed -- leaving an UNKNOWN with an empty reason.

**A filter written for the success case will strip the failure case.** When you filter output, check
what a failing run actually prints before deciding what to keep.

## Rule 6: A warning path must not be able to kill itself

Three constraints, each learned:

- **Never block or error a prompt.** Every path exits 0. A usage warning that breaks a session is
  worse than the cutoff it warns about.
- **ASCII output only.** A `UnicodeEncodeError` on print gets swallowed by the never-throw guard, so
  the warning vanishes *exactly when it was needed*. See [TIPS-AND-TRICKS.md](TIPS-AND-TRICKS.md) for
  why this is a general rule and not a style preference.
- **Persist the failure state too, with a short TTL.** An earlier version re-ran a 25-second
  subprocess on every prompt during an upstream outage, inside a hook with a 30-second budget. The
  failure mode of "retry until it works" is a hook that times out forever.

## Rule 7: Cache per pool, never in one unlabeled slot

A single shared cache slot lets the first writer in a refresh window define what every later reader
reports, whatever account that reader asked about. **Key the cache by pool.** An unlabeled cache is
an unlabeled claim.

## Rule 8: A threshold is not a decision

**The one most likely to bite you, and the one a session here got wrong by pausing work on the
number alone.**

A percentage alone cannot answer "should I stop". **7 percent remaining with 7 minutes to reset is
abundant. The same 7 percent remaining with four hours left is scarce.**

A rule that fires on the number alone pauses work for no reason, and stays quiet when the number
looks comfortable but the reset is far away. Note the polarity: every other figure on this page is
percent *consumed*, and these two are not.

A peer instructed a pause at a threshold, then retracted it after checking the clock: the window was
minutes from resetting, which made the remaining budget effectively unlimited. Their own summary is
the better statement of it:

> The priority was right for a different reason than the one I gave. I conflated a genuine loss risk
> with a usage threshold and used the threshold to justify the priority.

So: **evaluate the number together with its time-to-reset, and say which one drove the decision.**
The corollary has Rule 1's shape: a usage figure needs three things to mean anything -- the number,
whose pool it is, and when the window rolls.

---

## On Windows, one interpreter can see a directory that another cannot

On Windows, a directory can be **visible to an interpreter launched by full path and invisible to
the same interpreter launched through an app-execution alias**. The cause is installer-level AppData
virtualization. A hook that works by hand can read an empty directory when the client runs it.

Wire hooks by full interpreter path, and treat a directory that is **present but empty** exactly
like a missing one -- both report UNKNOWN. Virtualization substitutes the contents and leaves the
path, so a check for existence alone passes while reading nothing.

"I could not find the data" and "the data says you are fine" must never produce the same output.

## Related

- [TIPS-AND-TRICKS.md](TIPS-AND-TRICKS.md) -- the general form of most of the above
- [HOOKS.md](HOOKS.md) -- fail-open versus fail-closed, and declaring which you chose
- [CASE-STUDY-drift-audit.md](CASE-STUDY-drift-audit.md) -- auditing controls that look installed
- [TOKEN-ACCOUNTING.md](TOKEN-ACCOUNTING.md) -- what a weekly percentage counts, measured on four accounts
- [DESKTOP-ACCOUNTS.md](DESKTOP-ACCOUNTS.md) -- one config root per account, and how to read which one a session is on
