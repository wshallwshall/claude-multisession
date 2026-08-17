# Steering a running session

## TLDR/BLUF

**What this is.** A way to interrupt a session that is already mid-task. You run one command from a
second terminal, and your message reaches that session at its **next tool call**, not after the
current turn finishes.

**Why you should care.** A session twenty minutes into the wrong approach cannot be reached. Typing
at its prompt only queues your message for *after* the turn ends. Not for you if you never run a
session long enough to want to interrupt it.

**How to use it.** Nothing wires the delivery half for you. Do it per worktree, at
`settings.local.json` scope, before you need it -- [Wiring it](#wiring-it) has the JSON.

---

Two files, about a hundred lines between them, and no coupling to anything else in this repo:

| File | Role | Kind |
|---|---|---|
| `bin/ccx-steer.ps1` | writes the note | user-facing command |
| `scripts/hooks/steer-inject.ps1` | delivers the note | opt-in `PreToolUse` hook: the harness runs it before every tool call |

Directory placement is the contract, not decoration. `scripts/hooks/` means "the harness invokes
this"; `bin/` means "you invoke this". The steer command is not a hook and does not live there.

## The problem it works around

No supported channel reaches a session between tool calls. But every tool call is a handoff to the
harness, where a `PreToolUse` hook fires. That hook's `additionalContext` output lands in the
model's context. So the path exists; what is missing is a way for another process to write into it.

## How it works

**The goal.** Get one sentence in front of a session that is already mid-task.

**What to do.** Run this from a second terminal, in the worktree that session is working in:

```powershell
# terminal 2, while the session in that worktree is mid-task
pwsh -NoProfile -File bin/ccx-steer.ps1 "stop refactoring the parser; just fix the failing test"

# or, from anywhere
pwsh -NoProfile -File bin/ccx-steer.ps1 "..." -ProjectDir <path to the worktree>
```

**What happens next.**

1. The command writes your message to `<worktree>/.claude/steer.txt`.
2. At the session's next tool call, `scripts/hooks/steer-inject.ps1` fires, finds the file, reads
   it, **deletes it**, and re-emits the text wrapped in an envelope.
3. The session sees the note before that tool call is executed.

The envelope tells the model the text arrived via a side channel and should be acted on now, not at
the end of the turn.

The hook's output shape is fixed by the event:

<!-- no-copy -->
```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"[STEERING NOTE ...]: ..."}}
```

**The `hookSpecificOutput` wrapper is mandatory.** Emitting `additionalContext` at the top level
does not deliver it, and nothing complains: the hook exits 0 and the note is simply gone.

## Wiring it

**The goal.** Turn delivery on for one worktree. No installer in this repo wires this hook, on
purpose.

**What to do.** Add this to that worktree's `.claude/settings.local.json`:

<!-- no-copy -->
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "pwsh -NoProfile -File \"<absolute path to this repo>/scripts/hooks/steer-inject.ps1\"",
            "timeout": 5,
            "statusMessage": "Checking for steering notes"
          }
        ]
      }
    ]
  }
}
```

**Keep the escaped quotes around the path.** This is the one hook you wire by hand, so nothing
corrects it for you. Unquoted, a checkout path containing a space -- a two-word account name, a
redirected OneDrive profile, a `My Projects` directory -- makes `pwsh` read only the first word as
`-File`.

Measured: it exits 64 with a usage dump on stderr and nothing on stdout. Because this hook fails
open, that is byte-identical to "no note waiting", which the page's own
[fail-open section](#it-fails-open-and-what-that-costs-you) calls the failure you cannot detect.

**What happens next.** Wiring takes effect in **newly started sessions** only. Enable it before you
need it, not while the session you want to steer is already running.

Two reasons it is local and opt-in rather than tracked and always-on:

- **It costs a process spawn before every tool call.** Measured where this tooling was developed:
  roughly 366 ms per tool call, of which about 267 ms is bare PowerShell startup and cannot be
  optimized away. A standing tax in every session, paid for a feature you use occasionally.
- **`*.local.*` is git-ignored** by this repo's `.gitignore`. Anything with `.local.` in its name
  belongs to one checkout on one machine, so wiring it there opts one worktree in without opting in
  every clone.

## Why a file, and not an environment variable

An environment variable is read once, at process start. Hook wiring is resolved at session start. A
change to either reaches the sessions you start *next*, never the one already doing the wrong thing.
Both are configuration for future sessions dressed up as a control for the current one.

A file is different only in that the hook re-reads it on **every** run. That single property is what
makes it able to reach a live process:

| Channel | Reaches a session that is already running | Why |
|---|---|---|
| Environment variable | no | read once, at process start |
| Settings edit | no | hook wiring is resolved at session start |
| File checked by a hook | **yes** | re-read on every tool call |

The announce kill switch in this repo is a file for the same reason: `<state-root>/announce/OFF`,
not only the `CCX_ANNOUNCE_DISABLE` variable. The variable stands down sessions started after you
set it, which is precisely not the population misbehaving right now.

**Rule: anything that must reach a session already in flight -- a steering note, an emergency
off-switch -- is a file the hook checks on every run.** Environment variables and settings are for
sessions that have not started yet.

Two processes that share a filesystem need no IPC, no port, no daemon, and no knowledge of each
other's identity. The write is the send, the delete is the acknowledgement. That is the entire
protocol, which is why these two scripts share no code.

## The queue is one slot deep

- Writing a second note **replaces** the first. The command warns when it overwrites one that was
  never consumed. Take the warning seriously: the earlier note was not delivered and never will be.
- Delivery is read-then-delete, and the honest bound is **at most once**. The hook checks, reads,
  deletes and emits as separate steps under no lock, and the delete lands before anything confirms
  the note reached the model. There is no history and no re-delivery.
- **There is no expiry.** A note sits until the session's next tool call, possibly hours later and
  in the middle of an unrelated task. Write any condition into the text so the *recipient* can
  evaluate it: "if you have not started the migration yet, don't". Never write one only you can
  observe.
- The command's success output is a receipt that the note was **written**, not that it was
  **delivered**. Nothing in this pair reports delivery back to you. To know it landed, see
  [It fails open, and what that costs you](#it-fails-open-and-what-that-costs-you).

## Where the note goes, and why the command refuses to guess

`Resolve-ProjectDir` in `bin/ccx-steer.ps1` resolves the target in this order:

1. `-ProjectDir`, if given,
2. `$env:CLAUDE_PROJECT_DIR`, if set,
3. the enclosing worktree root, from `git rev-parse --show-toplevel`.

If none of those produce a directory it **throws** rather than defaulting to the current directory.
It throws again if the resolved directory has no `.claude` in it.

Both refusals are scar tissue. An earlier version resolved against the working directory and created
`.claude` if missing, so a command run from the wrong place printed "queued" over a note nothing
reads. The hook reads only `<project root>/.claude/steer.txt`. A green no-op is the worst outcome.

The hook mirrors this: if `CLAUDE_PROJECT_DIR` is unset it exits 0 immediately rather than searching.

## Encoding

Both scripts are ASCII-only, and the note is UTF-8 without a BOM (`-Encoding utf8` under PowerShell
7). It crosses processes and cannot depend on either console's code page. `.editorconfig` pins
UTF-8-no-BOM and LF, because other controls hash-compare an installed copy against the repo copy.

The message is written with `-NoNewline`, so what you typed is what arrives. The hook trims
whitespace and skips an empty or whitespace-only note.

## It fails open, and what that costs you

The hook declares its posture in its own header: **any error exits 0**. That is right here. A
steering convenience must never block a tool call, and a broken side channel must not break the
session.

The price is that breakage is invisible. A hook that is not wired, cannot find its script, or throws
on the first line emits nothing -- byte-for-byte what it emits when no note is waiting. "No note
queued" and "never wired" look identical: silence that reads as all-clear.

One signal lives outside the failing component, and it is free:

> **The note file is the receipt.** After the session has made at least one tool call, if
> `<worktree>/.claude/steer.txt` still exists, the hook did not run. If it is gone, it was consumed.

Check the file, not the transcript. `bin/ccx-doctor.ps1` lists every settings file that wires the
injector, by receipt, but does **not** fire it. `OK` means "wired here", not "proven to deliver". A
`--` means "not wired anywhere it can see", which for an opt-in feature is fact, not fault.

## Proving it end to end

**The goal.** Read the decision the hook emits, rather than inferring behavior from the source.

**What to do.** The hook reads no stdin -- everything it needs comes from the environment and the
file -- so you can drive it directly:

```powershell
pwsh -NoProfile -File bin/ccx-steer.ps1 "throwaway probe, ignore"

$env:CLAUDE_PROJECT_DIR = (git rev-parse --show-toplevel)
pwsh -NoProfile -File scripts/hooks/steer-inject.ps1

Remove-Item Env:\CLAUDE_PROJECT_DIR      # do not skip this -- see below
```

**What happens next.** Expect one line of compact JSON containing your text, and `.claude/steer.txt`
to be gone afterwards.

Three cautions:

- **Unset `CLAUDE_PROJECT_DIR` afterwards.** It outranks the worktree root in `ccx-steer.ps1`'s own
  resolution order. Left set, it silently aims every later `ccx-steer` run at the directory you
  probed from -- including notes you meant for another worktree.
- **This consumes the note.** Probe with a throwaway message, never with one you actually queued
  for a session.
- **Run the copy your settings name**, not the repo copy, if the two differ. A control is enforced
  by the file that is wired, and it can drift arbitrarily far from the file you are reading.

**No output does not mean the note survived.** It means the hook emitted nothing, and several of
those paths destroy the note first: a read-then-delete that fails after the delete, or a timeout
that kills the hook mid-run.

Read an empty result as "gone and undelivered", never as "still queued".

## The trust boundary

The steering note is the operator's own words, wrapped in an envelope that says so, and is meant to
be acted on the way a prompt is. Anything that can write `<worktree>/.claude/steer.txt` can put
words in the operator's mouth. The file is exactly as trusted as the worktree it sits in.

The inverse matters if you reuse this channel. A message from *another session* is peer data and
must never be obeyed as though the user said it. Do not route machine-to-machine traffic through it:
its premise is "this came from the user", and a channel that lies about that is worse than none.

## Limits

| Limit | Detail |
|---|---|
| Platform | PowerShell 7, Windows-first. Both scripts are plain PowerShell with no other dependency. |
| Delivery point | Only at a tool call. A session composing a long answer without calling a tool will not see the note until it next calls one. |
| Wiring reach | Enabling the hook affects newly started sessions only. The *note* reaches a running session; the *hook* has to already be there. |
| Depth | One note per worktree. No queue, no history, no re-delivery. |
| Receipt | The command confirms the write, never the delivery. The absence of the file is your only delivery evidence. |
| Failure mode | Fails open and silently by design; a broken hook is indistinguishable from an idle one at the session. |
| Install | No installer wires it. `bin/ccx-doctor.ps1` reports whether it is wired, by receipt, and does not attack it. |
