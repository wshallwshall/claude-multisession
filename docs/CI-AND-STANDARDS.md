# CI and standards for agent-written code

Several sessions are producing branches in parallel. All of them have to survive a real pipeline and
land in one trunk, and most of the code was written by an agent rather than typed. This document is
about that second half of the job: **getting work through CI without believing things that are not
true, and keeping a standard that does not quietly erode while nobody is looking.**

It is in two parts, and they answer different questions:

- **[Part 1: CI for multi-session work](#part-1-ci-for-multi-session-work)**: what breaks when N
  sessions push into one pipeline, and how each failure disguises itself as something else.
- **[Part 2: standards that survive agent-written code](#part-2-standards-that-survive-agent-written-code)**:
  how to review prose and claims, what the agent decides versus what you decide, and what "done"
  has to mean.

Scope and honest limits, first:

- **This repository ships no CI configuration.** Nothing here installs a workflow for you. The
  scripts referenced below are illustrations of the rules -- a working gate, a working receipt, a
  working two-layer control -- not a pipeline you can adopt whole.
- **Where the mechanics are forge-specific they are GitHub-shaped**, because that is what was
  exercised. The failure *shapes* are not forge-specific; the field names are.
- **Numbers here come from one of two places, and the difference is marked at the point of use.**
  Unmarked figures were measured on the repo this tooling was developed in; they are stated to
  justify a rule, never as constants you should expect to reproduce. Figures taken from published
  research carry an explicit **[external]** tag, and are not this repository's measurements at all.
  They carry their own sources' limitations, and the rule in *Do not claim a speed or quality gain
  you have not measured here* applies to them first.

Related, and deliberately not repeated here: [`PR-AND-MERGE.md`](PR-AND-MERGE.md) for merge-base,
conflict and merge-state mechanics; [`TIPS-AND-TRICKS.md`](TIPS-AND-TRICKS.md) section 4-5 for writing and
measuring a guardrail; [`SEQUENCE-ALLOC.md`](SEQUENCE-ALLOC.md) for shared-number collisions;
[`CASE-STUDY-drift-audit.md`](CASE-STUDY-drift-audit.md) for auditing controls as one system.

---

# Part 1: CI for multi-session work

## A green local run is not a green pipeline

This is the single most useful idea in Part 1, and every subsection under it is a different reason
the same sentence is true. The local quartet -- lint, format, types, tests -- passing tells you
something real. It does not tell you the pipeline will pass, and reading a red pipeline as "CI is
flaky" is the standard first mistake.

### Some checks have no local invocation at all

A change was pushed as "verified" on a clean local quartet. CI failed on gates the developer had
never run, because there is no command that runs them:

| Class of CI-only gate | Why it cannot be green locally |
|---|---|
| Static analysis / SAST | Runs as a hosted action; no local entry point exists |
| Content and secret scanning | Needs the full history and a rule source the clone does not carry |
| Inventory / doc-drift guards | Require a new artefact to be registered in an index **in the same commit** |
| Real-database legs | Silently *skip* locally because no server is reachable |
| Artefact-integrity gates | Compare a built artefact against a manifest that is only built in CI |

**Rule.** Keep an explicit list of the checks that run only in CI, and before pushing, self-run the
ones your diff plausibly trips. When you report a run, **name the commands you actually ran** rather
than saying "all green". CI, not your laptop, is the authority on what the full check set is.

The database row is the nastiest, because a skip and a pass are the same exit code. A leg that needs
a server you do not have will report success on your machine and fail on the runner, and nothing in
the local output says which happened. That is the same shape the doctor command refuses to allow:
`bin/ccx-doctor.ps1` reports an undetermined check as `??` and exits **2**, precisely so that a skip
can never be read as a pass.

### A gate that fails closed without a credential is blind locally -- or strong for the wrong reason

Two symmetric failures, both of which produce a green you cannot use:

1. **Blind locally.** A scanner refuses to run without a token or rule source, so on a machine
   without one it exits non-zero for a reason unrelated to your code. That looks exactly like the
   gate being broken, and it teaches people to skip it.
2. **Strong for the wrong reason.** The mirror image is worse. A guard whose behaviour depends on an
   environment variable that only one CI job sets will *pass in CI because the variable is absent*
   while failing on every developer box that has it. A guard that is strictly weaker in CI than on a
   laptop is not a guard.

**Rule.** For any check whose behaviour depends on a credential or an environment variable, write
down which jobs supply it, and confirm the gate is **at least as strong in CI as locally**. Make a
missing credential produce a distinct, self-describing exit state -- never a silent pass, and never an
exit code indistinguishable from a real finding.

### Reproduce CI's exact invocation, path arguments included

The formatter ran repo-wide; the linter ran against an explicit path list. Invoking the linter over
the whole repo locally produced roughly a hundred findings CI never sees, all in directories
deliberately outside the lint scope. That reads as "my branch is broken", triggers a panic fix
mid-task, and none of it was ever CI's verdict.

**Rule.** Copy CI's command line, including its path arguments. Do not substitute the tool's
convenient default scope. Where local and CI scopes legitimately differ, **pin the difference with a
test** so the two cannot silently diverge.

### Scoped-green is not the gate

An agent that runs only the tests near its change and reports green has not passed the gate. Two
parallel lanes did exactly that and failed CI -- one tripped a cross-cutting inventory-drift gate that
no change-local test exercises, the other failed only on one operating system's legs.

**Rule.** "Done" means the same gate that governs merge: the full local quartet **and** the blocking
CI, including cross-cutting invariant gates and every platform leg. Declare scope when you report a
run. *"The tests near the change passed"* is a different sentence from *"the gate passed"*, and only
one of them is an answer.

### One gate command, three call sites

Editor integration, the local pre-commit hook, and CI each had their own idea of what "the checks"
were. Divergence between them is exactly where *it passed on my machine* comes from.

**Rule.** Ship **one** gate command and have all three call sites invoke it identically, with the
same flags. Where a call site must differ -- an optional linter that is not installed everywhere --
make the difference an explicit, advisory-marked flag rather than a silently different command.

`scripts/hooks/seq_check.py` is the shape to copy: one file, one rule set, invoked as a pre-commit
hook locally and with `--ci` against a freshly fetched trunk. Its header states plainly that **the
two modes are not symmetric** and which rule cannot run in `--ci` -- see
[*State what a gate does not prove*](#state-what-a-gate-does-not-prove).

---

## What your test runner did not run

### Discovery config can silently exclude a whole package

The runner's config pinned discovery to a single directory. A second first-party package shipped its
own suite one directory over -- measured on the repo this tooling was developed in, 14 files and
roughly 344 tests -- and a bare run executed **none** of it. A "full suite" run reported 10,301
passed and 2 failed, was declared green, and CI then failed on three genuine regressions in the
excluded package, one of them security-relevant.

The number was real. Its **scope** was not, and nothing in the output said so.

**Rule.** Read the discovery config before trusting a suite total, and name every path you ran. If
your runner has a `testpaths`-style setting, treat it as a *claim about scope* that must be
reconciled against the packages actually in the repo. Either pass every path explicitly, or say which
paths you ran instead of writing the words "full suite".

### A negative grep proves absence only inside what you searched

Immediately downstream of that gap: a peer cited a test file, a grep of the (narrower) test directory
returned nothing, and the citation was confidently corrected as a relay error -- in a message about
verification discipline. The file existed, one directory over.

**Rule.** Never conclude a file or symbol does not exist from a scoped grep. Search the whole repo,
or ask the VCS for the tracked file list. **When CI names a path you cannot find, look harder before
doubting CI.**

### Two Windows traps that make a present thing read as missing

Both returned a confident false negative, and neither raised an error.

- **Path length.** A tracked, on-disk file reported as non-existent to the language runtime while the
  shell could see it. It strikes the **deepest** paths first -- exactly the nested package
  directories other tooling already under-covers. Extract or check out to a **short root**, and
  assert extraction completeness by file count before believing any "does not exist".
- **Shell path translation.** A `revision:path` argument was rewritten into a mangled single token,
  so the command failed on stderr while the piped counter printed `0` -- indistinguishable from "the
  string is not there". Never pipe a revision-scoped file read straight into a counter: capture it,
  check the return code, and require non-empty output before trusting a zero.

The trap inside the trap: the *adjacent* form of that command -- a revision with no slash in it -- is
unaffected. A quick reproduction attempt therefore gives a false all-clear. **When you reproduce
someone's reported negative, reproduce the exact form, not an adjacent one.**

---

## The required-check set

The set of merge-blocking checks lives server-side, where a clone cannot read it. That single fact
generates most of the traps in this section.

**Rule, before anything else.** Mirror the required-context list into a checked-in file that is the
canonical in-repo claim, and add a test that reconciles every prose statement against it. Read that
file -- or query the API -- before asserting anything about what gates a merge. **A count you recall is
always stale.** Prose describing the set drifted in three directions at once in one audit: an in-repo
page understated the required set by four blocking security gates and named one context by a string
that matched no job. Measured on the repo this tooling was developed in, protection passed through
six distinct configurations in a single day.

| Trap | What it looks like | Rule |
|---|---|---|
| Context recorded as the **workflow** name | Required context never matches anything that reports | Protection matches the **job** name (falling back to the job key when the job declares no `name`). Derive the string from the workflow file and verify it against a real run |
| Required but absent | Every PR sits on "Expected -- waiting for status to be reported"; nothing failing, nothing running | Before you path-gate, schedule-gate or fork-break a job, confirm it is not required. Add a job to the required list only after watching it report on a real PR |
| Branch predates a new required check | Same wedged symptom, one branch only | Bring the branch up to date; never edit protection to unstick a branch |
| Conditional / matrix legs required directly | A skipped leg reports a name that no required string matches | Roll them up (below) |
| Fork-incompatible job required | Outside contributions can never go green | Cannot be required; gate on its *ability to fail* instead (below) |

The wedged-PR symptom deserves naming once: **nothing is failing and nothing is running.** That state
is not diagnosed by staring at the checks tab, and the tempting remedy -- relaxing protection -- treats
the alarm as the fault.

### Roll up conditional legs behind one stable context

Heavy, path-gated and matrix legs cannot be required directly. A push-only leg reports *skipped* on
every PR. A matrix leg reports an **unexpanded** job name when skipped and an **expanded** one when
it runs, so no single context string matches both states. Requiring them wedges every PR; leaving
them out means a real regression in them cannot block a merge.

Add one roll-up job that depends on the conditional legs, runs unconditionally, and fails only on a
failed or cancelled dependency -- **a skipped dependency passes**:

{% raw %}
```yaml
  gate:
    needs: [heavy-leg, matrix-leg, path-gated-leg]
    if: always()
    runs-on: ubuntu-latest
    steps:
      - name: Fail on any failed or cancelled dependency
        run: |
          echo "results: ${{ join(needs.*.result, ',') }}"
          case "${{ join(needs.*.result, ',') }}" in
            *failure*|*cancelled*) echo "a required dependency did not pass"; exit 1 ;;
          esac
```
{% endraw %}

Require the roll-up, not the legs. Note what this does: it makes its dependencies **transitively
required** even though they appear nowhere in protection. Write that down next to the job, because
the next person to read protection will not see them.

### Some checks can never be required -- gate on the ability to fail

A code-scanning upload needs a write permission that fork-PR tokens do not have. Another analysis job
has no pull-request trigger at all. Requiring either blocks outside contributors or wedges every PR,
so the useful signal ends up advisory -- and *advisory* quietly becomes *nobody notices when it
breaks*.

**Rule.** For an advisory scanner, gate the merge on the scanner's **ability to fail** rather than on
its run: put a test inside the always-run required suite that drives the same shipped detector
against a deliberately injected defect and asserts it fires. A change that blinds the detector then
reds the PR even though the scan itself never gates.

That is the technique `bin/ccx-doctor.ps1` generalises -- it fires each control at a case the control
exists to refuse, and pairs every attack with a **negative control**, an ordinary action the same
control must allow. A script that refuses everything is not a working guard either, and a probe with
no positive control proves nothing.

### A doc is not a control

Every in-repo statement about which checks gate a merge, which jobs are advisory, and which jobs must
never acquire write scopes was prose. Prose drifted in all three directions at once.

**Rule.** Back each load-bearing CI claim with a test:

- one reconciling every prose statement against the canonical required-context file;
- one refusing an error-swallowing shape on any job backing a **required** context -- `continue-on-error`,
  a job-level skip condition, a trailing exit-zero suffix on the command that produces the verdict;
- one failing if an **advisory** workflow ever gains a write scope, an upload, or loses its
  non-blocking flag, so promoting one to blocking is equally deliberate.

The point of the second test is that the check *name* survives every one of those edits while the
enforcement does not. Pin the advisory jobs the other way for the same reason. And lint the workflow
files themselves -- see [*An invalid workflow expression*](#pipeline-shape-for-a-repo-several-sessions-push-to).

---

## A check that cannot fail is not a control

Three defects across two advisory gates spent months green in one estate. Two gates were measuring
nothing; the third measured correctly and published a wrong number. In every case a broken run and a
clean run printed identically. **Nobody investigates a green check** -- which is what makes this whole
class expensive.

### Read a workflow for what it can report, not for what it runs

A smoke workflow had `continue-on-error` on every step, every post-setup step gated on setup
succeeding, **and** `continue-on-error` on the job. Setup fails, everything skips, green. Smoke
fails, swallowed, green. Five runs, five successes, and nothing in that record could distinguish a
canary that flew from one that never left the ground.

**Rule.** For every check ask: *is there any input for which this goes red?* If no, it is decoration
-- delete it or give it teeth. Belt-and-braces error-swallowing stacked on top of triggers that
already guarantee non-blocking buys nothing and costs the entire signal.

### A job-level conclusion answers a different question than a step-level one

An advisory job carrying `continue-on-error` reports `conclusion: success` even when one of its steps
failed outright. Reading the job badge proves only that the job was **allowed** to be green.

The same shape shows up in shells: an exit code read through a pipe belongs to the **last** command,
so piping a failing scanner into a pager or a line counter prints `0` over a failing scan. (Worked
example in [`TIPS-AND-TRICKS.md`](TIPS-AND-TRICKS.md) section 5.)

**Rule.** When you need to know whether work actually succeeded, read the per-step conclusions and
confirm the produced artefacts exist and are **non-empty** -- a byte size, not just a name. Never
branch on a job conclusion for a step-level question.

### Receipts: count what the check examined, never what it found

Concrete cases from the same estate: a coverage gate whose shallow fetch destroyed its comparison
base, so the empty report looked clean; a mutation gate whose tool crashed before generating a single
mutant while a trailing `|| true` reported success in 37 seconds. One of those gates had been scored
"Built" across two published versions of a rubric while producing zero units of work.

**Rule.** Every gate publishes proof of execution: **units examined** -- files scanned, lines
analysed, cases processed, detectors loaded -- non-zero whenever the tool ran, whatever it concluded.
Make zero-units-examined exit non-zero, so a schema or path change cannot read as a clean sweep. Then
add a separate job that reads the receipts and demands either proof of execution or an explicit
reason.

Never make a check fire on *good news*. A clean codebase legitimately reports zero findings, and a
check that alarms on health gets muted. The receipt is the unit count; the verdict is separate.

`bin/ccx-doctor.ps1` prints what it scanned on **every** run -- config roots found, session records
read, records that could not be placed, worktrees enumerated, which interpreter -- pass or fail. That
block is the receipt.

### "Nothing to measure" passes only when it is stated and reasoned

A coverage tool prints the same *"no lines with coverage information in this diff"* message when the
change legitimately touched no measured source **and** when the coverage data itself measured
nothing. Its template branches on the coverage data, never on the diff size. The two outcomes are
byte-identical on screen; only the reason distinguishes them.

**Rule.** Let a gate report not-applicable, but require it to state **why**, derived from an input it
actually inspected. A silent empty result is a failure, not an exemption. The reason is the
load-bearing part -- it is what a reviewer checks against reality.

There is a sharper version for inputs. An absent *default* input directory may skip, with a stated
reason and a receipt. An **explicitly given** path that does not exist must **fail** -- that is what
catches a typo'd or renamed input directory. Publish which of the two happened.

### A reconciliation containing a derived term is blind to that term

A mutation gate validated `killed + survived + no-tests + other == total`. But `killed` was derived
as `total - listed`, so the identity reduces to *"every listed mutant carries a recognised status"*
and **any** value of `killed` satisfies it. A run that genuinely processed 461 mutants and reported
`killed = 0` sailed through the sum check.

**Rule.** Count each part independently, never as a remainder, and cross-check any derived headline
figure against a genuinely independent second measurement -- here, the tool's own progress counter. Do
the algebra when you write a reconciliation: **if a term cancels, the check cannot see it.** Assert
the reconciliation in a test, and where you keep a weak check, keep a test that documents its
blindness rather than deleting it silently.

### Attack the control with the failure class it was built to catch

The liveness gate written to catch gates-that-never-ran was found, in adversarial review before
merge, carrying **all three** of its own failure modes. A dead measurement could pass by declaring
itself not-applicable, an empty results file reported a flawless score, and its reconciliation was
algebraically blind.

Separately, a regression test "guarding" a shipped helper defined a *local copy* of the rule and
asserted against the copy. It never called the shipped function, so it would pass however the real
code behaved.

**Rule.** A check is evidence only once you have made it fail **on purpose** and confirmed the
injected defect actually landed. Prove a new guard by injecting the same regression into both the old
and new versions and showing the old survives while the new kills it. Add regression tests for the
good-news cases too, so you prove both that it fires and that it does not fire spuriously. If a test
re-implements the logic it guards, treat that as a design signal -- parameterise the shipped function
so the test can call the real thing.

### The advisory layer needs exactly one job permitted to go red

If every job in an advisory workflow is non-blocking, nothing enforces that the advisory layer
measures anything, and the scorecard keeps counting gates that stopped working.

**Rule.** Make the advisory jobs structurally unable to block a merge, and make exactly one job -- the
one that verifies the others ran and reconciles their numbers -- the one permitted to fail.

### A cost model built on a broken gate is fiction

A gate was placed on a nightly-only schedule and excluded from PRs because it was assumed expensive.
When the tool was actually repaired, it completed the same bounded scope in seconds. The placement
decision had been made on a number the broken tool never produced.

**Rule.** Re-derive placement and cost after any gate repair, and treat a cost figure quoted from
before a fix as **unmeasured**.

---

## Flakes

### Prove a failure is timing-dependent before calling it a flake

A UI test failed on and off and was triaged as a slow-runner flake. Timeout widening and automatic
reruns were applied; neither helped. It was a **livelock**: an in-flight guard cleared, re-fired a
latched refresh, and returned before rendering, discarding every snapshot as superseded -- measured at
391 reads served and 0 rendered over 20 seconds. Permanently stuck, not slow. It passed locally only
because the local startup ordering never entered the polling path.

Separately, a scheduled-job test reported as failing was simply **correct**: it asserted the job had
not fired, and the job genuinely had not. Re-running it "to clear the flake" would have buried a true
negative.

**Rule.** Before calling anything a flake, make it fail **deterministically** -- force the race to be
lost every time. If you cannot, you have not established timing-dependence. And establish that the
assertion is **wrong**, not merely inconvenient: a test failing for being right looks identical to
one failing for being flaky.

### Identical counters across runs do not prove determinism

A load assertion failed with byte-identical numbers across two runs, two branches and different
ephemeral ports. That was read as "deterministic, a real bug, do not re-run" -- and the very next
re-run passed. Several counters were fixed by the test profile and the rest quantised onto the same
values under similar contention.

**Rule.** Take the cheap third data point -- one re-run -- before asserting determinism from repeated
values. The sound half of that reasoning still holds and is worth keeping: **a failure that
reproduces on the trunk was not caused by the change under test.**

### Automatic reruns convert an unfixed defect into an invisible one

Blanket rerun-on-failure is a flake anaesthetic. It cannot heal a livelock or a deadlock, and a
masked failure looks exactly like a working test. It is also **exception-class scoped**: a rerun
filter restricted to assertion errors will not touch a test that dies on a timeout, so the fix
silently does nothing for the flake class that hurt most.

**Rule.** Fix flakes at the source. Use reruns only as a bounded, per-test, documented measure, with
the class of failure they target written down -- and check the rerun predicate actually matches the
failure type you are seeing.

### Poll the condition you assert, not a related earlier one

The recurring shape: the test waits for an **early** signal (a file appearing when delivery
completes) and then immediately asserts a **later** one (the store having finalised the record). On a
slow runner the early signal wins and the later assert reads empty. The same race hit a container
smoke step that grepped the logs once, the instant after stop, before the final buffered line
flushed.

**Rule.** Poll the actual asserted condition, with a bounded timeout. Never widen a fixed sleep, and
never assert a downstream state right after observing an upstream one. Make failure messages name the
violated expectation -- a bare assertion costs a whole triage round trip.

### Never assert a substring against random bytes

A test proved data was stored encrypted by asserting a plaintext marker string was absent from the
on-disk bytes. Those bytes are base64 of random ciphertext, and the base64 alphabet contains the
marker's characters, so the three-character run appeared by chance roughly one run in N -- on the fast
runner, with no timing component at all. It read as a flake and blocked an unrelated merge.

**Rule.** Assert the property the substring was proxying for: a version/format marker prefix,
inequality with the plaintext, and a decrypt round trip. Flake-free, and a strictly stronger check.

### A failure that reproduces on the trunk is not your regression

A native-level crash inside a database driver intermittently killed a test leg. Time was spent
bisecting the branch. It also hit the trunk, on unrelated commits -- an upstream driver defect.

**Rule.** Before bisecting your own diff, check whether the same failure appears on the trunk or on
unrelated PRs. **If every open PR goes red at once, suspect repo-wide tool or dependency drift**
rather than your change; that pattern reads exactly like your diff broke something when it did not.

---

## Landing it

Merge-state mechanics -- the four "can't merge" states, the pre-squash merge base, conflict resolution
-- live in [`PR-AND-MERGE.md`](PR-AND-MERGE.md) and are not repeated. What follows is the CI-timing
half.

### Push everything before arming auto-merge, then assert the head revision

Auto-merge squashes whatever revision went green. A follow-up commit pushed about a minute after
arming lost the race. The squash landed the **earlier** revision, keeping even the pre-push title.
Meanwhile the monitor truthfully reported zero failing checks and a merged state for work that was
not on the trunk. The merge looks completely successful and nothing warns you.

**Rule.** Push every commit **first**, then arm auto-merge, then assert the PR's head revision equals
your local `HEAD`. That one comparison is the whole defence. After any auto-merge, verify the
**content** landed by searching the merged trunk for a token from the change -- never infer it from a
merged status.

### A bare re-run does not pick up a newer base

A PR went red because the trunk had changed under it. A re-run was issued and failed identically,
repeatedly. The merge reference stays pinned to the old base until the branch itself is pushed, so
the re-run was re-testing the same broken combination hours later.

**Rule.** To revalidate against a moved trunk you must update the branch and push; re-running the job
is not a substitute.

**Corollary.** When a required gate *changes*, treat every already-green open PR as **unverified** --
their green was measured against the old gate.

### Sequence the queue deliberately

With up-to-date-with-base enforced and no merge queue, the trunk takes **at most one merge per CI
cycle**. Landing a zero-urgency PR therefore knocks every sibling behind and costs each of them a
full cycle.

**Rule.** Land the PR that unblocks others first. Arm auto-merge and move on rather than hand-merging
-- hand-merging loses the race against a moving trunk and needs a whole fresh cycle; that was observed
three times in one session. Read the merge **state** (behind / blocked / clean), never the presence
of an auto-merge request, when judging whether a PR can actually land, and keep a capped
update-branch loop rather than trusting the platform to bring stale branches current.

### A monitor that polls "nothing pending" is blind to a check that never starts

An absent check has no pending entry, so a query for *zero checks with a null conclusion* reads
identically to *everything finished successfully*. During a window when the required set had been
misconfigured down to a single context, a waiter reported GREEN without ever waiting for a test leg --
there was nothing to wait for. A related near-miss: filtering check runs to success-or-skipped
**first** made three in-progress required legs look missing.

**Rule.** Reconcile a CI wait against the list of checks that **should** gate the merge, not against
the absence of pending ones. Query state first and classify afterwards -- never filter before you have
the full set. The three-armed watcher loop in [`PR-AND-MERGE.md`](PR-AND-MERGE.md) is the working
version.

### Default filters, scopes and pagination answer a narrower question, and report no error

Four instruments, one shape:

| Instrument | Default | The narrower question it answered |
|---|---|---|
| Run-jobs listing | latest attempt | A step killed at the timeout cap is invisible behind its passing re-run. A claim that a certain duration "does not exist in 449 runs" was nearly published; it existed, on attempt 1 |
| Check-runs listing | 30 per page | The run being looked for returned empty and read as a real null |
| Repo-scoped endpoint | this repository | Answered a confident zero to a question whose data lives at a different scope |
| Job conclusion | job level | Drops the tightest step-level samples by construction |

**Rule.** Before believing *"it does not happen"*, ask whether your method could have **seen** it
happen -- a default filter, an endpoint's scope, a page size, a sample too small. *"It does not
happen"* and *"my method cannot see it happening"* print identically. Compute it a second way,
ideally with a second tool, and treat disagreement as the signal.

### Do not idle on a long pipeline -- and know when waiting is right

A full suite takes roughly fifteen minutes and a session does many pushes. Foreground waiting after
each push is the single largest source of dead time, and polling buys nothing a notification does
not.

Push or arm the merge, then move to the next task; if the outcome must be observed, start a
background watcher. **Wait only when** the next action depends on the outcome, the follow-on work
would be built on a change that might be reverted, or the push has not been verified as landed.

### "Tooling unavailable" is a fallback, not a diagnosis

A CI-status panel's message advising that the CLI may not be installed or authenticated was in fact
its **unclassified-error branch**. At least four distinct upstream causes reach it. One of them: the
tool resolved a PR number against the **wrong repository**, because the working directory belonged to
a sibling checkout. That last cause is not hypothetical for anyone running several worktrees.

**Rule.** Treat a generic *"unavailable -- check your setup"* string as **undiagnosed**. Verify auth
independently, then run the same query with the target repository named explicitly and compare. If a
status panel ever shows a plausible but *wrong* result, suspect a scope or identity mismatch before
suspecting the data.

---

## Pipeline shape for a repo several sessions push to

These are the structural decisions, rather than the moment-to-moment ones.

### Two tiers, and say which is which

Running every check on every proposal is slow and expensive. Moving the expensive legs off the PR
means a defect only those legs catch lands on the trunk first -- and if nobody watches the trunk runs,
it sits there.

**Rule.** Split deliberately: comprehensive-and-fast on every proposal; expensive (real databases,
service installation, load, breadth suites) on the trunk and on a schedule. Wire an alert on trunk
and nightly breakage, gate the heavy legs through a **roll-up** rather than requiring them directly,
and state the trade-off in the docs instead of implying full coverage per PR.

### Run supply-chain audits on a schedule, not only on PRs

An audit that runs only on pull requests never fires for a repository whose dependencies did not
change, so an advisory published against a pin you already hold is invisible until someone happens to
open a PR.

**Rule.** Run dependency and supply-chain audits **daily** as well as on PRs, so a new advisory
against an unchanged pin surfaces within about a day and starts the remediation clock without anyone
reading an advisory mailing list.

### Constrain every install site from a checked-in lock

Install steps that resolved from lower-bound version floors made CI a fresh dependency resolution on
every run. Upstream releases then landed silently. A linter's stricter defaults produced hundreds of
new errors, and a transitive package dropping an export broke an unrelated dependency. Each of those
reddened **every open PR** on the same day, and every contributor read it as their own change
breaking something.

**Rule.** Constrain every install site from a checked-in lock, and have a gate re-export the lock and
diff it, so a dependency change cannot land without regenerating **all** of the lock artefacts. Check
your ignore rules while you are there: a new lock artefact whose name matches a broad ignore pattern
is silently never committed.

### Same-commit registration gates, and the bot with no path to green

Several CI-only gates require a new security-relevant artefact to be registered in an inventory
**and** its documentation row added in the same change. Two changes merging in parallel each
satisfied their own half and broke the trunk.

The nastier variant: a file was added to a gate's *regenerate-and-diff* list but not to the automated
dependency bot's regeneration workflow. The bot pushed a partial refresh, the gate found the missing
file stale, and the PR was red with **no bot-reachable path to green** -- meaning every future
dependency bump needed a hand fix.

**Rule.** When you add a file to a gate's regenerate-and-diff set, grep for every **other** place that
regenerates that set -- including automation you do not run yourself -- and update them in lockstep.
Ideally, pin that with a test asserting the two lists match. Any gate a bot must satisfy needs the
bot's fixer changed in the same commit.

### A skip is not a pass -- sweep for the old path after moving anything

Relocating one scanner script broke three checks the same way, and all of them looked green from
outside:

- a **required** CI job logged *"script absent -- skipping"* and exited zero;
- a test passed locally only because the developer tree happened to hold a git-ignored input;
- two parity tests skipped at module level because a loader still pointed at the deleted path.

A relocation sweep estimated at "a couple of references" was **32 references across 19 files**.

**Rule.** After moving any file a gate depends on, grep the whole tree for the **old** path and treat
every hit as a potential silent skip. Run the suite with skip reasons displayed on anything that
guards something. And never let a check "skip when its script is missing" -- **missing tooling is a
hard failure**.

### An invalid workflow expression aborts compilation, so no jobs are created

Templating expressions are interpolated anywhere inside a run script -- comments included -- before the
shell ever sees it. A stray or invalid expression aborts workflow compilation entirely: no jobs are
created, the run is attributed to a phantom event, and required contexts silently never appear. The
only visible symptom is *the PR is stuck*, and the tempting remedy is relaxing branch protection. A
security-focused workflow linter does not catch this; a **syntax** linter does.

**Rule.** Run a workflow syntax linter from a **pre-commit hook** scoped to the workflow directory.
The hook is the load-bearing half, because a workflow-lint CI job is usually paths-filtered and
therefore not a required check. Never make "remember to lint the workflow" the mechanism for a
failure whose symptom is a wedged PR.

### Route matrix values and secrets through env, never inline in a run script

A dynamically built matrix defeats static analysis of the workflow, which then flags the value's
expansion inside a run script as template injection. Suppressing the rule is the tempting fix and the
wrong one.

**Rule.** Pass the value through an `env:` entry and reference the shell variable -- that is the
remedy, not a suppression. Same for any secret a step uses: write it to a file via an intermediate
env var rather than interpolating it into the script text.

### Package manifests are allowlists, not sweeps

A build that packages by *excluding* known-bad paths ships whatever nobody thought to exclude, and
the upload is irreversible.

**Rule.** Declare an explicit **allowlist** of what the published artefact contains, and add a
fail-closed gate that verifies the built artefact against it **before** the upload step. Verify the
published artefact once after release too -- checking the thing you built is not checking the thing
that shipped.

### Grandfather to a clean baseline, then ratchet

Turning on a broad ruleset against an existing codebase produces hundreds of violations, so the new
gate is either merged red -- training everyone to ignore it -- or abandoned.

**Rule.** Auto-fix what is safely fixable, suppress the residue **per line with the rule code named
in each suppression**, and enforce from that clean baseline so only new code must comply. Exclude
framework idioms at the specific layer that generates them rather than disabling the rule globally,
so genuine instances still fail elsewhere. No blanket suppressions.

A zero-findings run on a weak ruleset is a **start condition** for red-on-regression enforcement, not
a certificate.

### A required check pinned to one machine is a single point of failure

Routing a **required** check to a self-hosted runner with no hosted fallback means that if the box is
offline the check queues for up to about a day and then fails, freezing merges repository-wide -- not
just for the PR that noticed. Provisioning differences bite first. The first runs failed at
**setup**, not in tests, because the runner account could not self-install a language toolchain, and
because the shell the workflow steps declared was not on the machine `PATH`, which hosted images
provide by default.

**Rule.** Never make a required context depend on hardware only you can restart, without a fallback.
Pilot a runner change on a draft PR and confirm the runner is idle and reporting before making it
required. Expect setup-phase differences from hosted images -- pre-seeded tool caches, shell
availability, per-runner caches so concurrent jobs do not collide. Treat slower hardware as a **flake
amplifier**: fix the tests it surfaces properly rather than widening timeouts.

### The authoritative gate belongs where it cannot be bypassed

A local pre-commit hook is bypassable by whoever runs it, so any control that exists only locally is
advisory in practice regardless of intent. `scripts/hooks/push_guard.py` says exactly this in its own
header -- a guardrail, not a security boundary -- and it is the honest posture, not an apology.

**Rule.** Run cheap checks locally for fast feedback **and** server-side for authority. For anything
that must survive a bypassed local hook, use the two-layer shape: a local hook plus an ungated CI
backstop that cannot be skipped. `scripts/hooks/seq_check.py` is that shape -- the pre-commit hook is
the fast half, `--ci` against a freshly fetched trunk is the half that catches the stale-base
collision the local hook is structurally unable to see.

### Repo-wide mechanical sweeps need a quiescent window

A hundred-file import sort or formatter migration conflicts with every in-flight parallel session,
and the conflicts are mechanical noise that hides real changes.

**Rule.** Schedule sweeps as a dedicated pass when no other session is in flight, land them alone,
and announce them. **Never bundle a sweep with a behavioural change.**

---

## Part 1 in one table

| Symptom | What it actually was | Rule |
|---|---|---|
| Local quartet green, CI red | Gates with no local invocation | List the CI-only checks; name the commands you ran |
| Gate exits non-zero locally | Fails closed without its credential | Distinct, self-describing exit state for "no credential" |
| Gate green in CI, red locally | Depends on an env var only one job sets | Confirm the gate is at least as strong in CI |
| A hundred findings CI never sees | Local run used the tool's default scope | Copy CI's exact command line, path arguments included |
| "Full suite" passed | Discovery config excluded a package | Read `testpaths`; name every path you ran |
| "That file does not exist" | Grep scoped narrower than the repo | Search the whole tree, or ask the VCS |
| PR stuck, nothing failing | A required check that never reports | Never require a job you have not watched report |
| Skipped leg blocks the PR | Matrix / path-gated leg required directly | Roll up behind one unconditional context |
| Scanner green for months | Nothing was ever measured | Publish units **examined**; zero units exits non-zero |
| "Nothing to measure" | Could be a dead gate or a real no-op | Require a reason derived from an inspected input |
| Sum check passes on a wrong number | A term was derived as a remainder | Count parts independently; cross-check with a second measurement |
| Job badge green, step failed | `continue-on-error` at job level | Read step conclusions and artefact sizes |
| "It's a flake" | Livelock, or a test that was right | Make it fail deterministically before you believe timing |
| Re-run fails identically | Base is pinned until the branch is pushed | Update the branch and push; re-running is not revalidation |
| Merged, but the change is absent | Auto-merge squashed an earlier revision | Push all, then arm, then assert the head revision |
| Every open PR red at once | Repo-wide tool or dependency drift | Check the trunk before bisecting your diff |
| Required check queues for a day | Pinned to one self-hosted machine | Never require hardware without a fallback |
| Required job logged "skipping" | Its script had moved | Missing tooling is a hard failure, never a skip |

---

# Part 2: standards that survive agent-written code

An agent writes code and, more dangerously, writes **prose about the code**. Confident, well-formed,
internally consistent prose that a correctness review passes. This part is mostly about that, because
it is where the failures are hardest to see and cheapest to prevent.

## Review prose by what a reader would DO with it

A correctness review terminates at *"yes, that sentence is accurate"*. In one documentation audit
**every** finding passed that test. Each was true about the mechanism and misleading about the
posture -- a sentence that survives every spot-check while pointing the reader somewhere they cannot
go. Six such findings were caught by asking what happens to someone who acts on the sentence; none
was caught by accuracy checking.

**Rule.** For every load-bearing sentence, name the action a reader takes after reading it, and ask
whether that action **succeeds**. If it fails, the sentence is defective no matter how accurate it
is. Accuracy review is a floor, not the review.

The four subsections that follow are the specific shapes this audit kept finding.

### State a load-bearing fact once, link to it, and let the copy die

A repo that states a fact twice will eventually state it two ways, and **the stale copy is the one
that gets cited** -- a reader who finds *a* statement stops looking for the other. Three instances
landed in a single day:

- a capability described identically across five live documents when the underlying API did not
  provide it at all;
- a superseded claim left in one document after the code closed it, from where it propagated into a
  public page *and* an internal review;
- one section asserting a class of data never appears in a URL, while a later section of the same
  file documented the parameters that carry it.

In every case the repo held both the right and the wrong version.

**Rule.** Pick the source of record for each load-bearing fact, link to it everywhere else, and
delete the restatement. The mitigation is **structural, not diligence** -- you cannot out-discipline a
duplicated fact.

#### The one exception: short imperatives at the point of use

Applied absolutely, *never restate* pushes rules into a reference nobody opens mid-task, and a
pointer that is not followed changes no behaviour.

**Rule.** Duplicate a rule only when it is a **one-line imperative that cannot meaningfully drift**,
and only where the work happens. Anything with a mechanism, a number, or a caveat in it gets stated
once and linked -- those are the shapes that drift. (This document does exactly that with
[`PR-AND-MERGE.md`](PR-AND-MERGE.md) and [`TIPS-AND-TRICKS.md`](TIPS-AND-TRICKS.md).)

### A completeness claim is a liability -- prefer "at least"

*"Two configurations do X, and a reviewer should hear both"* invites the check and then survives it,
because a reader who confirms the named case stops looking. One documentation set twice shipped such
a sentence wrong in **both directions at once** -- naming a case that no longer existed while omitting
one that did.

**Rule.** Where you cannot enumerate exhaustively and keep the enumeration current, write "at least",
name the case that matters, and point at the reference that holds the full list. Reserve exhaustive
enumerations for sets **a test can verify**.

### A compensating control must not rest on a false premise

A browser-header relaxation was justified on the grounds that the URLs involved carried only opaque
identifiers -- untrue of one route. The control itself was sound; the stated reason was not. **The
next person to touch it reasons from the comment, not from the code.**

**Rule.** Review the justification as rigorously as the control. A wrong justification is worse than
no justification, because it survives review and licenses the next change. If you cannot state a true
reason, say the reason is unverified.

### Confirm your instrument answers the question you asked

Eleven claims were retracted across four parallel sessions in a single night, and every one traced to
an instrument answering in **adjacent terms**:

| The question asked | What the instrument returned |
|---|---|
| Is the tree dirty? | Is there an *unstaged* delta -- on a file already staged |
| Did this work land? | Is this commit an ancestor -- always *no* under squash-merge |
| Is the installed copy worse? | Are these two hashes different |
| Who is live now? | Who was live when the banner printed |
| Does the file contain CRLF? | Does the *diff* render a carriage return -- it called a byte-perfect file mangled |
| Did the command succeed? | The exit status of the last command in the pipe |
| What did the suite ever do? | What the *latest attempt* did |
| Did the step succeed? | Whether the job was allowed to be green |

**Rule.** Before publishing a measured claim, write down the question and write down what the
instrument returns, and check they are the **same sentence**. Re-reading caught none of the eleven; a
check that could fail caught one immediately.

#### Dating a claim does not protect it

It is tempting to treat a wrong measured claim as a fact that expired, and to fix it by adding *"as
of `<date>`"*. One retracted claim -- that a pull request never merged because it died on CI -- was
never true at any instant: that request's timeline carried exactly one close event, simultaneous with
the merge.

**Rule.** Treat a measured claim as **live until re-derived**, not as true-as-of-a-date. When a claim
matters, re-run the measurement rather than annotating it, and record the instrument alongside the
number so the next person can re-run it too.

Dates are still required on figures in a publication-facing summary -- a page that headlines
approximate test counts and a multiplied "total runs" figure will be quoted months later as current
fact. Date it, say the counts vary as the suite grows, and point at the workflow files as the source
of truth for what runs. Prefer *"about N as of `<date>`"* to a bare number.

#### State a rule as a question that outlives its examples

Rules written as a list of known-bad instruments rot. One of the examples in the table above misleads
only because that repository squash-merges, and any of them may stop being true without the
underlying rule changing at all. Readers then pattern-match against the list and miss the instance
that is not on it.

**Rule.** Write the rule as the **question**. Mark the examples explicitly as dated illustrations. If
the examples were deleted, the rule should still be actionable.

---

## Say which kind of claim you are making

### Built is not on-by-default is not fail-closed is not independently verified

Counting controls marked "Built" conflates four different states. A control can ship disabled; a
control read as "off" may actually be fail-closed. The inverse error is equally real -- a wrongly
pessimistic reading is as much a defect as an optimistic one.

**Rule.** Score those states separately and re-verify each against the current code before crediting
or docking it. A capability statement says nothing about the default posture: **state the default
explicitly.**

### Tag every claim with its honesty state and a pointer a reviewer can open

Documentation optimism is the default failure of assistant-written prose: a control is described as
implemented before the code exists, and the description is confident enough to survive review.

**Rule.** Tag each claim as **built / designed-but-deferred / aspirational**, and require a code or
workflow pointer for anything marked built. Keep a claims register with the exact approved wording
and its evidence. No claim ships without a pointer a grader can open.

### Use the register you actually have: aligned, built-to, self-assessed

Standards bodies that publish control catalogues generally issue no certificate, so "certified"
phrasing describes something that does not exist. "Verified against X" asserts a completed
verification that an in-progress survey does not support, and a rosier count reached via a
non-standard verdict category is not rescuable by narrowing the scope.

**Rule.** Say *built to*, *aligned with*, or *self-assessed against*, and back each with evidence.
Where an incomplete survey exists, **unread items are unverified -- which is explicitly not a pass**.
A self-attestation is a formal declaration: only make it if it is true.

### Keep one canonical verdict-of-record

When a rosier status document survives alongside the canonical one, the optimistic one gets quoted --
by outsiders, and eventually by the team. A dated snapshot also gets read as current posture long
after the code moved.

**Rule.** Name one document as the verdict-of-record, and retire or explicitly annotate every
superseded status doc so only one composite can be cited. Date every snapshot and mark it as a
snapshot. **Conflicting in-tree scorecards are a live defect, not a presentation nit.**

### Measure the adoption of a convention before citing it as evidence

A provenance convention was listed as retained audit evidence while its measured adoption was
**zero** -- no occurrences across 300 commits, dozens of tracked files instructing that it be omitted,
and a required merge check that rejected it outright. Evidence that does not exist cannot be produced
on request, and citing it is worse for a reviewer than declaring the gap.

**Rule.** Before citing a convention as evidence, **count it in the actual history**. If the count is
zero, record it as designed-and-blocked, name the structural blocker, and add a drift test that fails
if the claim is reinstated while the practice still contradicts it. Anything enforced by convention
alone is not a control -- it fails silently the moment attention moves.

### Correct a published overclaim visibly

Silently editing a claim that was already published leaves everyone who acted on the old wording
holding it, and erases the reason the wording was wrong.

**Rule.** Strike it in place, with the reason, the date, and the replacement wording. Keep volatile
counts out of the narrative page entirely -- hold them in one record and link to it -- so the prose
cannot go stale against the record.

### Run a refutation pass on any number you are about to build a rule on

Several widely circulated statistics about AI-authored code failed adversarial verification when
checked: headline percentages that did not reconcile with their own sources, and vendor-telemetry
figures repeated through secondary blogs. Building a rule on an alarm-bell number means the rule dies
with the number.

**Rule.** For each load-bearing claim, have independent reviewers try to **refute** it, and drop the
ones that fall. Carry the survivors with their limitations attached -- correlational, vendor-sourced,
or model-era-specific -- and re-baseline periodically rather than quoting a fixed magnitude.

### Do not claim a speed or quality gain you have not measured here

**[external]** -- not measured here. The best-controlled trial available measured 16 experienced
developers on mature repositories as roughly **19% slower** with early-2025 AI tooling, while they
forecast, and afterwards still believed, that they had been faster. It is a single small trial on one
tooling generation, which is exactly why it is quoted for its *direction of surprise* and not as a
magnitude. Benchmark pass rates on isolated tasks say nothing about repo-scale correctness or
maintainability either.

**Rule.** Claim what the process actually buys -- auditability, continuity, safety, reviewability --
and leave speed unclaimed unless you measured it in your own context. **Self-reported velocity is the
least reliable signal in the set.**

---

## What the agent decides, and what you decide

Split by **reversibility and reach**. Treating *"the human approved this task"* as approval for
everything downstream is how an outward-facing action ships without anyone choosing it -- and with
auto-merge enabled, opening a pull request effectively **is** merging.

| The agent decides | You decide |
|---|---|
| When to commit -- coherent, tested, one layer at a time, narrated | Push, pull request, merge, release |
| Which files to touch inside the approved plan | Deletions, installs, migrations, anything irreversible |
| How to structure the change | Anything outward-facing or public |

**Never work around a gate** with a bypass flag or a rename. If a gate fires, fix the cause. The
split itself is a one-line imperative, and appears at the point of use in
[`TIPS-AND-TRICKS.md`](TIPS-AND-TRICKS.md) section 3 (*"commit at logical stops; ask before push, PR
and merge"*). That repetition is exactly the exception described above, and nothing else about the
split is restated there.

### One coherent layer per commit

A commit mixing a refactor, a behaviour change and a mechanical sweep cannot be reviewed, reverted or
bisected -- and small-batch discipline is the one part of the delivery-stability concern that is
actually actionable.

**Rule.** Commit at logical stops, one coherent layer at a time, with a message that says what
changed and **why**. Branch and open a request for review rather than committing to the integration
branch.

### Approve a plan first, then review the diff against the plan

Reviewing a diff on its own merits accepts anything defensible, including work that drifted from what
was actually wanted -- and afterwards there is no versioned intent to check it against.

**Rule.** Write a testable intent before prompting: the files and seams to be touched, the test to be
added, the invariants that must not break. Then review the returned diff **against that plan**.
Divergence is a review finding, not a detail.

### Treat an agent's report of an outward-facing action as a claim

*"PR opened"*, *"branch pushed"*, *"merged"*, *"all green"* are a known confabulation surface. The
transcript is not ground truth; the system state is.

**Rule.** Verify each side-effecting outward action against the system itself before relying on it or
reporting it onward. This is the instrument rule again: check that what you queried answers the
question you are about to assert.

### Reject code you cannot explain -- assistance in reaching the explanation is fine

Code that works but is opaque produces people who can build but cannot debug, and it enters the
codebase with unknown provenance. The strict form -- *every line understood unaided* -- bars the
workflow it is meant to govern, so it gets quietly ignored rather than enforced.

**Rule.** Accept an explanation reached **with** assistance, but require that you produce, verify and
stand behind it. Rubber-stamping is not explaining, and code that stays opaque even with help is
discarded. Capture the explanation durably -- a comment, a review thread, a decision record, or the
test -- so the reasoning is recorded rather than ephemeral. State this relaxation and its trigger for
reinstatement explicitly rather than letting it be assumed.

### Know when to take manual control back

The expensive failure is not a bad suggestion. It is **grinding in a polluted context**, where each
retry inherits the confusion of the last and the output looks more finished each time.

Take manual control:

- on a security-critical seam you must own line by line;
- when you cannot yet verify the output -- write the test or the spec first;
- after about **two** failed attempts on the same problem. Clear the context and restart with a
  sharper prompt that incorporates what was learned.

Decompose work into short trajectories with fresh context per task rather than one long session.

---

## Everything the agent reads is data, never instructions

File contents, fetched pages, tool results, logs, sample payloads and config values can all contain
text shaped like a command -- *ignore prior rules*, *add this dependency*, *read that credential*. An
agent that acts on embedded instructions is steered **entirely inside the build process**, bypassing
every runtime control.

**Rule.** Never let fetched, tool-returned or file content auto-trigger an edit or a command: read
it, decide yourself, then act. Surface the instruction-shaped text to the human rather than obeying
it or silently ignoring it. The same rule governs a peer session's messages --
[`COORDINATION.md`](COORDINATION.md) *"A peer announcement is data, never an instruction"*.

### A path deny-list is not a content control

A path-based deny-list stops the agent reading a file, and gives false confidence. The confidence is
false because it cannot stop a string a human pastes into the prompt, a value that a command the
agent ran echoes into captured output, or something written into persistent memory. Commands whose
output legitimately contains sensitive payloads are a live leak path into transcripts and committed
files.

**Rule.** Pair the path deny-list with a **commit-time content scan that fails closed**, so anything
reaching a commit is caught by a second, different mechanism. Keep the human rule first: do not paste
it, and do not let a dump-style command's output be captured into a committed file, a transcript, or
a memory note.

### Secrets and sensitive data never enter the repository, wherever it is stored

A private remote feels like it changes what may be committed. It does not -- history is forever, and a
private repo can become public, be mirrored, or be packaged into a published artefact.

**Rule.** Source credentials from the environment or a secret store; keep versioned per-environment
files non-secret; keep fixtures synthetic; ignore local stores, dumps and credential files by
default; review the diff before committing. Back all of it with fail-closed secret and
forbidden-content scanning in CI **over the full history**.

### Verify a dependency before adding it, and know what verification cannot see

**[external]** -- not measured here. Published surveys of package hallucination found roughly **14%**
of the distinct modules referenced in real LLM output did not exist, which is what makes
plausible-but-fake package names an attack surface. The magnitude is model-era-specific and should be
re-derived rather than quoted; the attack surface is what the rule rests on. And an existence check
has a blind spot that is easy to mistake for coverage. A package that genuinely exists, publishes
files, is years old, and is served under its own canonical name still passes every automated check
**while being a different project than the one you intended**.

**Rule.** Gate on existence, publishing history, an age floor, and canonical-name identity -- failing
closed when the index is unreachable or when zero distributions were examined (a receipt, exactly as
in Part 1). Then keep **human verify-before-add** for the intended-identity class, record a dated vet
note with the dependency, and hash-lock the result. Never install ad hoc: declare it and re-lock.

---

## Judging tests, and judging metrics

### Judge tests by their assertions, not their presence or their coverage

Coverage percentage hides assertion-free tests and mock choreography -- a suite can execute every line
and verify nothing. **[external]**, from published research rather than measured here: mutation score
is a poor linear proxy on its own (largely a suite-size artefact), but top-decile suites catch
materially more real faults -- so mutation is valuable as **guidance** precisely where coverage is
blind.

**Rule.** Require value and negative-path assertions against real behaviour over mock-call
assertions, and run mutation on changed code as advisory guidance a human reads. Treat a high
proportion of *"was this called"* assertions as a smell to review, not a metric to gate.

### Never gate on a single gameable number

The metrics teams reach for first are weak or inverted predictors. Every figure in this table is
**[external]** -- published software-engineering research, none of it measured here:

| Metric | What the evidence says |
|---|---|
| Raw cyclomatic complexity | **[external]** Correlates with real defects at roughly **0.06**; largely a proxy for line count |
| Vendor "cognitive complexity" | **[external]** No incremental predictive value over traditional measures |
| Static-analysis severity counts | **[external]** Across 33 large projects, flagged classes were no more fault-prone than clean ones |
| High line coverage | The canonical place bad code hides, when assertions are weak |

**Rule.** Surface these as **advisory triage a human arbitrates**; never let one be the pass/fail. Let
machine-enforced structure -- layer boundaries, strict typing, behaviour-verifying tests, dependency
integrity -- carry the verdict, and judge by the composite, never by any single row.

### There is no validated universal threshold

Adopting a numeric cutoff from a blog or another project imports a constant the evidence does not
support, and then defends it as if it were external authority.

**Rule.** Set thresholds per project from your own accumulating data, record them in the project's
own appendix, and flag any directional target as **project-set, not evidence-certified**. Review them
as data accumulates.

### Blocking and advisory are not the same coverage

A long tool inventory reads as security posture, but advisory and cron-only jobs never turn a pull
request red. Counting them as coverage inflates the number without adding a gate.

**Rule.** Count coverage by the **blocking jobs that actually run on the change**, verified by
reading the workflow file -- not by tool count and not by a green checkmark.

---

## Ship the guard the same day as the rule

A rule stated in prose alone erodes silently. Nobody notices the day it stops being followed, and the
standard keeps describing a practice that ended months ago.

**Rule.** For every rule you write into a standard, name the machine check that will catch its
violation -- or record explicitly that it is **convention-only and therefore unenforced**. Where a
claim is at risk of being reinstated wrongly, write a drift test that fails if the document and the
repository disagree.

### Enumerate sibling paths for every control

An assistant implements a control exactly where it was prompted and misses its siblings. In one
audit, **every** confirmed medium-or-higher finding had this shape: a guard live on one operating
system and a no-op on another; a check on one destructive verb but not its counterpart; a scope check
on the record routes but not the topology reads.

**Rule.** When a change adds or modifies a control, list the sibling paths it should also cover --
other connectors, routes, platforms, CRUD verbs, publish targets -- and either cover them or record
the gap as a finding. Where the parity can be encoded as **one deterministic check over all
instances**, prefer that to a recurring manual sweep.

This is why `scripts/coord/install-git-hooks.ps1` installs into the shared git hooks directory: one
file governs every worktree of the clone at once. It also sees **every write route** -- an edit tool, a
shell redirect, an editor, a subagent -- because it inspects the tree rather than a tool call. There
are no siblings to miss.

### Exercise a new control in the real environment, not just the test written beside it

An over-strict guard that passes the unit test written alongside it can still break CI and ordinary
developer workflows. One config-trust guard refused the default developer checkout layout entirely
until an audited escape was added; its own test never covered that case.

**Rule.** Run any newly added control against real development, CI and production-like conditions
before calling it done. **A control validated only by the test authored with it has been validated by
the same reasoning that produced it.**

### Fail-open or fail-closed is a choice you must state

Both defaults are defensible and the wrong one is invisible until it matters: a workflow guard that
fails closed wedges everyone's work when it errors; a security boundary that fails open silently
stops protecting anything.

**Rule.** Decide per guard by **what it protects** -- workflow guards fail open so they never wedge
work, security boundaries fail closed -- and write the choice **and its reason** next to the code.
Every gate in `scripts/hooks/` declares its posture in its own header for this reason; see
[`HOOKS.md`](HOOKS.md). Any relaxation for development must be an explicit, named, audited escape
that is never set in production.

### State what a gate does not prove

A dry-run gate ran real inputs through the real production core with no external side effects, so
*"green in CI behaves identically in production"* was true -- and got over-read. It checks for
**absence of error**, not correctness of output: a transform producing valid-but-wrong output passes
cleanly.

**Rule.** For every gate, write down the class of defect it **cannot** see, and name the separate
discipline that covers it -- golden input/output pairs, reconciliation, a soak window. Prefer *"at
least these are covered"* to an enumeration that reads as completeness.

Two shipped examples of this being done honestly: `scripts/hooks/seq_check.py` states that its two
modes are **not symmetric** and which rule cannot run under `--ci`; `bin/ccx-doctor.ps1` prints its
own blind spots on every run, whether or not anything failed.

### Reserve globally unique identifiers from a shared registry, never by scanning

Isolated parallel sessions cannot see each other's new global identifiers. Two sessions that each
pick "the next free number" from their own checkout create differently named files, **merge clean**
with no conflict to catch it, and silently corrupt the ledger. One identifier was independently
claimed by three concurrent branches, and the collision surfaced only after merge.

**Rule.** Allocate the number atomically against a shared registry before use, add the index entry in
the same commit, reconcile against the integration branch before merge, and back it with a hook that
rejects a number the session did not allocate. Never grep for the next free number. Mechanism and
worked example: [`SEQUENCE-ALLOC.md`](SEQUENCE-ALLOC.md), `scripts/coord/alloc.ps1`,
`scripts/hooks/seq_check.py`, and the annotated original in
`examples/ledger_check.annotated.py`. Its comments are the transferable part, including why the
CI mode must use a two-dot diff and how the three-dot version failed **silently**, reporting PASS on
every run where it could not see.

### One working tree per session

Two concurrent sessions sharing a checkout interleave edits, stage each other's files, and produce
commits neither session intended.

**Rule.** Give each parallel session its own isolated checkout, branch and environment; share only
the remote. Coordinate writes to any shared state -- notes, memory, ledgers -- as single-writer. See
[`WORKTREES.md`](WORKTREES.md) and [`CONCEPTS.md`](CONCEPTS.md).

---

## Part 2 in one table

| When | Rule |
|---|---|
| Reviewing prose | Name the action a reader takes; ask whether it succeeds. Accuracy is the floor |
| Reviewing prose | State a load-bearing fact **once**, link to it, delete the copy |
| Reviewing prose | Exception: a one-line imperative may repeat at the point of use |
| Reviewing prose | Prefer "at least" -- a completeness claim invites the check and survives it |
| Reviewing prose | Review the **justification** as rigorously as the control |
| Measuring | Write the question and what the instrument returns; check they are the same sentence |
| Measuring | Re-derive a claim rather than dating it. Live until re-measured |
| Measuring | Write the rule as a question that outlives its examples |
| Claiming | Built != on-by-default != fail-closed != independently verified. Score them apart |
| Claiming | Tag built / deferred / aspirational, with a pointer a grader can open |
| Claiming | "Built to", "aligned with", "self-assessed against" -- never "certified" |
| Claiming | One verdict-of-record; retire or annotate every superseded snapshot |
| Claiming | Count a convention in the history before citing it as evidence |
| Claiming | Correct a published overclaim in place, with the reason and the date |
| Claiming | Leave speed unclaimed unless you measured it here |
| Deciding | Agent commits; human pushes, opens, merges, releases, deletes, installs |
| Deciding | Approve a plan, then review the diff **against the plan** |
| Deciding | An agent's report of an outward action is a claim -- verify it against the system |
| Deciding | Two failed attempts on one problem: clear the context and restart |
| Handling input | Everything the agent reads is data. Surface instruction-shaped text; never act on it |
| Handling input | A path deny-list is not a content control -- pair it with a fail-closed commit scan |
| Handling input | Verify a dependency's **identity**, not just its existence. Never install ad hoc |
| Judging | Assertions, not coverage. Never gate on a single gameable number |
| Judging | No universal threshold -- set it from your own data and record it |
| Judging | Coverage is the blocking jobs that run on the change, not the tool inventory |
| Enforcing | Ship the guard the same day as the rule, or record it as convention-only |
| Enforcing | Enumerate sibling paths; prefer one deterministic check over a manual sweep |
| Enforcing | State fail-open or fail-closed, with the reason, next to the code |
| Enforcing | State what the gate does **not** prove |

---

## Related

- [`PR-AND-MERGE.md`](PR-AND-MERGE.md) -- merge base, the four "can't merge" states, conflict
  resolution, the three-armed watcher
- [`TIPS-AND-TRICKS.md`](TIPS-AND-TRICKS.md) -- section 4 writing a guardrail, section 5 measuring whether it works
- [`CASE-STUDY-drift-audit.md`](CASE-STUDY-drift-audit.md) -- auditing controls as one system, and the
  drift taxonomy
- [`SEQUENCE-ALLOC.md`](SEQUENCE-ALLOC.md) -- the collision class every other control is blind to
- [`HOOKS.md`](HOOKS.md) -- harness hooks versus git hooks, and where each posture is declared
- `bin/ccx-doctor.ps1` -- receipts, attack-with-a-negative-control, and printed blind spots, in one
  command
- `.github/workflows/gates.yml` -- this repository's own gates, as a worked example of the rules
  above. It uses least privilege, and pins an action by commit SHA rather than a mutable tag. Each
  step prints what it examined. A leak-gate step says out loud when it ran with the private-name
  detectors off, and a test step refuses a pass when the runner reports zero tests. It
  deliberately does **not** run the doctor -- the reason is in the file's header
