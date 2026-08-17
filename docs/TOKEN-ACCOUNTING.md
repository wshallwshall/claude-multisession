# Token accounting: What a usage meter measures, and what a plan buys

## TLDR/BLUF

**What this is.** Four accounts on one subscription tier, measured on 2026-08-12, to answer two
questions. What unit does the weekly usage meter count, and what is a month of it worth at published
per-token API prices?

**Why you should care.** The meter ignores cache reads, so the percentage counts fresh tokens, not
work done and not dollars -- equal meter points bought 21 to 41 USD of list value here. Not for you
if you want a rate card: this is four samples of an undocumented meter, not vendor documentation.

**How to use it.** Take the ratio, not the dollar figures. Roughly 1.35 million non-cache-read
tokens buy 1 percent of a weekly window. That unit transfers between workloads. The dollar value
does not: it depends on how much cached context your sessions re-read.

---

## What was measured

Four Claude Max 20x accounts, each billed at 200 USD per month. All four ran the same kind of work:
long agentic coding sessions against one repository, with large cached contexts.

Each account's tokens were summed from its local session transcripts, which carry a usage block on
every assistant message. Each sum was paired with that account's live weekly percentage, read at the
same moment from the client's own usage endpoint.

| Account | Weekly meter | Tokens in window | Non-cache-read | Raw per 1 percent | Non-cache-read per 1 percent |
|---|---:|---:|---:|---:|---:|
| A | 92 percent | 5,563,746,679 | 139,181,709 | 60,475,507 | 1,512,845 |
| B | 93 percent | 3,666,611,235 | 125,727,276 | 39,425,927 | 1,351,906 |
| C | 37 percent | 1,348,106,117 | 50,279,736 | 36,435,300 | 1,358,912 |
| D | 97 percent | 2,779,391,470 | 102,320,610 | 28,653,520 | 1,054,852 |

Each window is that account's current weekly period, which began between two and six days before the
reading. Three of the four were near their end, so the extrapolation to a full window is short.

## The meter counts non-cache-read tokens

Raw tokens per 1 percent vary by a factor of 2.1 across the four rows, from 28,653,520 to
60,475,507. Non-cache-read tokens per 1 percent vary by only 1.4, and two of the rows agree to
within 0.6 percent: B at 1,351,906 and C at 1,358,912.

**Working estimate: roughly 1.35 million non-cache-read tokens per 1 percent of a weekly window**,
so a full weekly allowance is near 135 million and a month near 590 million.

Cache reads are close to free against the meter. That is a steeper discount than the API's, where a
cache read still costs a tenth of fresh input. At the 27-to-40 cache ratios measured here, a tenth
would have dominated the bill.

Two consequences for anyone reading a percentage:

- **A slow-moving percentage does not mean little happened.** A session re-reading a large cached
  context burns raw tokens at about thirty times the rate it burns metered ones -- forty times in
  the most cache-heavy of the four. The meter barely moves while the context churns.
- **A percentage is a cost signal, not a progress signal.** For progress, count output tokens or
  completed steps.

## What 200 USD per month buys

Each account's window was priced at the published per-token rates for the model it ran: 5 USD per
million input tokens, 25 output, 6.25 cache write, and 0.50 cache read. Each row is then scaled to a
full window, and from there to a month of 4.348 weeks.

| Account | Raw tokens per month | API list value per month | Multiple on 200 USD |
|---|---:|---:|---:|
| A | 26.3 billion | 17,623 USD | 88x |
| B | 17.1 billion | 12,607 USD | 63x |
| C | 15.8 billion | 11,908 USD | 60x |
| D | 12.5 billion | 9,323 USD | 47x |

**The defensible number is B and C at 60x to 63x.** Both outliers have known causes, and neither is
a workload difference the reader can expect to reproduce.

- **A's 88x is cache amplification.** Its raw-to-metered ratio is 40 to 1, against 27 to 29 for the
  other three. It re-read more cached context per unit of new work, and the meter did not charge for
  it.
- **D's 47x is an undercount, not a worse deal.** Its short-window meter showed active use on two
  days when the local transcripts held nothing for it. Some of its spend happened on a surface these
  files do not cover, so its true value is higher by an unmeasured amount.

Per million tokens, the subscription works out near 0.013 USD counting raw tokens, or 0.35 USD
counting only non-cache-read tokens. The same traffic mix at list price is roughly 0.75 USD raw and
21 USD non-cache-read. Both pairs divide to the 60x above, which is the check on it.

## What these numbers are not

| Claim | Limit |
|---|---|
| The metering formula | Unknown. Four observations fitted to the simplest model explaining them |
| The percentages | Integers. At 37 percent the quantisation alone is worth plus or minus 1.4 percent |
| The extrapolation | Assumes the rest of a window resembles the measured part. Row C is a 2.7x extrapolation and is the weakest |
| The dollar figures | A comparison against list price, not a bill. Batch pricing, longer cache lifetimes or a cheaper model all move it |
| The coverage | Local transcripts on one machine only. Row D is the proof that this misses real spend |

**A window's start is not its first use.** Two of the four opened between one and two days before
any token was spent against them. A window boundary cannot be inferred from observed activity.

## Reproducing it

The mechanism is the same one [USAGE-AWARENESS.md](USAGE-AWARENESS.md) describes and declines to
ship: undocumented client internals that can change without notice. Nothing here is packaged.

**The goal.** Pair one account's own token total with that account's own weekly percentage, read at
the same moment.

**What to do.** Read three surfaces -- two local files and one live reading:

1. **Session transcripts.** One JSON line per message, carrying a usage block with four counters:
   input, output, cache write and cache read. Subagent transcripts nest under the parent session, so
   a scan that reads only top-level files misses most of the volume.
2. **The config root the session ran under.** The account is that root's own name, never a field
   inside the per-session record, which carries none
   ([USAGE-AWARENESS.md](USAGE-AWARENESS.md)). Without it every number is a total over an unknown
   mixture of accounts.
3. **The live usage endpoint.** Supplies the percentage *and the window's reset time*, and must be
   gated on an identity lookup so a reading is provably about the account you think it is.

**Bound the window before summing.** A window's start cannot be inferred from activity, so work it
back from the reset time and sum only messages at or after it. A total over the wrong span still
divides into a percentage, and still looks plausible.

**Deduplicate messages by their request identifier before summing.** Retries and streamed messages
otherwise get counted twice.

**What happens next.** You get one row of the table above: a token total, a percentage, and the
ratio between them.

## Related

- [USAGE-AWARENESS.md](USAGE-AWARENESS.md) -- reading a percentage safely, and why a threshold alone is not a decision
- [TIPS-AND-TRICKS.md](TIPS-AND-TRICKS.md) -- the general form of an instrument answering a narrower question than the one asked
- [KORUS.md](KORUS.md) -- why the plan, and why more than one account for a week of heavy work
- [DESKTOP-ACCOUNTS.md](DESKTOP-ACCOUNTS.md) -- running several accounts, one desktop instance each
