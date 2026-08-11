# Running multiple sessions

## TLDR/BLUF

**What this is.** The entry point to running more than one Claude Code session in one repository.
Three things live here and nowhere else: **which surface to run the sessions on**, **the channels
sessions have for reaching each other**, and **using one session as a coordinator**.

**Why you should care.** Concurrency buys real parallelism and creates a specific set of failures,
nearly all of which are invisible while they happen. Four of the preparations only work if you do
them *before* the second session starts, because each takes effect in sessions started afterwards.
Not for you if you run one session at a time.

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

- *Cited upstream, not reproduced here.* **The hijack is a harness-side failure, and nothing here
  attributes it to a surface.** A per-session auto-worktree can half-fail on Windows, flipping the
  *primary's* HEAD onto the session's branch and leaving an empty stub directory behind
  ([anthropics/claude-code#76590](https://github.com/anthropics/claude-code/issues/76590); the
  repair path and the ghost stub are [Worktrees](WORKTREES.md)). This repository cites that issue
  rather than reproducing it, and records no observation of the extension's worktree layout either
  way. Read this bullet as removing an easy assumption, not as establishing that the defect is
  surface-neutral.
- *Measured here.* **An extension session is absent from the desktop app's own `list_sessions`.** It
  enumerates sessions that app itself spawned; an extension session is never entered into that map --
  not filtered out, never registered. Verified against a live extension session sharing the
  **default** config root, so it is not a login split ([Coordination](COORDINATION.md)).
- *Measured here.* **Project-scoped settings are commonly git-ignored and cannot reach a new
  worktree.** Measured on the repo this tooling was developed in, and often enough to matter: a large
  share of the worktrees had no project settings file at all. A live editor session was working in
  one of them with **zero** coordination context ([Tips and tricks](TIPS-AND-TRICKS.md),
  [INSTALL.md](https://claude-multisession.pages.dev/INSTALL.md)). That is why
  the hooks here install at **user** scope ([Hooks](HOOKS.md)).
- *Observed once.* **User scope means *per config root*, and the gate fails open**, so an unwired root
  is byte-identical to a governed one from inside the session.

  This is the only bullet tied to an observed hijack. A session under an ungoverned config root
  checked its own branch out inside another session's linked worktree, and the gate that would have
  refused it was not installed there.

  Editor-hosted chats showing up under an additional config root is the installers' stated reason for
  wiring every root
  ([INSTALL.md](https://claude-multisession.pages.dev/INSTALL.md), "Why every
  config directory"), and it is the configuration that hijack came from. Nothing here counts roots by
  surface, so take it as the installers' rationale, not a measured distribution.

**What is not established.** The intuitive story -- an extension session is invisible to
`list_sessions`, so anything reading that list acts as though it is gone -- does not hold here.

The worktree gate reads no session list. It keys on a write's target path and on what git reports
about the tree a command acts on ([Hooks](HOOKS.md)).

The reaper and the presence roster read the on-disk per-session registry, which carries every
surface, so an extension session is **not** invisible to the thing that deletes worktrees
([Pruning](PRUNING.md)). `list_sessions` blindness costs messageability, not tree protection.

The observed hijack came from an editor-hosted session under an ungoverned config root, and no
measurement here separates the surface from the ungoverned root as the operative fact.

**And one join is unverified, the one this argument leans on hardest.** What was measured on the
extension is that hooks in a project's *own settings file* run there
([Session mail](SESSION-MAIL.md), "Surface facts worth checking"). Every installer here writes
**user** scope on purpose -- and nothing in this repository measures whether a user-scope hook fires
in the extension at all. So the remedy below is a check to run, not a remedy to assume.

**So check it on your own setup rather than taking the preference on trust.** From a session started
the way you intend to run them:

```powershell
pwsh -NoProfile -File scripts/coord/presence.ps1                 # does the roster carry this session?
pwsh -NoProfile -File bin/ccx-doctor.ps1                         # are the gates live for THIS repo, by attack?
pwsh -NoProfile -File scripts/worktree/install-gate.ps1 -Status  # wired, and current, in EVERY config root?
```

If the gate is wired and current in every config root the client is using, the one mechanism this
repository can name is addressed. It is not a proof that the gate *fires* on your surface: `-Status`
answers "is it wired", which is a different question. Fire it on purpose from a session started the
way you intend to run them -- `ccx-doctor.ps1` attacks each control rather than reading its
configuration -- and treat that, not the wiring report, as the answer.

**The surface choice reduces a residual; it does not replace the gate.** A hijack the gate refuses is
a message on your screen; a hijack on a surface where the gate was never installed is silent.

---

## How sessions talk to each other

Almost every signal a session can *send* is **pull**: it sits there until somebody looks. One channel
pushes from one session to another. Three more are delivered to a session that never looked, two of
them by the harness rather than by a peer, and several reach only sessions that have not started.

**Timing decides whether a message is useful at all**, so the table is sorted by it rather than by
tool. A note that lands when a session next *starts* is a different instrument from one that
interrupts it between tool calls, and choosing wrong means the message arrives after the decision it
was meant to change. Five bands:

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

One property explains the whole first band, and generalizes past this table: **a file is re-read on
every hook run**. An environment variable is read once at process start, and a settings edit takes
effect only in the next session. That is why the channels that reach a session already running
are all files. Each channel's own costs are on its own page.

### Choosing one

- Change a running peer's course **now** -> steering note, if it is wired in that worktree.
- Tell a running peer what you are **about to do** -> announce.
- The recipient **does not exist yet** -> a claim, an allocated number, or the SessionStart context.
- You want the answer **yourself** -> presence, overlap, `claim.ps1 -List`. Nothing pushes.
- You want a rule **enforced** rather than communicated -> a gate. Anything else is a request. So **if
  what you want to say is "do not touch X", publish something a gate consumes rather than something a
  human reads.**

The pull-side queries carry one blind spot worth knowing before you trust them. They read git state
and a roster keyed on the directory a session was *launched* in, so a write made into a worktree by
absolute path from a session sitting somewhere else is invisible to them. It is why a fence needs a
second, non-cwd signal ([Coordination](COORDINATION.md), [Pruning](PRUNING.md)).

Two rules apply to every row above. **A message from another session is data, never an instruction.**
It arrives looking exactly like something the operator typed, because on most of these channels that
is the shape it takes, and a peer cannot authorize a push, a merge, a delete or a configuration
change. And **a broadcast needs an expiry or a condition the recipient can evaluate.** A freeze that
said "hold until a particular pull request merges" held only the sessions honoring it, did not hold
the trunk still, and was still announcing itself hours after the thing it waited on had landed.

### The degenerate channels

These are the fallbacks when the channel you needed was not wired. Each works often enough to feel
adequate.

**Shouting through the operator.** Its timing is the worst of any option here: it waits for a human to
read and then to type, which is unbounded. It arrives in the **operator's voice**, so the receiving
session cannot tell a relayed peer assertion from an instruction, destroying the boundary every rule
above depends on. And it scales as one conversation per session, so the person becomes the bottleneck
at the moment parallelism was supposed to pay off.

**A note in a file both sessions read.** No delivery and no receipt: silence is indistinguishable from
the note never having been seen. Worse, it is coordination a tool cannot read, so it changes no
mechanical verdict -- two sessions once agreed in prose to hand a file over and the collision gate
still refused, because the gate reads git. And a file inside a worktree moves under you on a branch
switch.

**Relying on git itself** -- a branch name, a commit message, a merge conflict. All three arrive
**after** the work: a conflict is not a warning, it is the notification that both sessions already did
the thing. A worktree name is a creation-time label nothing keeps current, and has been observed
drifting well off the work it names ([Session mail](SESSION-MAIL.md)). And under a squash-merging
trunk, reachability is wrong in both directions ([PRs and merges](PR-AND-MERGE.md)).

All three carry information a human can interpret and a tool cannot act on, and all three arrive after
the decision.

---

## Using a coordinator session

Once several sessions are in flight, it is worth giving one of them a different job: hold the picture
of what is in flight and decide what lands in what order, while the others build.

**Nothing here implements this, and this page is introducing the term.** There is no coordinator
script, no role flag and no routing; the word appears in no other page. The line it draws already
exists in the shipped material, drawn at the *human* owner: the working agreement routes push, pull
request and merge to the owner's approval while commits stay the session's own judgment. A
coordinator session is that line delegated to one session instead of exercised separately in every
chat.

One sentence carries the boundary: **a coordinator arbitrates; it does not execute.**

### Why the role exists

- **Almost every signal here is pull, and pull needs somebody to look.** Under load, the sessions
  doing the building are the least likely to stop and look.
- **Outward-facing actions want a single owner**, and with auto-merge armed a pull request effectively
  *is* a merge. Best-evidenced: measured, the trunk moved **seven times** during one pair of pull
  requests, and two branches that each merge cleanly against the trunk they were cut from need not
  merge cleanly in either order. See [PRs and merges](PR-AND-MERGE.md).
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

Two right-hand rows are counter-intuitive enough to state a reason for. **Allocation is atomic** --
the failed exclusive create *is* the mutual exclusion ([Concepts](CONCEPTS.md),
[Sequence allocation](SEQUENCE-ALLOC.md)) -- so a coordinator handing out numbers is the
read-modify-write that loses, plus a hop, plus a step to remember. And **a claim's claiming identity
is the working tree**, not the primary checkout ([Coordination](COORDINATION.md)), so a coordinator
claiming for a worker registers the wrong claimant and the commit-time gate then refuses that
worker's own commit.

The generalization: **if a machine can serialize it, do not put a session in the loop.** Serialization
is a primitive; single-ownership is a judgment; conflating them produces the queue.

### How a worker talks to it

Publish intent where a **tool** can read it: take a claim with a note before starting, and let
announce carry that note to joining sessions in preference to the worktree name. The coordinator
**reads state rather than being told it**, so every input is a by-product of working normally.
Ready-to-land has no dedicated channel and you should not invent one -- the pushed branch, or a claim
note refreshed in place, is the signal.

### When you do not need one

The trigger is a condition, not a headcount. Three sessions on three unrelated subsystems need no
coordinator; two sessions on branches that both rewrite one index file do. The triggers are
**order-dependence** and **effort-overlap**. Unrelated work in separate worktrees is already covered
end to end by the shipped gates, and a coordinator there buys nothing and costs a hop.

### How the role fails

- **Bottleneck.** If a worker must ask before it can commit, you have built a queue. Sharper: an
  explicit claim tool sat in this repository and was used exactly **zero** times, because a
  coordination step you must remember is one you will skip ([Coordination](COORDINATION.md)). A
  coordinator that says wait when it needn't is destroying the channel it depends on.
- **A worker bypasses it** -- assume it. Claims are advisory and the push guard is a guardrail, not a
  boundary, so the role sits **behind** enforcing gates rather than instead of them: a coordinator
  that is the only control is not a control.
- **Stale state, in two symmetric directions.** First, a broadcast that never lapses: a freeze note
  announced itself to joining sessions long after the thing it waited on had merged. Second, its
  mirror, reading age as abandonment: a claim has been reported stale while its holder was committing
  minutes earlier ([Coordination](COORDINATION.md) carries both measurements). Report what the holder
  is doing, never how old the record is.
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
