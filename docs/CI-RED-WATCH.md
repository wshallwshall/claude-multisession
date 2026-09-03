# Noticing a red without a session watching for it

## TLDR/BLUF

**What this is.** A cron script that polls for pull requests your repository has labelled red, and
starts one session per red to work out whose failure it is. It makes no model calls of its own.

**Why you should care.** A red waits until some long-lived session notices it. That session is also
the only one your operator talks to, so a busy one leaves the red unattributed. Not for you if
nothing labels a failing pull request: the watcher will not report on a label that does not exist.

**How to use it.** Add a `ciRed` block to `ccx.config.json`, then run
[`scripts/cron/watch-ci-red.ps1`](https://claude-multisession.pages.dev/scripts/cron/watch-ci-red.ps1)
on a schedule. Start with `-DryRun`.

---

## Nothing tells a session that a check went red

GitHub cannot reach into a session. There is no event a seat can subscribe to.

So the only path was: a console session polls, sees a red, and spawns a seat to attribute it. That
makes one session a single point of failure, and it is the same session the operator is talking to.

Autofix does not close this. It only wakes a session that is still live, and workers here end their
turn when the work is done. When it does fire, it tells a builder what broke, never whose failure it
is.

## Your repository sends the signal by labelling

The watcher does not read check results. Your repository labels a pull request when a required check
fails, and the watcher polls for that label.

That turns noticing into one list call across every open pull request, instead of a check rollup
fetched per pull request. It is the difference between a poll you can run every minute and one you
cannot.

**This is not a push.** GitHub still cannot reach into a session. The label only makes the poll cheap
enough to run often, which is the version you can actually have.

The label name is yours. The watcher reads it from `ciRed.label` and falls back to `ci-red`. Its
receipt always says which of the two supplied the name.

## What a tick costs

Nothing, while your repository is quiet.

| Watcher | Cost per waiting minute |
|---|---|
| A resident session on a three-minute heartbeat | 2,108 metered tokens |
| A resident session on a ten-minute sleep loop | 22,275 metered tokens |
| This script | Zero model tokens, plus three API calls |

A model starts only after a red already exists. If your design needs a model call to decide whether
to spawn, it is the resident session again under another name.

## Set it up

Add the block to `ccx.config.json`. Every key is optional and every one has a default.

```json
"ciRed": {
  "label": "ci-red",
  "repo": "you/your-repo",
  "claimPrefix": "ci-red-pr",
  "spawn": { "command": "claude", "args": ["-p"] }
}
```

| Key | Default | Controls |
|---|---|---|
| `label` | `ci-red` | The label your repository applies when a required check fails |
| `repo` | the `origin` remote | Which repository to poll, as `owner/name` |
| `claimPrefix` | `ci-red-pr` | The claim key stem, so one clone can watch two repositories |
| `spawn.command` | `claude` | What starts a seat. Give a full path if a shim resolves it |
| `spawn.args` | `["-p"]` | Fixed arguments. The generated prompt is appended after them |

Then schedule it. On Windows, one line registers a task that ticks every five minutes:

```
schtasks /Create /TN ccx-ci-red /SC MINUTE /MO 5 /TR "pwsh -NoProfile -File C:\path\scripts\cron\watch-ci-red.ps1"
```

Run it by hand first, with `-DryRun`, and read the receipt.

## It will not start two seats on one red

Two seats attributing one failure is worse than none. Each assumes the other did not.

The claim is [`scripts/coord/claim.ps1`](COORDINATION.md), the registry this project already has,
rather than a second one invented for the watcher. It needs two guards, because that script alone
does not cover this caller.

1. Across sessions, the claim's exclusive file create is the mutual exclusion. A peer holding the key
   makes the take fail, and the watcher skips that red.
2. Across ticks, it is not. Re-taking a key you already hold is a success on purpose, so a session
   can re-assert its own claim. Every tick runs from the same worktree, so every tick would re-take
   its own claim and start a second seat.

So the whole pass runs inside one lock, and the claim file is tested for before the take.

After a take succeeds, the watcher checks that the claim file it predicted actually appeared. The
prediction repeats a path formula that `claim.ps1` owns, and a formula in two places drifts. If the
file is missing, the run refuses and says so instead of starting a seat.

Nothing releases the claim on your behalf. The seat releases it when it is done, which is why the
briefing carries the release command.

## A held claim does not mean anyone is still working the red

This is the mirror of the rule above, and it costs the same thing.

Claims never expire. The claim also names the **watcher's own checkout** as the holder, because that
is where `claim.ps1` gets run from. Every liveness probe in this project reads the holder's worktree,
and that worktree is the one the cron ticks from, so it is always there.

Put those together and a seat that died one second after it started reads exactly like a seat that is
mid-attribution. Forever. The red waits on nobody while every tick prints a line that looks like
coverage.

So each spawn writes a dispatch record beside the journal. It holds the seat's process id, the start
time that tells that id from a reused one, and the journal's length at briefing time.

A later tick reads that record and answers in three different words.

| The tick finds | It says | Exit |
|---|---|---|
| The seat process is still running | `ALREADY-CLAIMED` | 0 |
| The process is gone, or its id now belongs to something else | `SEAT-GONE` | 1 |
| No dispatch record, or a start time it cannot read | `SEAT-UNKNOWN` | 1 |
| The claim file itself cannot be read | `SEAT-UNKNOWN` | 1 |
| The key is held by another worktree | `ALREADY-CLAIMED` | 0 |

**The start times are compared with a one-second window, not for equality.** The two readings come
from two different calls, and on Linux .NET derives the start time from the boot instant, which is
itself derived.

Two reads of one live process need not agree to the tick. An exact match called a running seat gone
on the ubuntu leg, and that sentence is the one that gets a working seat's claim released.

The window only ever errs toward `ALREADY-CLAIMED`, which costs a tick. A seat runs for minutes, so
a number reused inside one second is not a case this meets.

`SEAT-GONE` also says whether the seat appended to the journal before it went. A seat that wrote
nothing left the red unattributed; a seat that wrote left a verdict and only failed to release its
key, and those need different things from you.

**Nothing is released or respawned on the strength of that reading.** A seat that exits without
releasing may have finished.

Releasing on that inference frees the key for a second seat to re-attribute work already done.
Respawning on it starts a session every tick for as long as the label stays on.

The run reports what it can prove, fails, and hands you the release command.

## A missing label is not an all clear

Measured 2026-08-31: `CLAUDE_CONFIG_DIR` pointing at a directory that does not exist makes
`claude agents --json` return an empty list and exit 0. No error, no warning. A mistyped root and an
empty fleet look identical.

The same shape is available here three ways, so each check states the reading that proves it ran.

| Check | The reading that must come back |
|---|---|
| The repository is reachable | The API echoes the same full name back |
| The label exists on your repository | The API echoes the same label name back |
| The open pull request list is readable | A list, of which zero is a valid length |

The middle one carries the most weight. A query for a label nobody created returns an empty list and
exits 0, so a repository that never installed the labelling half reads exactly like one with nothing
red.

Each finding also has to appear in the open pull request list, which is fetched separately. One that
does not is reported and skipped rather than spawned on.

**Unless that list was capped.** The open list is fetched with a `-Limit`, and a list that fills it
may be short.

A labelled pull request missing from a capped list might be closed. It might also just sit past the
cap, and the watcher cannot tell which.

So it reports `NOT-OPEN-UNVERIFIABLE`, starts no seat, and the run ends `INCOMPLETE`. Reporting
success there would hide the red it exists to catch. Raise `-Limit` past your open pull request
count.

A check that reads back nothing makes the whole run **CANNOT-LOOK**, exit 2, and no all clear. Every
run prints what it scanned: the repository, the label, where each came from, and how many open pull
requests it examined.

### The three exit codes

| Code | Status | What it means |
|---|---|---|
| 0 | `OK` | It looked, and every red it found reached a seat |
| 1 | `INCOMPLETE` | It looked, and at least one red did not reach a seat |
| 2 | `CANNOT-LOOK` | It could not establish what it was looking at |

Exit 2 is reserved for a failed look, and the difference is worth keeping. A claim the watcher takes
but cannot then see is a failure to **act**, so it ends at exit 1 with the drift named in the reason.

A tick that finds the pass lock held by a sibling ends at exit 2. It examined nothing, so it has no
count to report.

## The seat starts fresh and keeps a journal

A worker that finished its turn has exited. Measured on the reference fleet: 740 session records
against 2 live sessions. There is usually nobody to wake.

So the watcher starts a new session. The branch and the worktree survive, so that session continues
the work rather than restarting it.

What does not survive is any memory of the last red. Each spawn appends to a journal at
`<state-root>/ci-red/pr-<number>.md`, and the prompt tells the seat to read that file first and
write to it last.

The briefing gives the seat one job: say whose failure this is. A red belongs to the pull request, to
the trunk, to a flake, or to the merge queue, and only the first is a builder's to fix. Sending all
four back to a builder is the failure the seat exists to prevent.

## What it does not do

It does not label anything. That half lives in your repository, and the watcher treats the label as a
contract it reads rather than a name it defines.

It does not decide whose failure a red is. That is the seat's work, and no script can do it.

It cannot see a red on a pull request your repository failed to label. The watcher is exactly as
complete as the labelling half you wired up.

## Related

- [Coordination](COORDINATION.md) -- the claim registry the watcher takes a key from
- [Usage awareness](USAGE-AWARENESS.md) -- why an unproven reading has to refuse rather than report
- [CI for leaders](CI-FOR-LEADERS.md) -- what done means when the author cannot vouch for the change
- [Every script](SCRIPTS.md) -- the full inventory, including this one
