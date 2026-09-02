# Session mail for a KORUS build

## TLDR/BLUF

**What this is.** Build instructions for a mailbox that reaches a [KORUS](KORUS.md) peer the
realtime channel can *list* but cannot *send* to. Two peers need one: an editor-extension session,
and a session under a [second Claude account](DESKTOP-ACCOUNTS.md).

**This page ships nothing. No script here implements it.** It is the design, staged as buildable
steps, plus every failure a first attempt hits. Each failure below was measured, not reasoned about.
Two survived a full review before anyone caught them.

**Why you should care.** [Announce](COORDINATION.md#announcing-yourself), the realtime channel, only
knows about sessions the desktop app itself started. Neither peer above is one of those, by
construction rather than by bug.

Not for you if every session in your build runs under one desktop app on one account.

**How to use it.** Start at [The shape of a working lane](#the-shape-of-a-working-lane), then work
through the steps in order. Read
[Four ways the first attempt breaks](#four-ways-the-first-attempt-breaks) before you ship. Each was
found by someone who thought their first build was done.

---

## Who actually needs this

KORUS recommends a VS Code instance alongside the desktop app for review, and several Claude
accounts to cover a week of build work. Both of those peers sit outside announce's reach, and the
gap is structural, not a setting to flip.

**The gap is delivery, not discovery.**
[Announce](COORDINATION.md#announcing-yourself) finds peers through `presence.ps1`, which reads the
on-disk registry across every config root and sees every surface. So it can *list* both peers below.

What it cannot do is send to them. Delivery runs through `list_sessions` and `send_message` on a
desktop-only MCP server, and that map holds only sessions the desktop app itself spawned, under the
account it authenticated against.

| Peer | Why announce cannot reach it |
|---|---|
| A VS Code companion session | Visible in the roster, but never entered into the desktop app's session map -- not filtered out, never registered. There is no id to send to |
| A session under a second Claude account | Its config root is independent. The roster spans it; the messaging map does not |

A file drop is blind to both axes. It does not care which app spawned the reader or which account it
logged into. That is the whole reason the lane is a file, not a second realtime channel.

**A failed send is evidence about your instrument before it is evidence about the channel.** The
`SendMessage` tool addresses subagents of your own session, not sibling top-level sessions.

A `SendMessage` failure to a sibling proves nothing about whether that peer is reachable at all.
Confirm which tool you called before deciding a peer is unreachable.

---

## The shape of a working lane

The lane is a **file drop** under the git common directory, in a mail root of its own -- not the
shared state root the coordination scripts use ([Coordination](COORDINATION.md)). A send command
writes the file; a hook in the recipient's session reads it. That hook is the **drain** below.

Three design choices carry the rest of this page, and each earns its place from a measured failure
below.

- Put the drop **inside `.git`**. Nothing under `.git` can enter a commit, and it is not a ref
  namespace, so `push --mirror` cannot carry it either. The leak risk becomes structural, not policed.
- Address a box by the **recipient's worktree path**, never by name or session id.
- Split delivery into **show** (every hook run) and **consume** (one event only). A client can spawn
  and discard a session before it reaches the event that would consume anything.

**The leak guarantee belongs to the path, not the design, and it does not travel.** Move the queue
outside `.git` and both properties disappear at once: a temp directory, a synced drive, neither
carries it.

Re-decide the plain-text-versus-hashed question there. Do not assume it carries over.

---

## Step 1: pick the state root

**The goal.** One mail root every worktree of a clone resolves the same way, so both ends of a
message agree where the boxes are.

**What to do.** Resolve it from the git common directory, once, and reuse that value:

```powershell
git rev-parse --path-format=absolute --git-common-dir
```

**What happens next.** You get one absolute path, identical from every worktree of that clone.

Build the boxes under it. `<git-common-dir>/mail/` is a reasonable layout:

- `box/<worktree-key>/inbox|claiming|seen|expired/`, one set of four per recipient.
- `tmp/`, for atomic publish staging: a message is written there and moved into an inbox in one
  step, so no reader ever sees half of it.
- One `OFF` file.

The `OFF` file's mere presence suppresses delivery for every worktree, without losing what is queued.

**That resolution assumes the session's cwd is inside the clone.** A session rooted at a directory that
*contains* clones -- a worktree container -- has no common dir, so the drain resolves nothing and
exits silently.

That silence is byte-identical to a healthy channel with no peers. Measured in August 2026 on a
separate implementation of this design. A container holding roughly 25 clones and worktrees was
addressed: the mail queued, nothing was ever delivered, and every send reported success.

**A session outside a clone has to be told where its queue lives.** Give the drain an explicit
anchor parameter naming the repository whose queue to read, rather than inferring one from the cwd.

**An anchor answers which queue, never which box.** Keep the box key a function of the session's own
cwd, or an anchored session reads the anchor repository's mail.

The key itself needed no change.
[Step 2](#step-2-address-a-box-by-worktree-not-by-name-or-session-id) keys on a normalized path hash
rather than a name, so the container got a valid box with no code written. That is a rule paying off
in a case it was not written for.

---

## Step 2: address a box by worktree, not by name or session id

**The goal.** An address that still points at the right box after a context clear, or a branch
switch.

**What to do.** Key each box on the recipient's worktree path.

- **Not by session id.** A context clear re-mints the id and strands mail addressed to the old one.
- **Not by worktree name.** A name is a creation-time label nothing keeps current. One worktree was
  observed on four different branches in a single day.

Write one function that computes the key, dot-sourced by both the sender and the drain, so the two
ends can never compute a different key from the same path:

0. **Resolve first.** Take the path to an absolute one, then to its worktree root
   (`git rev-parse --show-toplevel`). A relative `-To ..\peer` and a session launched in a
   subdirectory are both routine, and neither yields the same string as the recipient's own cwd.
1. Normalize trailing separator and slash direction, and fold case **only on a case-insensitive
   filesystem** ([Canonicalise before comparing](CONCEPTS.md)).
2. Hash the normalized string for injectivity: two different paths can never land in one box.
3. Keep a readable slug beside the hash, only so a human can tell boxes apart in a listing.

**What happens next.** Sender and drain compute the same key from the same path, and a listing shows
one box per worktree.

**Step 0 is the whole guarantee.** The promise above is that the two ends agree *from the same path*
-- it says nothing about them starting from the same path, and by default they do not. Skip it and
you build the silent misdelivery the next paragraph warns about.

**Match the key exactly, never by prefix, and expect getting it wrong to be silent.** A message
addressed to a peer's primary checkout instead of its worktree queued, reported success, and landed in
a box nobody drains. Every observable said it had worked.

---

## Step 3: write send, list and status commands

**The goal.** Commands a peer can run without having read this page.

**What to do.** Give send a destination, a body, and nothing else load-bearing:

```powershell
mail.ps1 -Send -To ..\your-worktree -Body "the ADR number is 0161"
mail.ps1 -Send -To all -Body "rebasing main in 10 minutes"
mail.ps1 -List
mail.ps1 -Status
```

**What happens next.** The message sits in the recipient's inbox until that recipient's drain runs.
Nothing is delivered at send time.

`-To all` broadcasts to every live worktree your presence roster can see. `-ToSessionId` optionally
narrows delivery to one session. Keep it a filter, never the addressing key, for the reason in step 2.

Give every message a TTL -- the age at which an undelivered message expires, set in step 6 -- and a
`-Kind` label such as `note`, `handoff`, or `alert`. The label is display-only, never a control.

**A length check in the send command is a courtesy, not a control.** Whoever can write a file into the
inbox never runs the sender's code. The binding cap belongs in the drain, covered in step 7.

---

## Step 4: claim a message exactly once

**The goal.** Each message claimed exactly once, even though two drains can run over one inbox at
the same time.

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

**What to do.** Build the claim as an **exclusive open, no sharing**. Stale metadata cannot answer
it.

**What happens next.** The claim is slightly over-strict, so retry briefly and then cede. An
unclaimed message stays claimable, and a false win is a double delivery. Ceding is the safe
direction.

> A concurrency result is a fact about a configuration, not about an API. A threads-in-one-process test
> is not evidence about processes, and it looks perfect right up until it runs as one.

---

## Step 5: split show from consume across two hook events

**The goal.** A message that survives a session which starts and vanishes before doing any work.

A hook that **consumes** at session start can lose state to a session that never really existed. One
measured launch produced six `SessionStart` events under six different ids. Exactly one of them went
on to submit a prompt.

A discarded session never reaches a later event, so anything it consumed is gone with it. Nothing about
the moment `SessionStart` fires can tell a real session from a phantom.

**What to do.** Never consume at `SessionStart`. Render mail there and leave it in the inbox. A
per-session marker suppresses re-display, but never authorizes a consume.

Consume only at `Stop`, an event a discarded session never reaches: claim, write a receipt, move to
`seen/`, and remove exactly what this invocation just rendered.

**What happens next.** Two real sessions starting before either finishes a turn both display the
same message. That is the accepted trade. **Duplicate display is accepted. Silent loss is not.**

**Mint the marker after the emit, not before.** A first version of this split minted the marker before
the message existed, and treated any receipt as backing it. Receipts were keyed per message, not per
(message, session).

So one session's receipt backed another session's marker, and a message nobody had seen was consumed.
The fix: the marker is the proof of display, written only once the display has actually happened.

Two smaller traps from that same repair each stranded a message while reporting success. Both sit in
[PowerShell failures that are silent inside a hook](#powershell-failures-that-are-silent-inside-a-hook),
with the rest of that class.

Make every write in the consume path terminating, and catch specifically, not broadly.

---

## Step 6: set one TTL, against your delivery points, not a feeling

**The goal.** One expiry number, chosen against the moments delivery can actually happen.

A message should be the one thing in this design that expires.
[Held state and a message expire for opposite reasons](CONCEPTS.md#the-rule-is-about-held-state-and-a-message-is-not-held-state).

Expiring held state hands a critical section to a second process while the first is still in it.
Expiring a message stops a stale instruction from being acted on.

**What to do.** Pick the number against when delivery actually happens: `SessionStart` and `Stop`. A
recipient closed or idle overnight receives nothing until it is opened again.

**What happens next.** At 720 minutes an ordinary overnight gap expired a real message. At 4320
minutes -- a weekend -- a three-day-old instruction still refuses to expire.

**Expiry is the only point where a message is lost rather than merely late, and it is reachable by
doing nothing.**

The loss is silent both ways: the recipient is never told a message existed, and the sender is never
told it went unread. A longer TTL lowers the frequency. It does not touch the silence.

---

## Step 7: treat the message body as hostile input

**The goal.** A body that cannot forge the frame around it, reach a path it was not addressed to, or
flood the recipient's screen.

**What to do.** Apply every rule below. Each closes a real defect, not a hypothetical one.

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

**What happens next.** Overflow should defer, never drop: a message too large for the current batch
stays in the inbox for the next drain. A single body over the per-message cap is still delivered,
truncated, with a pointer to the full file on disk.

**Measure the cap as rendered on every capped string the drain writes, not only on a body it
delivers.** Its own receipt notes are capped, and are subject to the same rule.

Measured in August 2026 on a separate implementation of this design. A receipt note capped at 80
characters lost the word that told two causes apart, because that word sat at the end of the
sentence.

Two different failures then wrote identical receipts, which is the defect the note existed to
prevent. It was caught by a test asserting on the rendered receipt, and nothing else would have
caught it.

**Lead a capped string with its discriminator, and assert on rendered output, never on the string
you meant to write.**

---

## Step 8: prove delivery, do not infer it from a successful send

**The goal.** Delivery you can point at, rather than a send you assume worked.

**Queued is not delivered.** Delivery happens when the recipient's drain next runs. Confirm it rather
than reading a successful send as proof.

**What to do.** Build three habits into the drain, which make delivery observable instead of merely
wired:

- **The drain announces that it ran.** "The box is empty" beats silence: a missing line means the hook
  did not fire, where silence alone reads the same as a hook that fired and found nothing.
- **A receipt records what was observed, not what was attempted**, written by the drain at the moment
  it renders. A receipt written by hand can assert a delivery that never happened.
- **Every observation carries its as-of time.** An undated observation reads as current and is not
  usable for anything.

---

## PowerShell failures that are silent inside a hook

Every entry below reported success to whoever ran it. Each was measured in August 2026 on a separate
implementation of this design, and hit by someone who had already read this page.

Run down at least these three before you ship a drain:

- **A mandatory string parameter rejects an empty string.** `[Parameter(Mandatory)][string]` given
  `""` throws before the body runs. That throw landed in a bare catch and killed a diagnostic path.
- **`$ErrorActionPreference = 'SilentlyContinue'` does not reach every error.** A
  `ParameterBindingException` is outside it, and so is a command that does not exist. One landed in
  a broad catch and produced a silent exit 0.
- **An unwrapped call sits between one state write and the next.** A file move that is
  non-terminating under a suppressed error preference completed, and no receipt was written after it.

The third one generalizes.
[Hooks](HOOKS.md#every-exit-from-a-stateful-hook-is-a-state-transition) carries the rule: a hook that
persists state has a state machine, and a call between two writes is where a transition goes missing.

---

## Four ways the first attempt breaks

Every one of these was found after a version that looked finished had passed review. The step that
answers each is named beside it:

1. **The exclusion primitive did not exclude.** Step 4: an exclusive open, not a move-and-catch.
2. **Showing is not consuming.** Step 5: render at every event, consume only at `Stop`.
3. **The repair reintroduced the defect it was fixing.** Step 5: mint the marker after the emit.
4. **A mid-turn wake-up is one-shot.** Below: re-arming belongs to the hook, not the watcher.

Budget review time for exactly these four. They are the ones that survive a plausible first pass.

---

## A mid-turn wake-up is one-shot, and cannot fix itself

The default `SessionStart`/`Stop` drain leaves a gap: a recipient idle for hours gets nothing until it
next opens. An urgent tier can close part of that gap.

**The goal.** Wake an idle recipient mid-turn, rather than waiting for its next turn boundary.

**What to do.** Arm a watcher at `Stop`, waking the session through a hook that carries **both**
`async` and `asyncRewake` -- [`asyncRewake` alone can block it](HOOKS.md). Arm it again on
`UserPromptSubmit`, so it re-arms once per real turn.

**What happens next.** It works, and then it stops. It cannot re-arm itself. The wake belongs to a
process the client spawned and is tracked by hook id, so a self-respawn produces a grandchild whose
exit nobody is listening for.

**Re-arming is the next hook's job, not the watcher's.** Arming the watcher on `SessionStart`
instead would spawn one watcher per phantom session.

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

The console and lander sessions are the two most likely to need this lane. Both are roles in the
[build shape](KORUS-BUILD.md) that [KORUS](KORUS.md) sets out.

The console reaches a VS Code review instance running alongside the desktop app. The lander reaches
a build session parked under a second account while its own account is out of weekly usage.

A build session that never leaves the desktop app, on the account driving it, has no gap for this lane
to close. [Announce](COORDINATION.md) already reaches it.

---

## Related

| For | Read |
|---|---|
| The build these console and lander sessions sit in | [Run a KORUS build](KORUS-BUILD.md) |
| The realtime channel, and who it can reach | [Coordination](COORDINATION.md) |
| Delivering a note into a running session, mid-turn | [Steering](STEERING.md) |
| Why held state and a message expire for opposite reasons | [Concepts](CONCEPTS.md) |
| Hook events and their failure postures | [Hooks](HOOKS.md) |
| Which channel to reach for which peer, timing included | [Running multiple sessions](RUNNING-MULTIPLE-SESSIONS.md) |
| Proving a control can actually fail | [CI and standards](https://secure-development-standards.pages.dev/CI-AND-STANDARDS.html) |
