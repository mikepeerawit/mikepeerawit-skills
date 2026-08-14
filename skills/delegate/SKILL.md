---
name: delegate
description: Delegate menial, well-scoped coding tasks to a cheaper subagent model to reduce the primary model's token burn — save its tokens/quota for work that needs real reasoning. Use when the work is mechanical and low-risk — bulk renames, formatting, boilerplate, find-replace, grep-style search & summarization, reading/condensing logs or files, test/docstring/comment scaffolding, or running builds/linters/tests and reporting pass-fail. Also use when the user says "delegate this", "send it to a cheaper model", "use <model>", or "do this cheaply". Do NOT use for architecture, design, debugging judgment, security-sensitive edits, or anything needing this conversation's context.
---

# Delegate

> Adapted from [`qwen-agent`](https://github.com/thananon/9arm-skills/blob/main/skills/engineering/qwen-agent/SKILL.md) in [thananon/9arm-skills](https://github.com/thananon/9arm-skills), generalized beyond its original Qwen-specific setup. Credit to 9arm for the underlying design.

Offload **menial, self-contained** tasks to a cheaper model, so the primary model's tokens/quota stay reserved for work that actually needs reasoning.

## Workflow

1. **Confirm it's delegable** — menial and low-risk. Needs design judgment or this chat's context? Do it yourself ([when NOT to](#when-not-to-delegate)).
2. **Pick the backend** by [rank](#backends-ranked) — a configured `AGENT_CMD` always beats rank 0; among configured ones, cheapest first unless someone's waiting or the task needs a bigger window.
3. **Size it** — it must fit that backend's [context window](#mind-the-context-window); split large jobs into bounded chunks.
4. **[Make it safe to be wrong](#make-it-safe-to-be-wrong)** — commit or stash first, grant the narrowest tool set.
5. **[Write a self-contained prompt](#writing-the-prompt-most-important-step)** — absolute paths, acceptance criteria, return contract. This step decides success.
6. **[Verify cheaply](#verify-cheaply)** — check the work without re-reading it.

## When NOT to delegate

Architecture/design, debugging that needs reasoning, security-sensitive changes, anything requiring this conversation's context, or tasks where a wrong cheap-model edit is costly to catch. If a job can't be sliced cleanly — it needs whole-codebase context to do correctly — that's also a sign. When in doubt, keep it.

## Backends, ranked

The real axis is **which quota you spend**, not raw price.

| Rank | Backend | Setup | Spends | Use when |
|---|---|---|---|---|
| 1+ | `AGENT_CMD` — a headless agentic CLI on a cheaper backend | one-time, per model | that provider's credit, or nothing if it's free | **whenever one is configured** |
| 0 | Native subagent — the subagent tool with a cheap model (e.g. `model: "haiku"`) | none | the same Anthropic quota you're protecting | fallback only |

**If an `AGENT_CMD` backend is configured, use it. Never pick rank 0 over a configured backend** — rank 0 bills the very quota this skill exists to protect, so choosing it while a cheaper backend sits configured defeats the point. Check for `AGENT_CMD` before you decide; don't assume it's absent.

Rank 0 is the fallback, for exactly two cases: nothing is configured, or every configured backend is down. When nothing is configured, use rank 0 and say so — don't stop to ask a config question before doing menial work, that costs more than it saves. Rank 0 still keeps the job's token dump out of *this* conversation's window, which is worth having on its own; it just isn't the saving the skill advertises.

Keep configured backends as an ordered list, cheapest first, each carrying its `CONTEXT_WINDOW`, cost and typical latency. Take `CONTEXT_WINDOW` from what the harness reports at runtime, not the model card — they routinely disagree and the card is the optimistic one. **Never guess a configured backend's window:** guessing causes silent truncation, which is the failure you can't see.

Setting `AGENT_CMD` up the first time is covered in [`references/setup.md`](references/setup.md). Read it only when `AGENT_CMD` doesn't exist or doesn't work.

### Choosing between them

This is about ordering the **configured** backends among themselves — rank 0 isn't in the running unless none of them is. Cost-first is the default; override it for the task in front of you:

- **Someone's waiting on the result** → fastest backend that fits. A 50% latency saving is worth a cent. A wrapper that ranks internally tries the cheap backend first regardless, unless the user has already told you theirs supports [pinning](references/setup.md#optional-pinning-one-backend) — then prefer a pin over re-running. Otherwise take the default order rather than stopping to ask: an unhonoured pin is ignored in silence and reads exactly like a working one.
- **Background, parallel or batch work** → keep the default order. Nobody's watching the clock.
- **Needs more context than rank 1 offers** → drop to the first backend whose window fits, rather than splitting the task into chunks that no longer make sense on their own.

### When a backend fails

- **Backend-level** (connection refused, 5xx, gateway timeout, auth rejected): the model never ran. If `AGENT_CMD` announced a fallback of its own, it already did this for you — don't re-run. Otherwise drop to the next backend and re-run the *same* prompt. Don't retry the dead one — outages outlast your patience. A backend you pinned has no next one — that's what the pin bought; drop it deliberately and say so, or report the failure. Only once **every** configured backend is exhausted does rank 0 come into play, and it puts the spend back on the quota you were protecting — so say that out loud rather than falling into it quietly.
- **Task-level** (it ran, but the output is wrong, truncated, or ignored instructions): falling back gains nothing, because a cheaper model won't do better. Fix the prompt, split the task, or do it yourself.

Tell the user whenever a fallback happens, and why — whether you or `AGENT_CMD` performed it. Silently spending money on a paid backend because a free one was down is a surprise, not a convenience.

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

```
In /Users/x/proj/src/api.ts, remove unused imports and sort the remaining
import statements alphabetically. Change nothing else.
Then run `npx tsc --noEmit` from /Users/x/proj.
Done = the file still parses and tsc reports no new errors.
Reply with at most 5 lines: the imports you removed, then PASS or FAIL for tsc.
```

Verify with `git diff --stat` (one file, imports only?) and `npx tsc --noEmit`. Neither re-reads the file.

Bad: `clean up the imports` — no path, no criteria, no return contract.

## Verify cheaply

You are the check on a cheaper, less reliable model — but don't pay full price for it. In order:

1. **Run the acceptance criterion** — the test, the build, the linter. Machine-checked beats read.
2. **`git diff --stat`** — right files, plausible size? A 400-line diff for "sort imports" fails without reading a line of it.
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

On the rank-0 fallback, pass that same self-contained prompt to the subagent tool with a cheap model instead — nothing else changes.

Those flags are Claude Code's; other CLIs differ. Headless flags, tool scoping, working directory, structured output and background/parallel runs are all in [`references/setup.md`](references/setup.md).
