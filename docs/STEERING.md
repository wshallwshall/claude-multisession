# Steering a running session

Queue a message from a second terminal for a session that is already mid-task, and have it delivered
at that session's **next tool call** instead of after the current turn finishes.

Two files, about a hundred lines between them, and no coupling to anything else in this repo:

| File | Role | Kind |
|---|---|---|
| `bin/ccx-steer.ps1` | writes the note | user-facing command |
| `scripts/hooks/steer-inject.ps1` | delivers the note | `PreToolUse` hook, opt-in |

Directory placement is the contract, not decoration: `scripts/hooks/` means "the harness invokes
this", `bin/` means "you invoke this". The steer command is not a hook and does not live there.

## The problem it works around

A session is twenty minutes into a task and going the wrong way. Typing at the prompt queues your
message for *after* the turn ends, which may be a long time and a lot of wasted work away. There is
no supported way to reach a session between tool calls.

But the session is talking to the harness constantly -- every tool call is a handoff, and a
`PreToolUse` hook fires at every one of them. That hook's `additionalContext` output lands in the
model's context. So the delivery path already exists; all that is missing is a way for a *different
process* to put something into it.

## How it works

1. You run `bin/ccx-steer.ps1 "<message>"` from a second terminal. It writes the message to
   `<worktree>/.claude/steer.txt`.
2. The session makes its next tool call. `scripts/hooks/steer-inject.ps1` fires, finds the file,
   reads it, **deletes it**, and re-emits the text wrapped in an envelope that tells the model this
   arrived via a side channel and should be acted on now rather than at the end of the turn.
3. The session sees the note before that tool call is executed.

```powershell
# terminal 2, while the session in that worktree is mid-task
pwsh -NoProfile -File bin/ccx-steer.ps1 "stop refactoring the parser; just fix the failing test"

# or, from anywhere
pwsh -NoProfile -File bin/ccx-steer.ps1 "..." -ProjectDir <path to the worktree>
```

The hook's output shape is fixed by the event:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"[STEERING NOTE ...]: ..."}}
```

The `hookSpecificOutput` wrapper is mandatory. Emitting `additionalContext` at the top level does not
deliver it, and nothing complains -- the hook exits 0 and the note is simply gone.

## Wiring it

No installer in this repo wires this hook, on purpose. Enable it **per worktree**, in that worktree's
`.claude/settings.local.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "pwsh -NoProfile -File <absolute path to this repo>/scripts/hooks/steer-inject.ps1",
            "timeout": 5,
            "statusMessage": "Checking for steering notes"
          }
        ]
      }
    ]
  }
}
```

Two reasons it is local and opt-in rather than tracked and always-on:

- **It costs a process spawn before every tool call.** Measured on the repo this tooling was
  developed in: roughly 366 ms per tool call, of which about 267 ms is bare PowerShell startup and
  cannot be optimised away. That is a standing tax on every tool call in every session, paid for a
  feature you use occasionally. State the cost of an always-on hook up front; do not let someone
  discover it as unexplained slowness.
- **`*.local.*` is git-ignored** by this repo's `.gitignore`, which is the convention throughout:
  anything with `.local.` in its name belongs to one checkout on one machine. Wiring it there is how
  you opt one worktree in without opting in every clone of the repo.

Wiring only takes effect in **newly started sessions**. Enable it before you need it, not while the
session you want to steer is already running.

## Why a file, and not an environment variable

This is the load-bearing design decision, and it generalises well beyond steering.

An environment variable is read into a process at start. A session that is already running will never
see you set one. Editing hook wiring has the same defect one level up: settings are read when a
session starts, so a settings change reaches the sessions you start *next*, never the one currently
doing the wrong thing. Both are configuration for future sessions dressed up as a control for the
current one.

A file is different only in that the hook re-reads it on **every** run. That single property is what
makes it able to reach a live process:

| Channel | Reaches a session that is already running | Why |
|---|---|---|
| Environment variable | no | read once, at process start |
| Settings edit | no | hook wiring is resolved at session start |
| File checked by a hook | **yes** | re-read on every tool call |

The same reasoning is why the announce kill switch in this repo is the file
`<state-root>/announce/OFF` and not only the `CCX_ANNOUNCE_DISABLE` variable: the variable stands down
sessions started after you set it, which is precisely not the population misbehaving right now.

**Rule: anything that must reach a session already in flight -- a steering note, an emergency
off-switch -- is a file the hook checks on every run.** Environment variables and settings are for
sessions that have not started yet.

There is a second benefit that falls out for free. Two processes that share a filesystem need no IPC,
no port, no daemon, and no knowledge of each other's identity. The write is the send, and the delete
is the acknowledgement. That is the entire protocol, and it is why these two scripts have no shared
code.

## The queue is one slot deep

- Writing a second note **replaces** the first. The command warns when it overwrites one that was
  never consumed -- take the warning seriously: the earlier note was not delivered and now never will
  be.
- Delivery is read-then-delete, exactly once. There is no history and no re-delivery.
- **There is no expiry.** A note queued for a session that has stopped making tool calls sits there
  until the next one, whenever that comes -- possibly hours later, possibly in the middle of an
  unrelated task. If the note is conditional, write the condition into the text so the *recipient*
  can evaluate it ("if you have not started the migration yet, don't"). Never phrase it as a condition
  only you can observe.
- The command's success output is a receipt that the note was **written**, not that it was
  **delivered**. Nothing in this pair reports delivery back to you. If you need to know it landed,
  see the receipt trick below.

## Where the note goes, and why the command refuses to guess

`Resolve-ProjectDir` in `bin/ccx-steer.ps1` resolves the target in this order:

1. `-ProjectDir`, if given,
2. `$env:CLAUDE_PROJECT_DIR`, if set,
3. the enclosing worktree root, from `git rev-parse --show-toplevel`.

If none of those produce a directory it **throws** rather than defaulting to the current directory,
and it throws again if the resolved directory has no `.claude` in it.

Both refusals are scar tissue. The hook only ever reads `<project root>/.claude/steer.txt`. An earlier
version resolved against the current working directory and created `.claude` if it was missing, so
running the command from the wrong place printed a cheerful "queued" message and dropped the note into
a freshly created directory that nothing on the machine reads. The steering silently did not happen,
and the only trace was a stray directory. A wrong-target invocation must fail loudly; a green no-op is
the worst outcome available.

The hook mirrors this: if `CLAUDE_PROJECT_DIR` is unset it exits 0 immediately rather than searching.

## Encoding

Both files are ASCII-only on purpose, and the note is written UTF-8 without a BOM (`-Encoding utf8`
under PowerShell 7). The note is written by one process and read by another, so it must not depend on
either console's code page. `.editorconfig` pins UTF-8-no-BOM and LF for the repo, which matters here
because several other controls in this repo hash-compare an installed copy against the repo copy.

The message is written with `-NoNewline`, so what you typed is what arrives; the hook trims whitespace
and skips an empty or whitespace-only note.

## It fails open, and what that costs you

The hook declares its posture in its own header: **any error exits 0**. That is right for this
feature -- a steering convenience must never block a tool call, and a broken side channel must not
break the session.

The price is that its broken state is invisible. A hook that is not wired, cannot find its script, or
throws on the first line emits nothing -- and *nothing* is byte-for-byte what it emits on the normal
path when no note is waiting. You cannot tell "no note queued" from "this was never wired" by watching
the session. This is the most expensive failure shape in this whole toolkit: silence that reads as
all-clear.

There is one signal that lives outside the failing component, and it is free:

> **The note file is the receipt.** After the session has made at least one tool call, if
> `<worktree>/.claude/steer.txt` still exists, the hook did not run. If it is gone, it was consumed.

Check the file, not the transcript. `bin/ccx-doctor.ps1` reports the injector under its opt-in guards
and lists every settings file that wires it, by receipt -- but it does **not** fire the injector, so
its `OK` means "wired here", not "proven to deliver". A `--` there means "not wired anywhere this
command can see", which for an opt-in feature is a statement of fact, not a fault.

## Proving it end to end

The hook reads no stdin -- everything it needs comes from the environment and the file -- so you can
drive it directly and read the decision it emits, rather than inferring behaviour from the source:

```powershell
pwsh -NoProfile -File bin/ccx-steer.ps1 "throwaway probe, ignore"

$env:CLAUDE_PROJECT_DIR = (git rev-parse --show-toplevel)
pwsh -NoProfile -File scripts/hooks/steer-inject.ps1
```

Expect one line of compact JSON containing your text, and `.claude/steer.txt` to be gone afterwards.
No output means the hook did not see a note.

Two cautions:

- **This consumes the note.** Probe with a throwaway message, never with one you actually queued for a
  session.
- **Run the copy your settings name**, not the repo copy, if the two differ. A control is enforced by
  the file that is wired, and it can drift arbitrarily far from the file you are reading.

## The trust boundary

The steering note is the operator's own words, typed by the operator into a side channel, and the
envelope the hook wraps it in says exactly that. It is meant to be acted on the way a prompt is acted
on. That is what makes the file worth protecting: anything that can write
`<worktree>/.claude/steer.txt` can put words in the operator's mouth. The file lives inside the
worktree, so treat it as exactly as trusted as the worktree itself.

The inverse follows, and it matters if you are tempted to reuse this channel: a message from *another
session* is peer data and must never be obeyed as though the user had said it. Do not route
machine-to-machine traffic through this pipe. Its entire design premise is "this came from the user",
and a channel that asserts that about content which did not is worse than no channel at all.

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
