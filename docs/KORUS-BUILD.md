# Run a KORUS build

## TLDR/BLUF

**What this is.** The four-session build shape, with the opening prompt for each session and what to
expect back. The shape comes from [The KORUS framework](KORUS.md), one operator's account of months
of Claude Code work; this page is the operating procedure for it.

**Why you should care.** Four sessions with distinct jobs beat four sessions all doing the same job,
because the failures that cost you work come from two sessions deciding the same thing. Not for you
until [Quickstart](QUICKSTART.md) is done: this page assumes the gates are installed and proven.

**How to use it.** Open the sessions in the order below. Each section states the goal, the prompt to
paste, and what the session should do first.

---

## The shape

Four sessions, three jobs. **Nothing here implements the roles**: there is no dispatcher script, no
role flag, and no routing. The roles are a convention you establish in each session's opening prompt
and in your `CLAUDE.md`.

<figure role="group">
<svg viewBox="0 0 820 360" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="The four-session KORUS shape. A backlog feeds a dispatcher, which hands tasks to two build sessions. Each builder works in its own git worktree on its own branch, and a claim marks which task each holds. The collision gate sits between the two builders and refuses an edit to a file the other one already has uncommitted changes in. Both builders hand finished branches to a single lander session, which is the only one that pushes or merges, and a push guard sits between the lander and the trunk.">
  <defs>
    <marker id="korus-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
      <path d="M0,0 L10,5 L0,10 z" fill="currentColor" />
    </marker>
  </defs>
  <rect x="20" y="30" width="150" height="40" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="95" y="55" font-size="12" text-anchor="middle" fill="currentColor">Backlog</text>
  <line x1="95" y1="70" x2="95" y2="128" stroke="currentColor" stroke-width="1.5" marker-end="url(#korus-arrow)" />
  <rect x="20" y="130" width="150" height="56" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="95" y="152" font-size="12" font-weight="bold" text-anchor="middle" fill="currentColor">Dispatcher</text>
  <text x="95" y="170" font-size="11" text-anchor="middle" fill="currentColor">plans, tracks, assigns</text>
  <line x1="170" y1="145" x2="286" y2="95" stroke="currentColor" stroke-width="1.5" marker-end="url(#korus-arrow)" />
  <line x1="170" y1="172" x2="286" y2="252" stroke="currentColor" stroke-width="1.5" marker-end="url(#korus-arrow)" />
  <text x="205" y="105" font-size="10" font-style="italic" fill="currentColor">claim</text>
  <text x="205" y="238" font-size="10" font-style="italic" fill="currentColor">claim</text>
  <rect x="290" y="55" width="230" height="62" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="405" y="78" font-size="12" font-weight="bold" text-anchor="middle" fill="currentColor">Build session A</text>
  <text x="405" y="97" font-size="11" text-anchor="middle" fill="currentColor">own worktree, own branch</text>
  <rect x="290" y="228" width="230" height="62" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="405" y="251" font-size="12" font-weight="bold" text-anchor="middle" fill="currentColor">Build session B</text>
  <text x="405" y="270" font-size="11" text-anchor="middle" fill="currentColor">own worktree, own branch</text>
  <line x1="405" y1="120" x2="405" y2="225" stroke="currentColor" stroke-width="1.5" stroke-dasharray="5 4" />
  <rect x="300" y="152" width="210" height="42" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-dasharray="3 3" />
  <text x="405" y="169" font-size="11" font-weight="bold" text-anchor="middle" fill="currentColor">collision gate</text>
  <text x="405" y="186" font-size="10" text-anchor="middle" fill="currentColor">refuses the second edit</text>
  <line x1="520" y1="86" x2="620" y2="150" stroke="currentColor" stroke-width="1.5" marker-end="url(#korus-arrow)" />
  <line x1="520" y1="259" x2="620" y2="196" stroke="currentColor" stroke-width="1.5" marker-end="url(#korus-arrow)" />
  <rect x="622" y="145" width="170" height="56" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="707" y="167" font-size="12" font-weight="bold" text-anchor="middle" fill="currentColor">Lander</text>
  <text x="707" y="185" font-size="11" text-anchor="middle" fill="currentColor">the only one that pushes</text>
  <line x1="707" y1="201" x2="707" y2="279" stroke="currentColor" stroke-width="1.5" marker-end="url(#korus-arrow)" />
  <text x="716" y="228" font-size="10" font-style="italic" fill="currentColor">push guard</text>
  <rect x="622" y="281" width="170" height="40" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="707" y="306" font-size="12" text-anchor="middle" fill="currentColor">trunk</text>
</svg>
<figcaption>The dispatcher assigns; each builder holds a claim and its own worktree; the collision
gate sits between the builders and refuses an edit to a file the other already has uncommitted
changes in; the lander is the only session that reaches the remote.</figcaption>
</figure>

| Session | Owns | Must not |
|---|---|---|
| **Dispatcher** | The plan, the backlog, and which task goes to which builder | Write application code |
| **Builder** x2 | Building its own tasks on its own branch, about four at a time | Push, open a pull request, or merge |
| **Lander** | Every operation that touches the remote, and the order branches land in | Build |

A fifth session is worth running when you keep a security register: an **ASVS monitor** whose only
job is keeping that register current as the other three land work.

**Work too large for one context is the case this shape pays off in.** An OWASP ASVS 5.0 assessment
runs to several hundred requirements, more than one session can hold. Split across sessions, the
cost is different unwritten rules: verdicts nobody can reconcile.

[Large assessments](https://secure-development-standards.pages.dev/ASVS-ASSESSMENT.html) is the
method for that case.

## Before you open any session

| Do this | Why | Where |
|---|---|---|
| Install and prove the gates | Roles are advisory; the gates are not | [Quickstart](QUICKSTART.md) |
| Give each session its own worktree | Two sessions in one tree overwrite each other | [Worktrees](WORKTREES.md) |
| Wire the steering hook | It only takes effect in sessions started afterwards | [Steering](STEERING.md) |
| Write the working agreement | It only reaches sessions that start later | [CLAUDE.md.template](https://claude-multisession.pages.dev/CLAUDE.md.template) |
| Turn on Ultracode and pick Opus 5 in every session | The build shape assumes workflows and adversarial review | [The KORUS framework](KORUS.md) |

If you run more than one Claude account, set the accounts up first: one desktop instance per
account, and each one adds a config root the installers have to reach
([Desktop accounts](DESKTOP-ACCOUNTS.md)).

## 1. Open the dispatcher

**The goal.** One session holds the plan, so the other three never have to guess what is next.

**What to paste:**

```text
You are the dispatcher for this build. You plan and track; you do not write application code.

Read the backlog. Produce a build plan that breaks it into tasks sized for one session each,
and write an ADR for any decision that outlives the task that made it.

Hand out at most four tasks per build session. When a build session reports a task blocked,
take it back, update the backlog, and hand that session something else.

Do not push, open pull requests, or merge. The lander owns those.
```

**What happens next.** It reads the repository and comes back with a plan and a task breakdown. Ask
it to write the backlog to a tracked file before handing anything out, because a plan that lives
only in one context dies with that context.

## 2. Open the two build sessions

**The goal.** Two sessions building in parallel, each unable to silently overwrite the other.

**What to paste,** into each:

```text
You are a build session. Take the tasks the dispatcher hands you and build them, up to four
at a time as workflows.

Before starting a task, take a claim on it with a one-line note saying what you are building:
  pwsh -NoProfile -File scripts/coord/claim.ps1 -Take "<task>" -Note "<what you are building>"

Before editing a file you did not create, check who else is in it:
  pwsh -NoProfile -File scripts/coord/overlap.ps1

Commit at logical stops. Do not push, open pull requests, or merge -- tell the lander the
branch is ready instead.
```

**What happens next.** Each session announces itself to the peers it can reach, takes its claims,
and starts building. When both reach for the same file, the second one is refused rather than merged
([Coordination](COORDINATION.md)).

**Why two rather than eight.** Two builders running four tasks each normally stay under the
five-hour session cap, where eight separate sessions multiply the coordination traffic instead. That
reasoning is in [The KORUS framework](KORUS.md).

[Token accounting](TOKEN-ACCOUNTING.md) measures the other half: what one percent of a weekly window
is worth, and what a month of it costs at published API rates.

## 3. Open the lander

**The goal.** One session owns the remote, so the trunk moves under a single decision-maker.

**What to paste:**

```text
You are the lander. You own every operation that touches the remote: pushing, opening pull
requests, arming auto-merge, and merging.

Read state rather than being told it:
  pwsh -NoProfile -File scripts/coord/presence.ps1   # who is live
  pwsh -NoProfile -File scripts/coord/overlap.ps1    # what is in flight

Decide which of two branches on the same ground lands first, and who re-syncs after.
You arbitrate and land. You do not build.
```

**What happens next.** It reads the branches rather than waiting to be told about them. A pushed
branch is the signal that work is ready.

**Read the role page before you rely on it.** The authority is not transferable, the route is
absolute, and a worker that cannot reach the lander is blocked rather than promoted.
[Running multiple sessions](RUNNING-MULTIPLE-SESSIONS.md) owns the full role.

## The daily loop

1. **Ask the dispatcher what is in flight.** It answers from the backlog, not from memory.
2. **Check the builders have not collided.** `overlap.ps1` answers what each is changing.
3. **Steer rather than wait.** A session deep in the wrong approach does not see your typing until
   its turn ends ([Steering](STEERING.md)).
4. **Let the lander land.** It decides the order; you approve the grant once, in words.
5. **Prune what merged.** The reaper removes worktrees that are merged **and** clean **and**
   unoccupied, and declines when it cannot tell ([Pruning](PRUNING.md)).

## When it goes wrong

| Symptom | What it actually is | Go to |
|---|---|---|
| Two branches built the same feature | Effort overlap. No gate can compute it | [Coordination](COORDINATION.md) |
| Two records took the same number | The collision git cannot see | [Sequence allocation](SEQUENCE-ALLOC.md) |
| A session is deep in the wrong approach | Your typing queues until the turn ends | [Steering](STEERING.md) |
| Branches will not land | Four states with three different fixes | [PRs and merges](PR-AND-MERGE.md) |
| A peer cannot be reached at all | Extension session, or another login | [Session mail](SESSION-MAIL.md) |
| Everything is green and you cannot tell if any of it runs | Every failure here looks like success | [Limits and requirements](LIMITS.md) |

## What this shape does not decide for you

**Whether the work was any good.** The gates refuse collisions. Nothing here reviews a change, and
CI is what turns "it merged" into "it passed" ([CI for leaders](CI-FOR-LEADERS.md)).

**Whether you are about to run out.** Usage-limit awareness is a design on this site, not a shipped
hook ([Usage awareness](USAGE-AWARENESS.md)).

**Who writes shared state outside git.** Project memory and shared notes are last-write-wins, and
the remedy is single-writer convention rather than a gate.

## Related

| For | Read |
|---|---|
| The account of why this shape, in its author's words | [The KORUS framework](KORUS.md) |
| Which surface to run the sessions on, and the channels between them | [Running multiple sessions](RUNNING-MULTIPLE-SESSIONS.md) |
| The model every page here applies | [Concepts](CONCEPTS.md) |
| The things that bite, in the order they bite | [Tips and tricks](TIPS-AND-TRICKS.md) |
