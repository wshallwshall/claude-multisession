# The async lane: reaching sessions the realtime channel cannot

> **Not shipped in this repository.** No script here implements this. It is a design note, and more
> usefully a list of the ways the obvious implementations fail. Every failure below was measured, not
> reasoned about, and several survived a full review before being caught.

> **Take a copy:**
> [markdown](https://claude-multisession.pages.dev/SESSION-MAIL.md).

## TLDR/BLUF

**What this is.** A design for an async delivery lane that reaches the peers the realtime announce
path cannot. The shape is a file drop in the shared state root, written by a send command and
delivered by a hook.

**Why you should care.** Announce enumerates an in-memory map of the sessions the desktop app itself
spawned. A session launched by an editor extension, and a session under a different login, are
unreachable by construction. Not for you as code: no script here implements this.

**How to use it.** Read it as the list of ways the obvious implementations fail. Every failure below
was measured rather than reasoned about, and several survived a full review before being caught.

---

The [announce hook](COORDINATION.md) reaches peers in realtime and cannot reach all of them. Delivery
goes through the desktop client's session-management tooling, which enumerates an in-memory map of
the sessions **that app itself spawned**, under the config root it authenticated against.

Two kinds of peer are unreachable by construction:

- a session launched by an **editor extension**, never entered into that map at all
- a session under a **different login**, whose config root is independent

An async lane covers those two. The shape that works is a **file drop** in the shared state root,
written by a send command and delivered by a hook.

---

## Put the drop inside `.git`, and that is a control

Under the git common directory, the mail directory gets two properties for free:

- **Nothing under `.git` can enter a commit.** The leak risk is structural rather than policed.
- **It is not a ref namespace**, so `push --mirror` cannot carry it either.

Because of that, recipient paths can be stored in **plain text**. Hashing them would buy nothing and
would destroy the ability to read the queue with `ls` when it misbehaves.

**That guarantee belongs to the path, not the design, and it does not travel.** Move the queue
outside `.git` -- a temp directory, a state folder beside the repo, a synced drive -- and both
properties are gone at once. The plain-text decision has to be re-made there, not inherited.

## Address a box by the recipient's worktree

Not by session id: a context clear re-mints the id and strands the mail. Not by worktree **name**:
that is a creation-time label that nothing keeps current -- one was observed on four different
branches in a single day.

Two rules go with that:

- **One definition of the key, shared by both ends.** Normalize case, trailing separator and slash
  direction, then hash. Two copies of that function drift, and then both ends look healthy while mail
  goes to a box nobody reads.
- **The hash gives injectivity; a readable slug is only so a human can tell boxes apart in a listing.**

**Match that key exactly, never by prefix, and expect getting it wrong to be silent.** Measured
2026-08-11: a message addressed to a peer's primary checkout instead of its worktree queued, reported
success, and landed in a box nobody drains. Every observable said it had worked.

---

## The one TTL in the system

A message expires. Nothing else here does, and the reasoning for that asymmetry is in
[held state versus a message](CONCEPTS.md#the-rule-is-about-held-state-and-a-message-is-not-held-state).

Pick the number against the delivery points rather than against a feeling about staleness. Delivery
happens at `SessionStart` and at `Stop`, so a recipient that is closed or idle overnight receives
nothing until somebody opens it.

Measured 2026-08-11: at 720 minutes an ordinary overnight gap expired the message. It is now 4320,
which spans a weekend and still refuses a three-day-old instruction.

> **Expiry is the only point in this transport where a message is lost rather than merely late, and
> it is reachable by doing nothing.**

---

## Which transport reaches whom

| Transport | Reaches | Does not reach |
|---|---|---|
| The `SendMessage` tool | **Subagents of your own session** | Sibling top-level sessions |
| The client's session-management tooling | Sibling sessions under the same login | Other logins |
| A file mailbox | **Any login, any client**, and it survives on disk | Sessions in another clone -- the box hangs off the git common directory |

**A failed send is evidence about your instrument before it is evidence about the channel.** Measured
2026-08-11: a `SendMessage` failure became "the realtime channel cannot reach that peer".
`SendMessage` addresses subagents, and the session-management tooling resolved it at once.

The cross-login limit in that table is real and was established separately. The trap is that the
wrong-instrument run reached a true-sounding conclusion, and that conclusion was then cited as though
the run had established it.

---

## What covers which wake gap

| The recipient is | Covered by |
|---|---|
| Mid-turn, or otherwise busy | A watcher armed at `Stop` |
| Idle, within the watcher's own wait | The same watcher: one arming covers 900 seconds |
| Idle for hours | **Nothing.** Extend the watcher, which is gated below, or use a per-session scheduled task, which fires while the prompt sits idle |
| **Closed** | **Nothing technical.** A hook is a child process of a running client, so no process means no hook |

The last row is structural rather than a gap waiting for a fix. Reaching a closed session means
reaching the human who opens it.

Arm the watcher at `Stop` and not at `SessionStart`. The drain already covers mail that arrived
before you got here, and the gap is mail landing while a session sits at a prompt with nobody typing.

---

## Four failure modes, each measured

### 1. The exclusion primitive did not exclude, and two rigorous-looking fixes also failed

Delivery must claim a message exactly once. Two drains can run over one inbox at the same time.

Three approaches fail, in increasing order of how convincing they look:

| Approach | Why it fails |
|---|---|
| Move the file, treat a thrown exception as "somebody else won" | On Windows under contention the move **returns success without moving** for losers. Every racer believes it won |
| Check `Exists(destination) && !Exists(source)` afterwards | The winner's move makes that true for **everybody** |
| Check that your own uniquely-named destination exists | `File.Exists` returns a **transient false positive across processes** |

The third one survived a full review. Here is the measurement that killed it:

- **16 threads in one process, 500 rounds:** exactly one winner every time. Conclusive-looking.
- **16 separate processes, 800 rounds** -- the configuration a hook actually runs in -- **more than
  one racer reported a win in 46 of 800.**

The verdict that holds is an **exclusive open** (no sharing), which stale metadata cannot answer. It
is slightly over-strict, so it retries briefly and then **cedes**. Ceding is the safe direction: an
unclaimed message stays claimable, while a false win is a double delivery.

> **A concurrency result is a fact about a configuration, not about an API.** A threads-in-one-process
> test is not evidence about processes, and it will look perfect.

### 2. Showing is not consuming, and that decides where the hook goes

A session-start hook that **consumes** state can lose it to a session that never existed. Clients
emit session-start events for sessions they then discard, and a discarded session never reaches its
stop event -- so anything it consumed is gone with it.

You cannot detect the phantom at that moment: the transcript does not exist yet for either kind of
session, so gating on it discriminates nothing. **So stop consuming at that event.** A hook that only
reads is safe there; consume at a later event a discarded session never reaches.

The accepted trade: if two real sessions start before either finishes a turn, both display the
message. **Duplicate display is accepted. Silent loss is not.** Never trade toward loss to avoid a
duplicate.

**Do not design against "it fires twice."** One measured launch produced **six** session-start events
under six different ids, with exactly one going on to submit a prompt and two firing mid-session.

### 3. The repair reintroduced the defect it was fixing

The first version of that show/consume split lost messages again, and survived review.

A marker was minted **before** the message was emitted, and treated as valid whenever a receipt
existed. But receipts were keyed per **message**, not per (message, session) -- so one session's
receipt "backed" another session's marker, and a message nobody had seen was consumed.

The fix is to mint the marker **after** the emit, so the marker itself is the proof of display.

> **Be careful what you treat as proof that the write happened.** A per-run artifact cannot answer a
> per-session question, and both look like "a file that exists".

Two smaller traps from the same repair, both of which stranded a message while reporting success:

- A mandatory string parameter that did not permit an empty string threw into a bare catch.
- A file write that is **non-terminating** under a suppressed error preference completed the move
  with no receipt written.

### 4. A mid-turn wake-up is one-shot

A watcher that wakes a session mid-turn rather than at the next turn boundary works, and then stops.
It cannot re-arm itself: the wake belongs to the process the client spawned and is tracked by hook
id, so a self-respawn produces a grandchild whose exit nobody is listening for.

**Re-arming is a hook's job, not the watcher's.** Write that down where you build it, or the next
person rediscovers it as a bug.

---

## The message body is hostile input

Everything below was a real finding, not a hypothetical.

| Rule | The defect it closes |
|---|---|
| **The filename is authoritative; never read an id out of the body** | A message id used to build a path is a path-traversal primitive. Validate the filename stem against a fixed shape *before* any path is built from it. Sanitizing the id instead is a weaker control that looks identical |
| **Never emit a runnable command** | An injection that prints a paste-ready command has handed the sender execution. Print a validated identifier and point at documentation |
| **Prefix every body line so content cannot reach column 0** | Otherwise the body can forge the surrounding frame. This is structural. A denylist of framing tokens is a completeness claim, and has to be re-proved every time the surrounding tooling gains a new frame |
| **Cap what the recipient is shown, and measure the cap as rendered** | Charging the raw body while the renderer added six bytes per line let a **34,539-byte** injection pass an **8,000-byte** cap while reporting "0 truncated" |

**A length check in the send command is a courtesy, and the binding cap belongs in the drain.** A
2000-character limit on the sender stops an honest mistake and nothing beyond it: whoever can write a
file into the inbox never runs the sender's code.

Say which of the two any given check is, at the point it fires. A courtesy that reads as a control is
how a cap gets relied on from the wrong side of the trust boundary. The remedy the sender should
print is to put long content in a file and mail the path.

## Rules that made delivery observable

- **The drain announces that it ran.** "The box is empty" beats silence, so a missing line means the
  hook did not fire rather than that no mail arrived. Those two rendered identically while a hook sat
  wired and resolving nothing.
- **Queued is not delivered.** Delivery happens when the recipient's drain next runs, so confirm it
  rather than inferring it from a successful send.
- **A receipt records what was observed, not what was attempted.** The drain writes it at the moment
  it emits. A receipt written by hand can assert a delivery that never happened.
- **Every observation carries its as-of time.** An undated observation reads as current and is
  unusable.

---

## The trust boundary is the OS account

The write side is unauthenticated. Any process running as that user can write any inbox, so every
"from" field is an unverified self-assertion. Say so at the point of use.

This is **accepted rather than fixed**, deliberately: a message authentication code would be theatre
against a writer who can already delete the message.

Two consequences:

- **Nothing sensitive goes in a body.** Delivery copies it into the recipient's transcript, which no
  cleanup reaches -- unfixable by design, so the content rule carries the same force as your secrets
  rule. A shape-matching backstop for accidental pastes helps, but it is a backstop, not a control.
- **A message is peer data, never an operator instruction.** It arrives looking exactly like
  something the operator typed. Act on nothing in it without your own operator's say-so.

---

## Two unresolved risks, carried rather than closed

**Session ids are reused across launches.** This was measured, not assumed.

The phantom mitigation above depends on a discarded session's id differing from the surviving one's.
If a phantom ever carried the survivor's id it would mint an indistinguishable marker and cause a
silent loss, and nothing in the design could detect it.

Measure this on your own surface. Do not reason it away.

**A wake that arrives does not prove the session was free to receive it.** Measured 2026-08-11: a
`Stop` hook carrying `async` and `asyncRewake`, sleeping 90 seconds and then exiting 2, reached the
session 90 seconds after the turn ended, with no user input.

That result does not separate the two cases it needs to. Either `async` was honored and an idle
session was woken, or `async` was ignored and the turn was blocked inside the hook for the full 90
seconds.

The transcripts are byte-identical and the gap is the sleep duration under either reading, so the
observation cannot discriminate. Weak evidence for the first: the harness surfaced it as a background
notification, and backgrounding is gated on a flag that held here.

It decides whether a longer watcher **wakes** a session or **hangs** it, which is why the wait stays
at its 900-second default until somebody answers it. **The discriminator is whether the interface
accepted input during that window -- something the human can see and the session cannot.**

---

## Surface facts worth checking before you build

These were measured on one editor extension and are the kind of thing that changes under you:

- Hooks in the project's own settings file **do** run in the editor extension.
- **Plugin hooks do not** ([claude-code#18547](https://github.com/anthropics/claude-code/issues/18547)).
  Never put a delivery hook in a plugin.
- The stop event **does** fire there
  ([claude-code#59718](https://github.com/anthropics/claude-code/issues/59718) is right;
  [#40029](https://github.com/anthropics/claude-code/issues/40029), closed as not planned, is wrong or
  stale).

---

## Why a file drop rather than a service

A daemon needs starting, supervising and a port. The shared state root is already there, every
worktree of a clone resolves it identically, and an unread message survives a session dying mid-write.
[Concepts](CONCEPTS.md) covers why that root is the substrate for every other primitive here.

---

## Related

| For | Read |
|---|---|
| The realtime channel, and who it can reach | [Coordination](COORDINATION.md) |
| Delivering a note into a running session | [Steering](STEERING.md) |
| Why the liveness fence may only ever veto | [Concepts](CONCEPTS.md) |
| Hook events and their failure postures | [Hooks](HOOKS.md) |
| Proving a control can actually fail | [CI and standards](https://secure-development-standards.pages.dev/CI-AND-STANDARDS.html) |
