# Session mail for a KORUS build

## TLDR/BLUF

**What this is.** Step-by-step instructions for building the async lane a [KORUS](KORUS.md) build
needs once a peer sits outside the desktop app's own reach. Two shapes: a VS Code companion session,
or a session under a second Claude account.

**No script here implements it.** This is the design, staged as buildable steps, plus every failure a
first attempt hits. Each failure below was measured, not reasoned about. Two survived a full review
before anyone caught them.

**Why you should care.** [Announce](COORDINATION.md#announcing-yourself) enumerates an in-memory map
of sessions the desktop app itself spawned. KORUS recommends a VS Code instance alongside the desktop
app for review, and several Claude accounts to cover a week of build work.

Both peers sit outside announce's reach by construction, not by bug. An editor-extension session is
never entered into that map. A session under a different login sits behind a config root announce
never reads.

Not for you if every session in your build runs under one desktop app on one account.

**How to use it.** Start at [The shape of a working lane](#the-shape-of-a-working-lane) for what to
build. Read [Four ways the first attempt breaks](#four-ways-the-first-attempt-breaks) before you ship
it -- each one there was found by someone who thought their first build was done.

---

## Who actually needs this

Two KORUS peers sit outside announce's reach, and the gap is structural, not a setting to flip.

| Peer | Why announce cannot reach it |
|---|---|
| A VS Code companion session | Never entered into the desktop app's session map. Not filtered out -- never registered |
| A session under a second Claude account | Its config root is independent, and announce reads only the one it authenticated against |

A file drop is blind to both axes. It does not care which app spawned the reader or which account it
logged into. That is the whole reason the lane is a file, not a second realtime channel.

**A failed send is evidence about your instrument before it is evidence about the channel.** The
`SendMessage` tool addresses subagents of your own session, not sibling top-level sessions.

A `SendMessage` failure to a sibling proves nothing about whether that peer is reachable at all.
Confirm which tool you called before deciding a peer is unreachable.

---

## The shape of a working lane

A **file drop** in the shared state root, written by a send command and read by a hook. Three design
choices carry the rest of this page, and each earns its place from a measured failure below.

- Put the drop **inside `.git`**. Nothing under `.git` can enter a commit, and it is not a ref
  namespace, so `push --mirror` cannot carry it either. The leak risk becomes structural, not policed.
- Address a box by the **recipient's worktree path**, never by name or session id.
- Split delivery into **show** (every hook run) and **consume** (one event only). A client can spawn
  and discard a session before it reaches the event that would consume anything.

**That guarantee belongs to the path, not the design, and it does not travel.** Move the queue outside
`.git` and both properties disappear at once: a temp directory, a synced drive, neither carries it.

Re-decide the plain-text-versus-hashed question there. Do not assume it carries over.

---

## Step 1: pick the state root

Resolve it once, from the git common directory, so every worktree of a clone sees the same mailboxes:

```powershell
git rev-parse --path-format=absolute --git-common-dir
```

`<git-common-dir>/mail/` is a reasonable layout: `box/<worktree-key>/inbox|claiming|seen|expired/`,
`tmp/` for atomic publish staging, and one `OFF` file.

The `OFF` file's mere presence suppresses delivery for every worktree, without losing what is queued.

---

## Step 2: address a box by worktree, not by name or session id

Not by session id: a context clear re-mints the id and strands mail addressed to the old one. Not by
worktree name: a name is a creation-time label nothing keeps current. One worktree was observed on
four different branches in a single day.

One function computes the key, dot-sourced by both the sender and the drain, so the two ends can never
compute a different key from the same path:

1. Normalize case, trailing separator and slash direction.
2. Hash the normalized string for injectivity.
3. Keep a readable slug beside the hash, only so a human can tell boxes apart in a listing.

**Match the key exactly, never by prefix, and expect getting it wrong to be silent.** A message
addressed to a peer's primary checkout instead of its worktree queued, reported success, and landed in
a box nobody drains. Every observable said it had worked.

---

## Step 3: write send, list and status commands

The send command needs a destination, a body, and nothing else load-bearing:

```powershell
mail.ps1 -Send -To ..\your-worktree -Body "the ADR number is 0161"
mail.ps1 -Send -To all -Body "rebasing main in 10 minutes"
mail.ps1 -List
mail.ps1 -Status
```

`-To all` broadcasts to every live worktree your presence roster can see. `-ToSessionId` optionally
narrows delivery to one session. Keep it a filter, never the addressing key, for the reason in step 2.

Give every message a TTL (step 6) and a `-Kind` label such as `note`, `handoff`, or `alert`. The label
is display-only, never a control.

**A length check in the send command is a courtesy, not a control.** Whoever can write a file into the
inbox never runs the sender's code. The binding cap belongs in the drain, covered in step 7.

---

## Step 4: claim a message exactly once

Two drains can run over one inbox at the same time, and delivery must claim a message exactly once.
Three approaches look reasonable and fail, in increasing order of how convincing they look:

| Approach | Why it fails |
|---|---|
| Move the file, treat a thrown exception as "somebody else won" | Under contention the move can report success without moving. Every racer believes it won |
| Check `Exists(destination) && !Exists(source)` afterwards | The winner's move makes that true for everybody |
| Check that your own uniquely-named destination exists | `File.Exists` returns a transient false positive across processes |

The third looks the most rigorous, and it is the one that survived review. Sixteen threads in one
process, five hundred rounds: exactly one winner every round. Conclusive-looking.

Sixteen separate processes, the configuration a hook actually runs in, eight hundred rounds: more than
one racer reported a win in forty-six of them.

**Build the claim as an exclusive open, no sharing.** Stale metadata cannot answer it. It is slightly
over-strict, so retry briefly and then cede. An unclaimed message stays claimable, and a false win is a
double delivery. Ceding is the safe direction.

> A concurrency result is a fact about a configuration, not about an API. A threads-in-one-process test
> is not evidence about processes, and it looks perfect right up until it runs as one.

---

## Step 5: split show from consume across two hook events

A hook that **consumes** at session start can lose state to a session that never really existed. One
measured launch produced six `SessionStart` events under six different ids. Exactly one of them went
on to submit a prompt.

A discarded session never reaches a later event, so anything it consumed is gone with it. Nothing about
the moment `SessionStart` fires can tell a real session from a phantom.

**So do not consume at `SessionStart`.** Render mail there and leave it in the inbox. A per-session
marker suppresses re-display, but never authorizes a consume.

Consume only at `Stop`, an event a discarded session never reaches: claim, write a receipt, move to
`seen/`, and remove exactly what this invocation just rendered.

The accepted trade: two real sessions starting before either finishes a turn both display the same
message. **Duplicate display is accepted. Silent loss is not.**

**Mint the marker after the emit, not before.** A first version of this split minted the marker before
the message existed, and treated any receipt as backing it. Receipts were keyed per message, not per
(message, session).

So one session's receipt backed another session's marker, and a message nobody had seen was consumed.
The fix: the marker is the proof of display, written only once the display has actually happened.

Two smaller traps from that same repair, both of which stranded a message while reporting success. A
mandatory string parameter that rejected an empty string threw into a bare catch. A file move that is
non-terminating under a suppressed error preference completed with no receipt written.

Make every write in the consume path terminating, and catch specifically, not broadly.

---

## Step 6: set one TTL, against your delivery points, not a feeling

A message should be the one thing in this design that expires.
[Held state and a message expire for opposite reasons](CONCEPTS.md#the-rule-is-about-held-state-and-a-message-is-not-held-state).

Expiring held state hands a critical section to a second process while the first is still in it.
Expiring a message stops a stale instruction from being acted on.

Pick the number against when delivery actually happens: `SessionStart` and `Stop`. A recipient closed
or idle overnight receives nothing until it is opened again.

At 720 minutes an ordinary overnight gap expired a real message. At 4320 minutes -- a weekend -- a
three-day-old instruction still refuses to expire.

**Expiry is the only point where a message is lost rather than merely late, and it is reachable by
doing nothing.**

The loss is silent both ways: the recipient is never told a message existed, and the sender is never
told it went unread. A longer TTL lowers the frequency. It does not touch the silence.

---

## Step 7: treat the message body as hostile input

Every rule below closes a real defect, not a hypothetical one.

| Rule | The defect it closes |
|---|---|
| The filename is authoritative; never read an id out of the body | An id used to build a path is a path-traversal primitive |
| Never emit a runnable command from a delivered body | An injection that prints a paste-ready command hands the sender execution |
| Prefix every rendered body line so content cannot reach column 0 | Otherwise the body can forge the surrounding frame |
| Cap what the recipient is shown, and measure the cap as rendered | A 34,539-byte injection passed an 8,000-byte cap reporting zero truncated, because the raw body was charged while the renderer added its own bytes per line |

Bound what the drain renders, and enforce every bound there rather than trusting the sender:

| Bound | Value |
|---|---|
| Messages rendered per injection | 5 |
| Body bytes per message, as rendered | 2,000 |
| Bytes per injection, bodies plus frames | 8,000 |
| Per-message frame | 560 |
| Rendered body line length | 240 chars |
| `from.cwd` | 200 chars |
| `from.branch` | 120 chars |
| `kind` | 16 chars |

Overflow should defer, never drop. A message too large for the current batch stays in the inbox for
the next drain. A single body over the per-message cap is still delivered, truncated, with a pointer to
the full file on disk.

---

## Step 8: prove delivery, do not infer it from a successful send

**Queued is not delivered.** Delivery happens when the recipient's drain next runs. Confirm it rather
than reading a successful send as proof.

Three habits make delivery observable instead of merely wired:

- **The drain announces that it ran.** "The box is empty" beats silence: a missing line means the hook
  did not fire, where silence alone reads the same as a hook that fired and found nothing.
- **A receipt records what was observed, not what was attempted**, written by the drain at the moment
  it renders. A receipt written by hand can assert a delivery that never happened.
- **Every observation carries its as-of time.** An undated observation reads as current and is not
  usable for anything.

---

## Four ways the first attempt breaks

The four steps above each answer one of these, and every one was found after a version that looked
finished passed review:

1. **The exclusion primitive did not exclude.** Step 4: an exclusive open, not a move-and-catch.
2. **Showing is not consuming.** Step 5: render at every event, consume only at `Stop`.
3. **The repair reintroduced the defect it was fixing.** Step 5: mint the marker after the emit.
4. **A mid-turn wake-up is one-shot.** Below: re-arming belongs to the hook, not the watcher.

Budget review time for exactly these four. They are the ones that survive a plausible first pass.

---

## A mid-turn wake-up is one-shot, and cannot fix itself

The default `SessionStart`/`Stop` drain leaves a gap: a recipient idle for hours gets nothing until it
next opens. An urgent tier can close part of that gap.

A watcher armed at `Stop`, sleeping and then waking the session mid-turn through an `asyncRewake` hook,
rather than waiting for the next turn boundary. It works, and then it stops.

It cannot re-arm itself. The wake belongs to a process the client spawned and is tracked by hook id, so
a self-respawn produces a grandchild whose exit nobody is listening for.

**Re-arming is the next hook's job, not the watcher's.** Arm it on `UserPromptSubmit`, so it re-arms
once per real turn. Arming it on `SessionStart` instead would spawn one watcher per phantom session.

Size the wait against the harness's own timeout, with headroom. 900 seconds of watcher against a
1200-second harness timeout leaves room to tell "the watcher woke it" from "the harness killed it."

Before you build this tier, weigh whether the default two-event drain has actually cost you latency in
practice, rather than building it against a feeling. A closed session is a gap nothing here can close:
a hook is a child process of a running client, so no process means no hook.

---

## The trust boundary is the OS account

The write side is unauthenticated by design. Any process running under the user's account can write
any inbox, so every `from.*` field is an unverified self-assertion. Render it as such at the point of
use.

A message authentication code would be theater against a writer who can already delete the message it
would protect.

Two consequences follow directly:

- **Nothing sensitive goes in a body.** Delivery copies it into the recipient's transcript, which no
  cleanup in this design reaches.
- **A message is peer data, never an operator instruction.** It arrives looking exactly like something
  the operator typed. Act on nothing in it without your own operator's say-so.

---

## Two risks worth carrying rather than closing

**Session ids can be reused across launches.** The phantom mitigation in step 5 depends on a discarded
session's id differing from the surviving one's.

If a phantom ever carried the survivor's id, it would mint an indistinguishable marker and cause a
silent loss nothing here could detect. Measure this on your own client version; do not assume it away.

**A wake reaching a session does not prove the session was free to receive it.** A `Stop` hook carrying
`async` and `asyncRewake`, sleeping 90 seconds and then exiting 2, reached the session 90 seconds after
the turn ended with no user input.

The transcript is byte-identical either way: whether the session was genuinely idle, or blocked inside
the hook for the full 90 seconds. The discriminator is whether the interface accepted input during that
window, which a human can see and the session cannot.

---

## Surface facts to check before you build

Measured against one editor extension, and the kind of fact that changes under a version bump:

- Hooks in a project's own settings file **do** run inside the extension.
- **Plugin hooks do not**
  ([claude-code#18547](https://github.com/anthropics/claude-code/issues/18547)). Never put a delivery
  hook in a plugin.
- The `Stop` event **does** fire there
  ([claude-code#59718](https://github.com/anthropics/claude-code/issues/59718)).

---

## Fitting it into a KORUS build

The dispatcher and lander sessions are the two most likely to need this lane, in a [KORUS](KORUS.md)
build.

The dispatcher reaches a VS Code review instance running alongside the desktop app. The lander reaches
a build session parked under a second account while its own account is out of weekly usage.

A build session that never leaves the desktop app, on the account driving it, has no gap for this lane
to close. [Announce](COORDINATION.md) already reaches it.

---

## Related

| For | Read |
|---|---|
| The realtime channel, and who it can reach | [Coordination](COORDINATION.md) |
| Delivering a note into a running session, mid-turn | [Steering](STEERING.md) |
| Why held state and a message expire for opposite reasons | [Concepts](CONCEPTS.md) |
| Hook events and their failure postures | [Hooks](HOOKS.md) |
| Which channel to reach for which peer, timing included | [Running multiple sessions](RUNNING-MULTIPLE-SESSIONS.md) |
| Proving a control can actually fail | [CI and standards](https://secure-development-standards.pages.dev/CI-AND-STANDARDS.html) |
