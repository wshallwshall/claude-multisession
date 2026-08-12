# Running multiple sessions

## TLDR/BLUF

**What this is.** The entry point to running more than one Claude Code session in one repository.
Three things live here and nowhere else: **which surface to run the sessions on**, **the channels
sessions have for reaching each other**, and **using one session as a coordinator**.

**Why you should care.** Concurrency buys real parallelism and a specific set of failures, nearly
all invisible while they happen. Four preparations work only *before* the second session starts,
because each takes effect in sessions started afterwards. Not for you if you run one session at a
time.

**How to use it.** Read [Concepts](CONCEPTS.md) first, then work the numbered list below in order.
Everything else on this page names a problem and links to the page that owns the fix.

---

More than one Claude Code session in one repository at the same time buys real parallelism and
creates a specific set of failures, nearly all of which are invisible while they happen.

Three things live here and nowhere else: **which surface to run the sessions on**, **the channels
sessions have for reaching each other**, and **using one session as a coordinator**. Everything else
names the problem and links to the page that owns the fix.

Read [Concepts](CONCEPTS.md) first. A worktree per session, one shared state root every worktree of a
clone resolves identically, and a liveness fence that may only veto: every page below applies those
three ideas.

**Before the second session starts.** At least these four, and the last two are only effective if you
do them *first* -- each takes effect in sessions started afterwards, so doing it in response to the
problem is doing it too late.

1. Pick the surface, deliberately -- see [below](#which-surface-to-run-several-sessions-on).
2. Give each session its own worktree, cut from a freshly fetched remote tip
   ([Worktrees](WORKTREES.md)).
3. Install the gates into **every** config root the client uses, then verify with the three commands
   in the surface section
   ([INSTALL.md](https://claude-multisession.pages.dev/INSTALL.md),
   [Hooks](HOOKS.md)).
4. Wire the steering hook now if you will ever want it, because it only takes effect in sessions
   started after it was wired ([Steering](STEERING.md)).

---

## The problems, and which page owns each

At least these, ordered roughly by when they bite. The fix lives on the page in the right-hand
column, and only there.

| The problem | What it looks like | Owned by |
|---|---|---|
| Two sessions share one working tree | Both edit the same files, and each believes it owns the directory. | [Worktrees](WORKTREES.md) -- one worktree per session, cut from a freshly fetched remote tip |
| A session runs a checkout inside another session's checkout | Every file under the other session swaps to a different commit's content, mid-task, with nothing on either screen saying so. | [Worktrees](WORKTREES.md) for the repair path and the rule; [Hooks](HOOKS.md) for the refusal that stops the tree-swapping verb in the first place |
| The shared primary checkout drifts onto someone else's branch | A peer put it there, or the harness's own auto-worktree half-failed and left a ghost stub. | [Worktrees](WORKTREES.md) -- `restore-primary.ps1`, and the SessionStart backstop whose dirty-tree refusal is its only safety property |
| Your tests pass against code you are not editing | A shared editable install binds every worktree to whichever checkout was installed last. | [Worktrees](WORKTREES.md) -- one dependency environment per worktree, built inside it from the lockfile |
| Two sessions edit the same file in parallel | Found at merge, after both built on divergent assumptions. | [Coordination](COORDINATION.md) -- overlap for the pull direction, the collision gate for the refusal |
| Two sessions build the **same thing** in **different files** | Zero conflicts, two green pull requests, one thrown away. This is the residual no gate can compute: announce and claims are both best-effort. | [Coordination](COORDINATION.md) |
| Two sessions reach for the same next number in a shared sequence | Two records numbered `0004`. Git merges both cleanly and nothing in the graph can see it. | [Sequence allocation](SEQUENCE-ALLOC.md) -- atomic allocation plus a commit-time gate; neither half suffices alone, and no installer wires the commit-time half |
| A session is a long way into the wrong approach | Typing at its prompt only queues your message for after the turn. | [Steering](STEERING.md) -- a note delivered at the target session's next tool call |
| A peer cannot be reached at all | An editor-extension session, or one under a different login, is invisible to the realtime channel. | [Session mail](SESSION-MAIL.md) -- designed and documented there, **not shipped** |
| Two sessions write the same last-write-wins state outside git | Project memory, a shared note, a ledger. One write vanishes with no error anywhere. | **No shipped mechanism.** Named in [Worktrees](WORKTREES.md) and [Concepts](CONCEPTS.md) as something a worktree does not isolate; the remedy is single-writer convention. An accepted residual -- see [coordinator](#using-a-coordinator-session). |
| Several branches all have to land in one trunk | "Can't merge" is four different states with three different fixes. | [PRs and merges](PR-AND-MERGE.md) -- read the state before touching the branch; it also owns what squash-merge does to reachability |
| Cleanup deletes a worktree a session is still working in | Or it half-fails, stranding commits in no ref and no reflog. | [Pruning](PRUNING.md) -- merged AND clean AND NOT occupied, two occupancy signals either of which may veto, and an orphan ledger |
| Everything is green and you cannot tell whether any of it is running | Every failure mode here is byte-identical to success. | [Hooks](HOOKS.md) for the event map and each control's posture; the instrument is `bin/ccx-doctor.ps1`; [the drift audit](CASE-STUDY-drift-audit.md) for the method |

---

## Which surface to run several sessions on

> **This is operating experience, dated 2026-08-06. It is not a benchmark.** Several sessions at once
> are run on the **Claude Code desktop app**. Running several at once in the **VS Code extension** has
> run into worktree hijacking. Nothing in this repository measures a hijack rate per surface, so treat
> this as one operator's result on one setup. If your own result differs, yours is the better data.

The preference is worth stating only because the mechanisms under it are each checkable. Each bullet
says what class of evidence it rests on, because they are not the same class:

- *Cited upstream, not reproduced here.* **The hijack is harness-side, and nothing here ties it to a
  surface.** A per-session auto-worktree can half-fail on Windows, flipping the *primary's* HEAD
  onto the session's branch
  ([claude-code#76590](https://github.com/anthropics/claude-code/issues/76590)).

  This repository cites that issue rather than reproducing it, and records no observation of the
  extension's worktree layout either way. Read the bullet as removing an easy assumption, not as
  establishing that the defect is surface-neutral.
- *Measured here.* **An extension session is absent from the desktop app's own `list_sessions`.** It
  enumerates only sessions that app spawned; an extension session is never registered, not filtered
  out. Verified on a live extension session sharing the **default** config root: not a login split.
- *Measured here.* **Project-scoped settings are commonly git-ignored and cannot reach a new
  worktree.** A large share of this repo's worktrees had no project settings file, and a live
  editor session was working in one with **zero** coordination context. So the hooks here install
  at **user** scope.
- *Observed once.* **User scope means *per config root*, and the gate fails open**, so an unwired root
  is byte-identical to a governed one from inside the session.

  This is the only bullet tied to an observed hijack. A session under an ungoverned config root
  checked its own branch out inside another session's linked worktree, and the gate that would have
  refused it was not installed there.

  Editor-hosted chats under an extra config root are the installers' stated reason for wiring every
  root ([INSTALL.md](https://claude-multisession.pages.dev/INSTALL.md)), and it is the configuration
  that hijack came from. Nothing here counts roots by surface: rationale, not a measured
  distribution.

**What is not established.** The intuitive story -- an extension session is invisible to
`list_sessions`, so anything reading that list acts as though it is gone -- does not hold here.

The worktree gate reads no session list. It keys on a write's target path and on what git reports
about the tree a command acts on ([Hooks](HOOKS.md)).

The reaper and the presence roster read the on-disk per-session registry, which carries every
surface, so an extension session is **not** invisible to the thing that deletes worktrees
([Pruning](PRUNING.md)). `list_sessions` blindness costs messageability, not tree protection.

The observed hijack came from an editor-hosted session under an ungoverned config root, and no
measurement here separates the surface from the ungoverned root as the operative fact.

**And one join is unverified, the one this argument leans on hardest.** What was measured: hooks in
a project's *own settings file* run in the extension ([Session mail](SESSION-MAIL.md)). Every
installer here writes **user** scope, and nothing measures whether a user-scope hook fires there at
all.

**So check it on your own setup rather than taking the preference on trust.** From a session started
the way you intend to run them:

```powershell
pwsh -NoProfile -File scripts/coord/presence.ps1                 # does the roster carry this session?
pwsh -NoProfile -File bin/ccx-doctor.ps1                         # are the gates live for THIS repo, by attack?
pwsh -NoProfile -File scripts/worktree/install-gate.ps1 -Status  # wired, and current, in EVERY config root?
```

A gate wired and current in every config root addresses the one mechanism this repository can name.
That is not proof it *fires* on your surface: `-Status` answers "is it wired", not "does it fire".
`ccx-doctor.ps1` attacks each control rather than reading config; trust it, not the wiring report.

**The surface choice reduces a residual; it does not replace the gate.** A hijack the gate refuses is
a message on your screen; a hijack on a surface where the gate was never installed is silent.

---

## How sessions talk to each other

Almost every signal a session can *send* is **pull**: it sits there until somebody looks. One channel
pushes from one session to another. Three more are delivered to a session that never looked, two of
them by the harness rather than by a peer, and several reach only sessions that have not started.

**Timing decides whether a message is useful at all**, so the table is sorted by it rather than by
tool. A note that lands when a session next *starts* is a different instrument from one that
interrupts it between tool calls, and choosing wrong lands the message after the decision. Five
bands:

- **A** -- already running, mid-turn.
- **B** -- a running peer, if it is in the desktop roster.
- **C** -- anyone who looks, whenever they look, including sessions that start later.
- **D** -- at commit: after the work, before it lands.
- **E** -- only a session that starts later; never a running one.

At least these channels exist. Each links to the page that owns it.

| Channel | Reaches whom, and when | Push or pull | Shipped here |
|---|---|---|---|
| [Steering note](STEERING.md) | **A** -- a **busy** session, at its next tool call. The only channel that interrupts a turn in progress. | addressed to one worktree | yes, opt-in per worktree; nothing wires it |
| [Collision gate](COORDINATION.md) | **A** -- a **busy** session, at the tool call: while the outcome can still change. | addressed to whoever attempts the edit; delivered by the harness, not a peer | yes |
| [Kill-switch files](COORDINATION.md) | **A** -- sessions already running, because the hook re-reads the file on every run. | broadcast, one bit | yes |
| [Announce](COORDINATION.md) | **B** -- a peer already running **and** in the desktop session list. Not an extension session, not another login. | addressed; one note per peer, same content to each | yes; delivery needs a desktop-only server |
| [Claims](COORDINATION.md) | **C** -- anyone who looks; also surfaced to joining sessions in preference to the worktree name. | broadcast to a place, not sent to anyone | yes |
| [Overlap](COORDINATION.md) | **C** -- you, about live peers, at the moment you ask. | pull; nobody sends | yes |
| [Presence and occupancy](COORDINATION.md) | **C** -- you, about who is live and where, right now. | pull | yes |
| [Locks](COORDINATION.md) | **C** -- whichever session attempts the same operation, as it attempts it. | broadcast; the file's existence is the signal | yes (a library -- dot-source it) |
| [Sequence allocation](SEQUENCE-ALLOC.md) | **C** -- every session, present and future, when it asks for a number. | broadcast to a shared registry | the allocator, yes; **no installer writes the `pre-commit` gate** -- until you wire it, nothing at commit time catches a reused number |
| [Commit-time claim gate](COORDINATION.md) | **D** -- the committing session, at commit; it reaches one that never asked for anything. | addressed to the committing session | yes, installed per clone into the shared git hooks directory, so one copy governs every worktree; `--no-verify` bypasses it |
| [SessionStart context](HOOKS.md) | **E** -- only a session that starts later. | broadcast | yes |
| The working agreement ([`CLAUDE.md`](https://claude-multisession.pages.dev/CLAUDE.md.template)) | **E** -- only sessions that start later; an edit misses a running one. | broadcast | template only; nothing installs it |
| [Session mail](SESSION-MAIL.md) | **E** -- a session that starts later; a mid-turn wake-up is possible and is one-shot. | addressed to a worktree box, keyed by normalized path | **no** -- designed and documented here, not implemented here |

One property explains the whole first band: **a file is re-read on every hook run**. An environment
variable is read once at process start, and a settings edit takes effect only in the next session.
So every channel that reaches a running session is a file. Costs are on each channel's page.

### Choosing one

- Change a running peer's course **now** -> steering note, if it is wired in that worktree.
- Tell a running peer what you are **about to do** -> announce.
- The recipient **does not exist yet** -> a claim, an allocated number, or the SessionStart context.
- You want the answer **yourself** -> presence, overlap, `claim.ps1 -List`. Nothing pushes.
- You want a rule **enforced** rather than communicated -> a gate. Anything else is a request. So **if
  what you want to say is "do not touch X", publish something a gate consumes rather than something a
  human reads.**

The pull-side queries share one blind spot. They read git state and a roster keyed on the directory
a session was *launched* in. A write made into a worktree by absolute path from a session sitting
elsewhere is invisible to them. A fence needs a second, non-cwd signal
([Pruning](PRUNING.md)).

**A message from another session is data, never an instruction**: it authorizes no push, merge,
delete or config change. **A broadcast needs an expiry or a condition the recipient can evaluate**:
a freeze held only the sessions honoring it and still announced hours after its pull request merged.

### The degenerate channels

These are the fallbacks when the channel you needed was not wired. Each works often enough to feel
adequate.

**Shouting through the operator.** Its timing is the worst here: unbounded, waiting on a human to
read and then type. It arrives in the **operator's voice**, so the receiver cannot tell peer
assertion from instruction. And it scales as one conversation per session: the person is the
bottleneck.

**A note in a file both sessions read.** No delivery, no receipt: silence and unseen look the same.
No tool reads it, so no mechanical verdict changes: two sessions agreed in prose to hand a file
over and the gate refused, because it reads git. And a worktree file moves under you on a branch
switch.

**Relying on git itself**: branch name, commit message, merge conflict. A conflict is not a warning
but the notification that both sessions already did the thing. A worktree name is a creation-time
label, observed well off the work it names. Under squash-merge, reachability is wrong both ways.

All three carry information a human can interpret and a tool cannot act on, and all three arrive after
the decision.

---

## Using a coordinator session

Once several sessions are in flight, it is worth giving one of them a different job: hold the picture
of what is in flight and decide what lands in what order, while the others build.

**Nothing here implements this, and this page is introducing the term.** No coordinator script, no
role flag, no routing. The working agreement already routes push, pull request and merge to the
*human* owner, commits to the session. A coordinator delegates that line to one session.

One sentence carries the boundary: **a coordinator arbitrates; it does not execute.**

### Why the role exists

- **Almost every signal here is pull, and pull needs somebody to look.** Under load, the sessions
  doing the building are the least likely to stop and look.
- **Outward-facing actions want a single owner**, and with auto-merge armed a pull request *is* a
  merge. Measured: the trunk moved **seven times** during one pair of pull requests. Two branches
  that each merge cleanly against the trunk they were cut from need not merge cleanly in either
  order.
- **Some shared state is last-write-wins and outside git** -- project memory, shared notes, a ledger.
  The rule there is single-writer, and single-writer needs a writer.

### What routes through it, and what does not

At least these, and the two catch-all rows at the bottom are the rule the rest are instances of.

| Routes through the coordinator | Does **not** route through it |
|---|---|
| Pushing a branch to the remote | **Committing** -- the worker's own judgment, at logical stops, one layer each. A coordinator asked before a commit is a queue. |
| Opening a pull request | Editing, running tests, iterating on its own branch |
| Merging, and arming or disarming auto-merge | Creating its own worktree -- already serialized by a mutex |
| The **order** decision: which of two branches on the same ground lands first, and who re-syncs after | **Allocating a sequence number** |
| Which of two overlapping **efforts** continues, and which stops | **Taking a claim** |
| Writes to any shared last-write-wins state outside git | Taking a lock |
| Anything whose answer must be identical for every session and no gate can compute | Any read-only query |

**Allocation is atomic**: the failed exclusive create *is* the mutual exclusion, so a coordinator
handing out numbers is the read-modify-write that loses. **A claim is keyed to the working tree**,
so a coordinator claiming for a worker gets that worker's own commit refused by the commit-time
gate.

The generalization: **if a machine can serialize it, do not put a session in the loop.** Serialization
is a primitive; single-ownership is a judgment; conflating them produces the queue.

### The route is absolute, and the authority is not transferable

Writing "push, pull request and merge stay with the coordinator" as one flat rule collapses two rules
that fail in different directions.

**The route is absolute.** Every remote operation goes through the coordinator whenever one is
running, and a session can adopt that on sight.

**The grant is not, and no coordinator can hand it on.** It came from the human owner, in words, in
one session. A successor inherits the route and not the grant, so a role that exists is not a role
that has been authorized.

The fallback runs to the owner rather than downward. With no coordinator running, a remote operation
goes to the **owner**, never to whichever worker happens to be holding the branch. **A worker that
cannot reach a coordinator is blocked, not promoted.**

**An override has to name the route it overrides.** "Yes", "go ahead" and "use your best judgment"
are not overrides, and the reply a bare approval earns is a question about which route it meant.

### How a worker talks to it

Publish intent where a **tool** can read it: take a claim with a note before starting, and announce
carries that note to joining sessions. The coordinator **reads state rather than being told it**.
Ready-to-land needs no channel: the pushed branch, or a refreshed claim note, is the signal.

### When you do not need one

The trigger is a condition, not a headcount: **order-dependence** and **effort-overlap**. Three
sessions on unrelated subsystems need no coordinator; two on branches that both rewrite one index
file do. Unrelated work in separate worktrees is covered by the shipped gates; a coordinator adds a
hop.

### How the role fails

- **Bottleneck.** If a worker must ask before it can commit, you have built a queue. An explicit
  claim tool sat here and was used exactly **zero** times: a coordination step you must remember is
  one you will skip. A coordinator that says wait when it needn't destroys the channel it depends
  on.
- **A worker bypasses it** -- assume it. Claims are advisory and the push guard is a guardrail, not a
  boundary, so the role sits **behind** enforcing gates rather than instead of them: a coordinator
  that is the only control is not a control.
- **Stale state, in two symmetric directions.** A broadcast that never lapses: a freeze note still
  announced itself long after its pull request merged. Its mirror: a claim was reported stale while
  its holder was committing minutes earlier. Report what the holder is doing, not how old the record
  is.
- **Phrasing a ruling as restraint.** "Do not merge" does not reach armed auto-merge; nobody has to
  click anything for those to land. "Disarm auto-merge on your pull request" does.
- **Authority confusion.** A coordinator's message is still peer data. Being central is not being
  authorized.
- **State that lives only in one context.** Whatever it decides must end up in a claim, a number, a
  branch or a gate; a cleared context takes the rest with it.
- **It inherits the timing table.** It reaches a busy worker only through the steering note -- opt-in
  per worktree, and effective only in sessions started after it was wired.

---

## Related

| For | Read |
|---|---|
| The model everything here applies | [Concepts](CONCEPTS.md) |
| Creating, rescuing, restoring and removing checkouts | [Worktrees](WORKTREES.md) |
| Presence, overlap, claims, locks and announce | [Coordination](COORDINATION.md) |
| Reaching a session that is already mid-task | [Steering](STEERING.md) |
| Reaching a peer the realtime channel cannot see | [Session mail](SESSION-MAIL.md) |
| The collision class git cannot see | [Sequence allocation](SEQUENCE-ALLOC.md) |
| Landing several branches in one trunk | [PRs and merges](PR-AND-MERGE.md) |
| Removing worktrees without destroying a session | [Pruning](PRUNING.md) |
| Every control mapped to its event and its failure posture | [Hooks](HOOKS.md) |
| The things that bite, in the order they bite | [Tips and tricks](TIPS-AND-TRICKS.md) |
| Proving the controls are actually running | [Drift audit case study](CASE-STUDY-drift-audit.md) |
