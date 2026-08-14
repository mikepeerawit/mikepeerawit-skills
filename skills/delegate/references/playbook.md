# Delegate playbook

Worked examples and the reasoning behind `SKILL.md`'s rules. `SKILL.md` holds what you need to *decide and act*; this file holds *why*, and is read on demand — when a rule looks wrong, or when a delegation goes sideways and you need to know which rule you broke.

> `delegate` is adapted from [`qwen-agent`](https://github.com/thananon/9arm-skills/blob/main/skills/engineering/qwen-agent/SKILL.md) in [thananon/9arm-skills](https://github.com/thananon/9arm-skills), generalized beyond its original Qwen-specific setup. Credit to 9arm for the underlying design.

## Why the threshold is two bars, not one

The bar is *>2k tokens **or** >5 files*, and either alone is enough. They catch different failures.

A 40-file rename of one-line changes is barely 2k tokens and still worth delegating, because 40 files is 40 chances to put a diff in your window. A single 5,000-line log is one file and clears the other bar on its own. Requiring both would let each of those through.

Size is a measurement, not a judgment call — estimate it (bytes ÷ 4 ≈ tokens) rather than deliberating about it. The payoff scales with how much output would otherwise land in your window, so the big jobs are where this earns its keep and the borderline ones barely matter either way.

## Reading "conversation context" narrowly

`SKILL.md` says not to delegate work that depends on decisions made earlier in this conversation. Read that narrowly, or it swallows everything: *every* task you meet is happening inside a conversation.

What disqualifies a job is depending on a decision, constraint or preference established here **that the prompt can't restate**. If you can write it down in the prompt, it isn't conversation context — it's just an instruction. "Use the naming convention we agreed" is conversation context. "Name them `get*` rather than `fetch*`" is an instruction, and delegable.

## Worked example

A job that clears the threshold — 31 files, none of which need to enter your window:

```
In /Users/x/proj/src, rename the exported symbol `fetchUser` to `getUser`
everywhere it appears — its declaration in /Users/x/proj/src/api/user.ts,
every import of it, and every call site. It appears in 31 files.
Rename nothing else, and do not touch filenames, comments or string
literals — leave any `fetchUser` inside those exactly as it is.
Then run `npx tsc --noEmit` from /Users/x/proj.
Done = (a) no `fetchUser` remains in *code* under src, and (b) tsc
reports no new errors.
Reply with at most 5 lines: the file count you changed, then PASS or
FAIL for (a) and for (b), then every surviving `fetchUser` line as
`path:line` — those should be comments and strings only.
```

Verify with `git diff --stat` (≈31 files, small per-file diffs?), `npx tsc --noEmit`, and `rg -wn fetchUser src` — whose output should match the surviving lines it reported, one for one. None of those reads a changed file.

Note what the carve-out costs: because comments and strings are excluded, "no `fetchUser` anywhere" is *not* the criterion, and a bare `rg` returning hits is not a failure. Say so in the prompt, or the delegate will either edit comments it was told to leave, or report FAIL on correct work.

Bad: `rename fetchUser to getUser` — no root path, no scope limit, no count to check against, no return contract.

### Describe the work, not the exercise

Wording that a literal model reads as an instruction *about* the task — test framing, a marker string to echo back, "this is a trial run" — displaces the task itself. It reasons about the exercise and writes nothing. Say what to change and what done looks like; never mention that you're testing it.

## Why there's no fallback

`AGENT_CMD` is a hard prerequisite. The obvious fallback — handing the job to a cheap Claude subagent — was removed, because it billed the very quota the skill exists to protect, and because it kept getting chosen *over* a configured backend: a subagent is a tool sitting in the model's list every turn, while `AGENT_CMD` is a variable the model has to go looking for. Emphasis didn't fix that asymmetry; deleting the option did. Full reasoning and the rejected alternatives: [ADR-0001](../../../docs/adr/0001-delegate-requires-a-configured-backend.md).

## Why commit first, and why tool scoping matters

**Commit or stash before any write task.** Then `git diff` shows exactly what the delegate did, and `git checkout --` undoes it in one move. A bad cheap-model edit mixed into your own uncommitted work has no clean revert — you're left picking apart two sets of changes by hand, which costs more than the delegation saved.

**Grant the narrowest tool set the task needs.** Read-only jobs — search, summarize, condense a log — get read tools only: no `Bash`, no `Write`. Tool scoping is what lets a job finish unattended without stalling on an approval prompt, but the same grant is the blast radius if the model misreads the task. Widen it deliberately, one tool at a time.

## Why a missing backend gets announced

Both "nothing configured" and "every backend down" end in the same place: do the work inline, and say so in one line.

The announcement is the whole point. A missing backend that nobody mentions stays missing — the skill degrades into contributing nothing while appearing to work, which is exactly the failure that made rank 0 worth deleting (see [ADR-0001](../../../docs/adr/0001-delegate-requires-a-configured-backend.md)). One line makes it visible, so it gets fixed once instead of silently costing you forever.

Announcing is also why the skill doesn't *stop and ask*. A config question costs more than the menial work it interrupts. Announce, proceed, move on.

## Why you don't re-run after a wrapper falls back

A wrapper fronting several backends handles its own ordering, and prints to stderr when it falls through. If you see that announcement, the work has already been redone on the next backend — running it again does it a third time, and on a write task that means double-applied edits.

The rule reduces to: **a backend-level failure you see reported is already handled; one you discover yourself is yours to handle.** Either way, tell the user a fallback happened and why. Silently spending money on a paid backend because a free one was down is a surprise, not a convenience.

## Context-window exhaustion, seen from the outside

You rarely get told the window overflowed. You infer it from the result: truncated edits, later instructions ignored while earlier ones landed, a summary that omits files it was told to touch. Any of those means split smaller and retry — not re-prompt at the same size.

This is also why you never guess a backend's window. The advertised figure and what the harness actually grants routinely disagree, and the card is the optimistic one; guessing high causes silent truncation, which is the failure mode you can't see from the output.

## Why a zero exit proves nothing

An agentic CLI exits 0 whenever the model completes a turn — including a turn where it read your prompt, decided nothing needed doing, and said so. Exit status tells you the *process* ran, never that the *work* happened. That's why verification starts with the acceptance criterion and not the return code.
