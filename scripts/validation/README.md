# What broken looks like

Five instruments that can only fire when the multi-session tooling is misbehaving, and the rule for
what counts as broken. Written before the first run against a real backlog, not after.

```
pwsh -NoProfile -File scripts/validation/run-checks.ps1
pwsh -NoProfile -File scripts/validation/run-checks.ps1 -SelfTestOnly
```

The runner proves every instrument against a planted corpus first. If one fails to fire, it refuses
to measure anything live and exits 3.

## Why this exists

A run where no worker asks a question reads as a smooth run. It is also what a dead message channel
looks like. The two produce the same output, so the quiet run proves nothing on its own.

The same shape covers claims, number allocation, and session cleanup. Each one fails silently. Each
one needs a signal decided in advance, or the run gives you an anecdote instead of a measurement.

## The five signals

| Signal | What it scans | Broken when |
|---|---|---|
| `message-delivery` | every `*.json` under the mail root: messages, and the receipts a drain writes | a message older than the settle window has no receipt naming it |
| `message-expiry` | the same lane, but only messages that declare a ttl | a message passed its send time plus its ttl with no receipt |
| `claim-holders` | every claim file in `<state-root>/claims`, and every session record the fence can see | two claim keys naming one item are held by two LIVE worktrees, or one claim's worktree holds two LIVE sessions |
| `allocation-collisions` | every ref `git for-each-ref` returns, plus the working tree, matched against each sequence's own `filePattern` | one number maps to two or more distinct paths, and the index row does not declare the second as a companion |
| `session-reaping` | every `<config-root>/sessions/*.json` record, and every file under each worktree they place into | a LIVE record's worktree has seen no commit and no file write for over 24 hours |

Each check exits 0 for CLEAN, 1 for BROKEN, and 2 for CANNOT_TELL.

**CANNOT_TELL is not a pass.** It means nothing was examined, so nothing was measured. A check that
found no corpus must never print the line a check prints after looking and finding nothing wrong.

## The two rules the instruments obey

Both were learned the hard way rather than reasoned out.

### Rule 1: run a control that must fire

An instrument validated only against a healthy system cannot tell a clean result from a broken
probe. So every check here ships with two planted corpora, under `fixtures/`.

The broken one must come back BROKEN. The clean one must come back CLEAN. One alone is worth little:
a check wired to always fail passes the first, and a check wired to always pass passes the second.

`run-checks.ps1` runs two control cases per check, both of them, before it looks at your machine.
`tests/test_every_validation_check_is_proven_by_a_control.py` runs them again in the test suite, and
refuses a check that arrives without both fixtures.

### Rule 2: report what you scanned

A count from a pipeline carrying a head, a tail, or a sample cap is not a census. A truncated result
reads as a complete one.

So every receipt prints its corpus size beside its finding, on a clean run as well as a failing one.
Nothing here caps a count. `-MaxReport` bounds how many findings are printed, and the bounded list
says `showing N of M` so it can never read as the whole set.

## The worked example, preserved

This is the sharpest illustration of rule 1 available, and the session that found it has been
archived. It is written down here so nobody has to find it twice.

Measured 2026-08-31 on Claude Code CLI 2.1.251:

```
CLAUDE_CONFIG_DIR='C:\Users\<user>\.claude-DOES-NOT-EXIST' claude agents --json
-> []    exit=0
```

The account name is written `<user>` because the leak gate refuses a real home path, and it carries
no part of the finding.

A nonexistent config root returns an empty list with a success code. No error, no warning. An empty
fleet and a mistyped root are byte-identical.

**How it was found matters as much as the fact.** The measuring session's first loop had a quoting
bug that never interpolated its variable. It passed a literal unexpanded path twice, got two clean
empty answers, and nearly reported them as a real reading. The bad instrument looked exactly like a
working one returning good news.

**The rule that follows.** If this tooling ever adopts `claude agents --json`, the root must be
proven to exist before the call. An empty result from an unproven root is UNKNOWN, not zero sessions.

Note the irony worth recording: the existing hand-rolled root reader already tests each path for
existence, and the built-in does not.

### One correction from the same session

An earlier claim was wrong, so it is corrected here rather than left to be rebuilt on.

`claude agents --json` reads exactly one config root per invocation, and the root is selectable by
the environment variable. A loop over the roots gets full coverage across accounts. The command is
not confined to one root as a tool.

What stays hand-rolled is discovering which roots exist, and the liveness fence.

## What a CANNOT_TELL is telling you

| Check | What it means | What to do |
|---|---|---|
| `message-delivery`, `message-expiry` | there is no mail root, or it holds nothing | the lane is built per machine and ships as a guide, not code. Build it, then send a canary |
| `claim-holders` | nothing has ever claimed in this clone | take one claim, then rerun |
| `allocation-collisions` | no sequences are configured, or no path matches one | check `sequences` in `ccx.config.json` against the paths the repository actually uses |
| `session-reaping` | no config root holding a sessions registry was found | that is the reading a moved registry gives. Prove the root exists before believing the zero |

## The stopping rule

A validation run needs an ending, or it quietly becomes "we are just using it now". This run is over
when all five hold.

1. **The controls pass in the same run that measures.** `run-checks.ps1` reports every instrument
   PROVEN. A reading taken by an unproven instrument does not count toward anything below.
2. **Every signal has produced at least one reading that is not CANNOT_TELL**, over a corpus the
   receipt shows was not empty. A quiet channel does not satisfy this. Send a canary and watch it
   arrive.
3. **One deliberate end-to-end probe per channel has gone through.** Send a message and see the
   receipt. Take a claim and release it. Allocate a number and land it. Remove a worktree and see
   the reaper account for it.
4. **The instruments have run at least twice**, once early enough to act on what they find, and once
   after the last piece of work. The second run's corpus counts must be larger than the first. Equal
   counts mean the run never loaded the tooling.
5. **Every BROKEN reading is fixed, or filed with a number.** An unfiled defect is one the next run
   rediscovers as if it were new.

Then stop. Running these on a habit turns a measurement into background noise, and nobody reads
background noise.

## What these instruments cannot see

Named because a blind spot nobody states becomes a coverage claim.

- **A drain that deletes both the message and its receipt leaves nothing behind.** That message is
  invisible to every count here. Delivery is provable only where a receipt survives.
- **The claim and reaping checks read the session registry, which is a vendor surface.** A renamed
  field leaves the record counts untouched and turns verdicts to UNVERIFIED. A healthy census is not
  evidence the schema still matches.
- **The allocation check cannot fail on an unallocated number.** The registry is per clone, so a
  number allocated in another checkout is absent here for an innocent reason. It is a note.
- **The fixtures for `claim-holders`, `allocation-collisions` and `session-reaping` enter through a
  second reader.** They prove the analysis fires. They do not prove the live reader found anything,
  which is what the corpus counts are for. Both halves are needed.
- **PROVEN covers the verdict logic, not the live reader.** An instrument mutated so it can never
  report a collision on real data still reads PROVEN here, because the fixture path is untouched.
  Three real defects lived in that gap.
  `tests/test_a_validation_check_reads_real_data_the_way_it_reads_a_fixture.py` closes it for the
  three checks that read a live corpus, by building a mail root and a real git repository rather
  than a fixture. The gap is narrower now, not gone: the two registry checks still enter through a
  second reader.
- **These are diagnostics, not gates.** Nothing here blocks a commit or a push. They report.

## The files

| File | What it holds |
|---|---|
| `run-checks.ps1` | the registry of checks, the control pass, and the live pass |
| `_receipt.ps1` | the receipt shape and the one rule that turns a corpus and a finding into a verdict |
| `_mailbox.ps1` | the schema-tolerant mail-lane reader the two message checks share |
| `check-*.ps1` | one instrument per signal |
| `fixtures/broken/` | the planted corpus each check must fire on |
| `fixtures/clean/` | the planted corpus each check must stay quiet on |

Related reading: [session mail](../../docs/SESSION-MAIL.md) for the lane the message checks read,
[coordination](../../docs/COORDINATION.md) for claims and presence, and
[sequence allocation](../../docs/SEQUENCE-ALLOC.md) for the number the allocation check groups on.
