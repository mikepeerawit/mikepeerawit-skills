---
name: delegate
description: Route work that would dump a lot of tokens into this conversation to a cheaper model instead — protecting both the quota and the context window for work that needs real reasoning. Use BEFORE, not after: before reading a large file/log/dump, before a repo-wide search, before a bulk mechanical edit (renames, formatting, find-replace, boilerplate, test/docstring scaffolding), or before running a build/linter/test suite you only need pass-fail from. Rule of thumb: delegate when the job would add >2k tokens to this context OR touch >5 files; do it yourself only when it is under both. Also fires on "delegate this", "send it to a cheaper model", "use <model>", or "do this cheaply". Skip for architecture, design, debugging judgment, security-sensitive edits, or work that depends on decisions made earlier in this conversation.
---

# Delegate

> Adapted from [`qwen-agent`](https://github.com/thananon/9arm-skills/blob/main/skills/engineering/qwen-agent/SKILL.md) in [thananon/9arm-skills](https://github.com/thananon/9arm-skills), generalized beyond its original Qwen-specific setup. Credit to 9arm for the underlying design.

Offload **bulky, self-contained** work to a cheaper model. Two things stay protected, and they're worth naming separately:

- **Quota** — the primary model's budget, spent on reasoning instead of grunt work.
- **Context window** — the delegate's output never enters *this* conversation. Usually the one that matters: long sessions die of context exhaustion far more often than of quota.

Both require a configured [`AGENT_CMD`](#the-backend). Without one this skill has nothing to offload *to* — see [no backend available](#no-backend-available).

## Is it worth delegating?

Delegating isn't free — you pay to write a self-contained prompt and to verify the result. Delegate once the job clears **either** bar: it would add **>2k tokens** to this context, **or** it touches **>5 files**. Do it yourself only when it's under **both**.

Either bar alone is enough. A 40-file rename of one-line changes is barely 2k tokens and still worth delegating, because 40 files is 40 chances to put a diff in your window.

Above the bar, delegate. The payoff scales with how much output would otherwise land in your window, so a 5,000-line log or a 40-file rename is where this earns its keep.

Size is a measurement, not a judgment call — estimate it (bytes ÷ 4 ≈ tokens) rather than deliberating.

### Delegate jobs, not steps

The cost of delegating is roughly **fixed**: one self-contained prompt to write, one result to verify. That cost doesn't shrink when the job does — so the smaller the unit you hand over, the worse the trade. Handing over five steps separately pays that cost five times; handing over the job they add up to pays it once.

So before you delegate a step, look at what it's part of. If the next three things you were going to do are all delegable and all belong to the same job, send the **job**: "migrate every call site in `/abs/path/src` off the old API, then run the suite" beats three separate renames with a verification round between each.

The limits are the [context window](#mind-the-context-window) — the whole job must fit — and self-containment: a job you can't describe without referring back to this conversation isn't one job, it's [work you should keep](#when-not-to-delegate).

## Workflow

1. **Catch it before you act** — the trigger is the moment *before* a large read, a repo-wide search, a bulk mechanical edit, or a suite run you only need pass-fail from. Check the [threshold](#is-it-worth-delegating), then that it's [not on the keep-it list](#when-not-to-delegate).
2. **Find the backend — run the command, don't assume the answer:**

   ```bash
   printenv AGENT_CMD
   ```

   Non-empty → that is what you delegate to. Empty → [no backend available](#no-backend-available). Never conclude a backend is absent without running this.
3. **Size it** — it must fit that backend's [context window](#mind-the-context-window); split large jobs into bounded chunks.
4. **[Make it safe to be wrong](#make-it-safe-to-be-wrong)** — commit or stash first, grant the narrowest tool set.
5. **[Write a self-contained prompt](#writing-the-prompt-most-important-step)** — absolute paths, acceptance criteria, return contract. This step decides success.
6. **[Verify cheaply](#verify-cheaply)** — check the work without re-reading it.

## When NOT to delegate

Architecture/design, debugging that needs reasoning, security-sensitive changes, work that depends on **decisions made earlier in this conversation**, or tasks where a wrong cheap-model edit is costly to catch. If a job can't be sliced cleanly — it needs whole-codebase context to do correctly — that's also a sign.

Read that third item narrowly. *Every* task you meet is happening inside a conversation; what disqualifies a job is depending on a decision, constraint or preference established here that the prompt can't restate. If you can write it down in the prompt, it isn't conversation context — it's just an instruction.

In doubt about **judgment**, keep it. In doubt about **size**, the [threshold](#is-it-worth-delegating) decides — don't relitigate a measurement as a judgment call.

## The backend

Delegation goes to **`AGENT_CMD`** — a headless agentic CLI on a cheaper backend, spending that provider's credit rather than your Anthropic quota. It is a hard prerequisite: there is no built-in fallback, because the obvious candidate (a cheap Claude subagent) bills the very quota this skill exists to protect.

**You do not rank backends — `AGENT_CMD` does.** If its owner configured several, the wrapper tries them cheapest-first and handles its own fallback. Your job is to run the one command and read what comes back.

```bash
$AGENT_CMD -p "<self-contained prompt>" --allowedTools Read Glob Grep
```

Sizing is still yours: the job must fit the backend's [context window](#mind-the-context-window). Take that figure from what the harness reports at runtime, not the model card — they routinely disagree and the card is the optimistic one. **Never guess it**; guessing causes silent truncation, the failure you can't see.

Setting `AGENT_CMD` up is covered in [`references/setup.md`](references/setup.md). Read it only when `AGENT_CMD` doesn't exist or doesn't work.

### No backend available

Two ways to get here: `printenv AGENT_CMD` came back empty, or every backend behind it is down. Both get the same response — **do the work inline, and say so in one line**:

> No delegate backend available — doing this inline, so its output lands in this window.

Don't do it silently: a missing backend that nobody mentions stays missing, and the skill degrades into contributing nothing while appearing to work. Don't stop to ask, either — a config question costs more than the menial work it interrupts. Announce, proceed, move on.

### When a backend fails

- **Backend-level** (connection refused, 5xx, gateway timeout, auth rejected): the model never ran, so re-running the same prompt is safe. If `AGENT_CMD` announced a fallback of its own on stderr, **it already did this for you — don't re-run it yourself.** If it exhausted its backends, or has only one, that's [no backend available](#no-backend-available).
- **Task-level** (it ran, but the output is wrong, truncated, or ignored instructions): re-running gains nothing — a cheaper model won't do better on the second try. Fix the prompt, split the job, or do it yourself.

Tell the user whenever a fallback happened, and why — whether you or `AGENT_CMD` performed it. Silently spending money on a paid backend because a free one was down is a surprise, not a convenience.

## Make it safe to be wrong

- **Commit or stash first** on any write task. Then `git diff` shows exactly what the delegate did, and `git checkout --` undoes it. A bad cheap-model edit mixed into your own uncommitted work has no clean revert.
- **Grant the narrowest tool set the task needs.** Read-only jobs — search, summarize, condense a log — get read tools only: no `Bash`, no `Write`. Tool scoping is what lets a job finish unattended, but it's also the blast radius.

## Writing the prompt (most important step)

The delegate has **zero** context from this conversation. A vague prompt is the #1 failure mode.

- **Absolute paths** for every input and output (`/Users/x/proj/src/foo.ts`, not `foo.ts`).
- **Explicit inputs, outputs and acceptance criteria** — what to change, what "done" looks like.
- **No references** to "the file we discussed", "above", or prior turns.
- **Describe the work, not the exercise.** Wording a literal model reads as an instruction *about* the task — test framing, a marker string to echo back — displaces the task itself: it reasons about the exercise and writes nothing.
- **A return contract** (below). Treat the delegate as a capable-but-literal junior.

### The return contract

The delegate's output lands in *your* context verbatim. If checking its work costs what doing it would have, you saved nothing — so make the output cheap to check. Put this in the prompt:

> Write your results to `<abs-path>`. Reply with at most 5 lines: files touched, and PASS or FAIL for each acceptance criterion.

### Worked example

A job that clears the [threshold](#is-it-worth-delegating) — 31 files, none of which need to enter your window:

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

Note what the carve-out costs: because comments and strings are excluded, "no `fetchUser` anywhere" is *not* the criterion, and a bare `rg` returning hits is not a failure. Say so in the prompt, or the delegate will either edit comments it was told to leave or report FAIL on correct work.

Bad: `rename fetchUser to getUser` — no root path, no scope limit, no count to check against, no return contract.

## Verify cheaply

You are the check on a cheaper, less reliable model — but don't pay full price for it. In order:

1. **Run the acceptance criterion** — the test, the build, the linter. Machine-checked beats read.
2. **`git diff --stat`** — right files, plausible size? A 31-file rename that comes back touching 4 files, or rewriting 400 lines in one of them, fails without reading a line of it.
3. **Spot-check one file** — the trickiest one, not all of them.

Read the full output only when 1–3 disagree with the delegate's own report.

**A zero exit is not an acceptance signal** — an agentic CLI exits 0 whenever the model completes a turn, including one that did nothing you asked.

## Mind the context window

The whole job — prompt + every file it reads + its own reasoning and edits — has to fit inside the backend's window.

- **Estimate first:** bytes of the files it must touch ÷ 4 ≈ tokens.
- **Chunk large jobs** into independent slices — one file (or a few small ones), one directory, or one log segment per run.
- **Don't make it read what it doesn't need.** Exact paths; never "scan the repo."
- **Exhaustion symptoms** when verifying: truncated edits, ignored later instructions, a summary omitting files it was told to touch. Split smaller and retry.

## Running it

```bash
$AGENT_CMD -p "<self-contained prompt>" --allowedTools Read Glob Grep   # add Edit Write Bash only if the task needs them
```

Those flags are Claude Code's; other CLIs differ. Headless flags, tool scoping, working directory, structured output and background/parallel runs are all in [`references/setup.md`](references/setup.md).
