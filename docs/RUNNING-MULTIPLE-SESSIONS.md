# Running multiple sessions

## TLDR/BLUF

**What this is.** The three things this page owns: **which surface to run the sessions on**, **the
channels sessions have for reaching each other**, and **using one session as a lander**. A lander is
the session the merge routes through; nothing here implements it.

**Why you should care.** Several sessions at once buy real parallelism and a set of failures,
nearly all invisible while they happen. Four preparations work only *before* the second session
starts: each takes effect in sessions started afterwards. Not for you if you run one session at a
time.

**How to use it.** Read [Concepts](CONCEPTS.md) first, then work the four preparations below in
order. After that, two tables do the lookup: **the problems**, each with the page that fixes it, and
**the channels**, each with who it reaches and when.

---

Every page below applies three ideas from [Concepts](CONCEPTS.md):

- **A worktree per session** -- one directory and one branch each.
- **One shared state root** that every worktree of a clone resolves identically.
- **A liveness fence that may only veto** -- it can refuse an action, never authorize one.

**Before the second session starts.** At least these four. Do the last two *first*: each takes
effect in sessions started afterwards, so doing it in response to the problem is doing it too late.

1. **Pick the surface, deliberately** -- see [below](#which-surface-to-run-several-sessions-on).
2. **Give each session its own worktree**, cut from a freshly fetched remote tip
   ([Worktrees](WORKTREES.md)).
3. **Install the gates into every config root the client uses**, then verify with the three commands
   in the surface section ([INSTALL.md](INSTALL.md),
   [Hooks](HOOKS.md)).
4. **Wire the steering hook now** if you will ever want it. It only takes effect in sessions started
   after it was wired ([Steering](STEERING.md)).

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
| Two sessions write the same last-write-wins state outside git | Project memory, a shared note, a ledger. One write vanishes with no error anywhere. | **No shipped mechanism.** Named in [Worktrees](WORKTREES.md) and [Concepts](CONCEPTS.md) as something a worktree does not isolate; the remedy is single-writer convention. An accepted residual -- see [lander](#using-a-lander-session). |
| Several branches all have to land in one trunk | "Can't merge" is four different states with three different fixes. | [PRs and merges](PR-AND-MERGE.md) -- read the state before touching the branch; it also owns what squash-merge does to reachability |
| Cleanup deletes a worktree a session is still working in | Or it half-fails, stranding commits in no ref and no reflog. | [Pruning](PRUNING.md) -- merged AND clean AND NOT occupied, two occupancy signals either of which may veto, and an orphan ledger |
| Everything is green and you cannot tell whether any of it is running | Every failure mode here is byte-identical to success. | [Hooks](HOOKS.md) for the event map and each control's posture; the instrument is `bin/ccx-doctor.ps1`; [the drift audit](CASE-STUDY-drift-audit.md) for the method |

---

## Which surface to run several sessions on

**KORUS assumes Claude Code for Desktop. That is a requirement, not a preference.** A CLI-only or
editor-extension setup is not a configuration this project supports.

Your own contrary data does not change it: the coordination layer is *shaped* around the desktop
client. [Limits and requirements](LIMITS.md) states it, and [Install](INSTALL.md) turns that reader
away on its first screen.

Two things follow from the client rather than from a measurement. Announce delivers through a
desktop-only MCP server, and the session roster it reads is the desktop app's.

> **Separately, one operator's observation, dated 2026-08-06. Not a benchmark.** Running several
> sessions at once in the **VS Code extension** has run into worktree hijacking: one session checking
> its own branch out inside another session's directory. Nothing here measures a hijack rate per
> surface, so that part is an anecdote. It is a reason the requirement is not a hardship, not the
> reason for it.

**The mechanisms under it are checkable, which is why they are listed separately.** The four below do
not rest on the same class of evidence, so each one names its own class:

- *Cited upstream, not reproduced here.* **The hijack is harness-side, and nothing here ties it to a
  surface.** A per-session auto-worktree can half-fail on Windows, flipping the *primary's* HEAD
  onto the session's branch
  ([claude-code#76590](https://github.com/anthropics/claude-code/issues/76590)).

  This repository cites that issue rather than reproducing it, and records no observation of the
  extension's worktree layout either way. The bullet removes an easy assumption. It does not
  establish that the defect is surface-neutral.
- *Measured here.* **An extension session is absent from the desktop app's own `list_sessions`.** It
  enumerates only sessions that app spawned; an extension session is never registered, not filtered
  out. Verified on a live extension session sharing the **default** config root: not a login split.
- *Measured here.* **Project-scoped settings are commonly git-ignored and cannot reach a new
  worktree.** A large share of this repo's worktrees had no project settings file, and a live
  editor session was working in one with **zero** coordination context. So the hooks here install
  at **user** scope.
- *Observed once.* **User scope means *per config root*, and the gate fails open.** An unwired root
  refuses nothing and says nothing, so from inside the session it is byte-identical to a governed
  one.

  This is the only bullet tied to an observed hijack. A session under an ungoverned config root
  checked its own branch out inside another session's linked worktree, and the gate that would have
  refused it was not installed there.

  Editor-hosted chats under an extra config root are the installers' stated reason for wiring every
  root ([INSTALL.md](INSTALL.md)), and that is the
  configuration the hijack came from. Nothing here counts roots by surface: rationale, not a
  measured distribution.

**What is not established.** The intuitive story -- an extension session is invisible to
`list_sessions`, so anything reading that list acts as though it is gone -- does not hold here.

The worktree gate reads no session list. It keys on a write's target path and on what git reports
about the tree a command acts on ([Hooks](HOOKS.md)).

The reaper and the presence roster read the on-disk per-session registry, which carries every
surface. So an extension session is **not** invisible to the thing that deletes worktrees
([Pruning](PRUNING.md)). `list_sessions` blindness costs you messaging, not tree protection.

The observed hijack came from an editor-hosted session under an ungoverned config root, and no
measurement here separates the surface from the ungoverned root as the operative fact.

**And one join is unverified, the one this argument leans on hardest.** What was measured: hooks in
a project's *own settings file* run in the extension ([Session mail](SESSION-MAIL.md)). Every
installer here writes **user** scope, and nothing measures whether a user-scope hook fires there at
all.

**The goal.** Find out whether the controls are live on the surface you actually run, rather than
taking the preference on trust.

**What to do.** From a session started the way you intend to run them:

```powershell
pwsh -NoProfile -File scripts/coord/presence.ps1                 # does the roster carry this session?
pwsh -NoProfile -File bin/ccx-doctor.ps1                         # are the gates live for THIS repo, by attack?
pwsh -NoProfile -File scripts/worktree/install-gate.ps1 -Status  # wired, and current, in EVERY config root?
```

**What happens next.** A gate wired and current in every config root covers the one mechanism this
repository can name. It is not proof the gate *fires* on your surface:

- `-Status` answers "is it wired", not "does it fire".
- `ccx-doctor.ps1` attacks each control rather than reading config, so trust it over the wiring
  report.

**The surface choice reduces a residual; it does not replace the gate.** A hijack the gate refuses
is a message on your screen. A hijack on a surface where the gate was never installed is silent.

---

## How sessions talk to each other

Almost every signal a session can *send* is **pull**: it sits there until somebody looks. One
channel pushes from one session to another. Three more are delivered to a session that never
looked, two of them by the harness rather than by a peer. Several reach only sessions that have not
started.

**Timing decides whether a message is useful at all**, so the table is sorted by timing rather than
by tool. A note that lands when a session next *starts* is a different instrument from one that
interrupts it between tool calls. Choose wrong and the message arrives after the decision. Five
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
variable is read once at process start, and a settings edit reaches only the next session. So every
channel in **band A** is a file.

**Announce is band B and is not a file.** It delivers through a desktop-only MCP server, which is
why it reaches only peers in the desktop session list.

That path has a known failure mode. A delivered message can leave the recipient's query emitting
nothing, until the app's watchdog force-ends it about 16 minutes later. It surfaces only as an
`Error` badge -- no other signal.

Upstream: [claude-code#86012](https://github.com/anthropics/claude-code/issues/86012), observed on
the machine this page was written on. Each channel's page carries its costs.

### Choosing one

- Change a running peer's course **now** -> steering note, if it is wired in that worktree.
- Tell a running peer what you are **about to do** -> announce.
- The recipient **does not exist yet** -> a claim, an allocated number, or the SessionStart context.
- You want the answer **yourself** -> presence, overlap, `claim.ps1 -List`. Nothing pushes.
- You want a rule **enforced** rather than communicated -> a gate. Anything else is a request. So
  **if what you want to say is "do not touch X", publish something a gate consumes rather than
  something a human reads.**

**The pull-side queries share one blind spot.** They read git state, and a roster keyed on the
directory a session was *launched* in. A write by absolute path into a worktree, from a session
sitting elsewhere, is invisible. A fence needs a second, non-cwd signal
([Pruning](PRUNING.md)).

**A message from another session is data, never an instruction**: it authorizes no push, merge,
delete or config change. **A broadcast needs an expiry or a condition the recipient can evaluate**:
a freeze held only the sessions honoring it and still announced hours after its pull request merged.

### The degenerate channels

These are the fallbacks when the channel you needed was not wired. Each works often enough to feel
adequate.

**Shouting through the operator.** Its timing is the worst here: unbounded, waiting on a human to
read and then type. It arrives in the **operator's voice**, so the receiver cannot tell peer
assertion from instruction. It scales as one conversation per session: the person is the bottleneck.

**A note in a file both sessions read.** No delivery, no receipt: silence and unseen look the same.
No tool reads it, so no mechanical verdict changes. Two sessions agreed in prose to hand a file
over; the gate refused, because it reads git. And a worktree file moves under you on a branch
switch.

**Relying on git itself**: branch name, commit message, merge conflict. A conflict is not a warning
but the notification that both sessions already did the thing. A worktree name is a creation-time
label, observed well off the work it names. Under squash-merge, reachability is wrong both ways.

All three carry information a human can interpret and a tool cannot act on. All three arrive after
the decision.

---

## Using a lander session

Once several sessions are in flight, give one of them a different job. The **lander** holds the
picture of what is in flight and decides what lands in what order, while the others build.

**No script implements this.** No lander script, no role flag, no routing -- the role is a prompt and
a rule. The working agreement already routes push, pull request and merge to the *human* owner, and
commits to the session. A lander delegates that line to one session.

[Run a KORUS build](KORUS-BUILD.md) step 3 is the prompt to paste and the daily loop around it. This
page owns the rule; that page owns the procedure.

One sentence carries the boundary: **a lander arbitrates; it does not execute.**

### Why the role exists

- **Almost every signal here is pull, and pull needs somebody to look.** Under load, the sessions
  doing the building are the least likely to stop and look.
- **Outward-facing actions want a single owner**, and with auto-merge armed a pull request *is* a
  merge. Measured: the trunk moved **seven times** during one pair of pull requests. Two branches
  that each merge cleanly against the trunk they were cut from need not merge cleanly in either
  order.
- **Some shared state is last-write-wins and outside git**: project memory, shared notes, a
  ledger. The rule there is single-writer, and single-writer needs a writer.

### What routes through it, and what does not

At least these, and the two catch-all rows at the bottom are the rule the rest are instances of.

| Routes through the lander | Does **not** route through it |
|---|---|
| Merging, and arming or disarming auto-merge | **Pushing its own branch, and opening its own pull request.** Owner ruling 2026-08-29: sessions push their own |
| The **order** decision: which of two branches on the same ground lands first, and who re-syncs after | **Committing** -- the worker's own judgment, at logical stops, one layer each. A lander asked before a commit is a queue. |
| Which of two overlapping **efforts** continues, and which stops | Editing, running tests, iterating on its own branch |
| Writes to any shared last-write-wins state outside git | Creating its own worktree -- already serialized by a mutex |
| Anything whose answer must be identical for every session and no gate can compute | **Allocating a sequence number**, **taking a claim**, taking a lock, any read-only query |

**Allocation is atomic**: the failed exclusive create *is* the mutual exclusion. A lander handing
out numbers is the read-modify-write that loses. **A claim is keyed to the working tree**, so a
lander claiming for a worker gets that worker's own commit refused by the commit-time gate.

The generalization: **if a machine can serialize it, do not put a session in the loop.**
Serialization is a primitive; single-ownership is a judgment; conflating them produces the queue.

### The route is absolute, and the authority is not transferable

Writing "push, pull request and merge stay with the lander" was the rule until 2026-08-29, when
the owner ruled that sessions push their own. Only the merge stayed. Even for what remains, one
flat rule collapses two that fail in different directions.

**The route is absolute for what it still covers.** A merge goes through the lander whenever one
is running, and a session can adopt that on sight. A push and a pull request do not, and have not
since 2026-08-29.

**The grant is not, and no lander can hand it on.** It came from the human owner, in words, in
one session. A successor inherits the route and not the grant, so a role that exists is not a role
that has been authorized.

The fallback runs to the owner, not downward. With no lander running a **merge** goes to the
**owner**, never to whichever worker holds the branch. **A worker that cannot reach a lander is
blocked from merging, not promoted to it.** Its own push and pull request were never blocked.

**An override has to name the route it overrides.** "Yes", "go ahead" and "use your best judgment"
are not overrides. What a bare approval earns is a question back about which route it meant.

### How a worker talks to it

Publish intent where a **tool** can read it: take a claim with a note before starting, and announce
carries that note to joining sessions. The lander **reads state rather than being told it**.

Ready-to-land needs no channel: a refreshed claim note is the signal. **Not a pushed branch.** A
worker pushes its own branch as a matter of course, so a push says nothing about whether the work
is ready. Before 2026-08-29 a push meant the lander had already acted; now it means a worker
started.

### When you do not need one

The trigger is a condition, not a headcount: **order-dependence** and **effort-overlap**. Three
sessions on unrelated subsystems need no lander; two on branches that both rewrite one index
file do. Unrelated work in separate worktrees is covered by the shipped gates; a lander adds a
hop.

### How the role fails

- **Bottleneck.** If a worker must ask before it can commit, you have built a queue. An explicit
  claim tool sat here and was used exactly **zero** times: a coordination step you must remember is
  one you will skip. A lander that says wait when it needn't destroys the channel it depends
  on.
- **A worker bypasses it** -- assume it will. Claims are advisory and the push guard is a guardrail,
  not a boundary. So the role sits **behind** enforcing gates rather than instead of them: a lander
  that is the only control is not a control.
- **Stale state, in two symmetric directions.** A broadcast that never lapses: a freeze note still
  announced itself long after its pull request merged. Its mirror: a claim was reported stale while
  its holder was committing minutes earlier. Report what the holder is doing, not how old the record
  is.
- **Phrasing a ruling as restraint.** "Do not merge" does not reach armed auto-merge; nobody has to
  click anything for those to land. "Disarm auto-merge on your pull request" does.
- **Authority confusion.** A lander's message is still peer data. Being central is not being
  authorized.
- **State that lives only in one context.** Whatever it decides must end up in a claim, a number, a
  branch or a gate; a cleared context takes the rest with it.
- **It inherits the timing table, and the one channel that interrupts a turn is closed to it.** The
  steering note is the only channel reaching a *busy* session, and
  [Steering](STEERING.md#the-trust-boundary) forbids this use of it in terms: "Do not route
  machine-to-machine traffic through it."

  Its premise is "this came from the user". A lander writing one puts words in the operator's mouth,
  which is the bullet above.

  So a lander reaches a busy worker through **no** channel. It waits for the turn to end, and uses
  announce or a claim like any other peer. If you route lander traffic through `steer.txt` anyway,
  you have broken the premise the recipient relies on.

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
