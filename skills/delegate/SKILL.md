---
name: delegate
description: Delegate menial, well-scoped coding tasks to a cheaper subagent model to reduce the primary model's token burn — save its tokens/quota for work that needs real reasoning. Use when the work is mechanical and low-risk — bulk renames, formatting, boilerplate, find-replace, grep-style search & summarization, reading/condensing logs or files, test/docstring/comment scaffolding, or running builds/linters/tests and reporting pass-fail. Also use when the user says "delegate this", "send it to a cheaper model", "use <model>", or "do this cheaply". Do NOT use for architecture, design, debugging judgment, security-sensitive edits, or anything needing this conversation's context.
---

# Delegate

> Adapted from [`qwen-agent`](https://github.com/thananon/9arm-skills/blob/main/skills/engineering/qwen-agent/SKILL.md) in [thananon/9arm-skills](https://github.com/thananon/9arm-skills), generalized beyond its original Qwen-specific setup. Credit to 9arm for the underlying design.

Offload **menial, self-contained** tasks to a cheaper model running headless, so the primary model's tokens/quota stay reserved for work that actually needs reasoning. Only delegate when the task is low-risk enough that a less capable model can be trusted with it.

## Workflow

1. **Confirm the task is delegable** — menial and low-risk. If it needs design judgment or this chat's context, do it yourself (see [When NOT to delegate](#when-not-to-delegate)).
2. **Pick the backend.** Confirm `AGENT_CMD` and `CONTEXT_WINDOW` are known for this project — if either is unknown, ask the user, never guess ([Configuration](#configuration)). Where more than one backend is configured, choose by [rank](#ranking-backends): cheapest first, unless someone is waiting on the result or the task needs a bigger context window.
3. **Size it** — check the task fits the delegate's context window; split large jobs into bounded per-file/per-dir chunks.
4. **Write a fully self-contained prompt** with absolute paths and acceptance criteria. This is the step that decides success.
5. **Run it** — foreground for a single job, background-redirected for parallel jobs.
6. **Verify the output yourself.** The delegate is cheaper and less reliable than you are. Check the result actually meets the acceptance criteria before reporting success.

## When NOT to delegate

Architecture/design, debugging that needs reasoning, security-sensitive changes, anything requiring this conversation's context, or tasks where a wrong cheap-model edit is costly to catch. When in doubt, keep it.

If a job is inherently too big to slice cleanly — it needs whole-codebase context to do correctly — that is also a sign it isn't a delegate task.

## Configuration

This skill is model-agnostic by design. Two values must be resolved once per model you delegate to:

- **`AGENT_CMD`** — the shell command that runs the target model headless with a prompt and can call tools unattended.
- **`CONTEXT_WINDOW`** — that model's context window in tokens, used to size delegated tasks. Take this from what the harness actually reports at runtime, not the model card — they routinely disagree, and the model card is the optimistic one.

**If either is unknown, ask the user — never guess.** Once known for this project, treat them as fixed for the rest of the task. If this becomes a repeat pattern, note the command in a project `CLAUDE.md` so future sessions don't have to ask again.

Setting `AGENT_CMD` up the first time — proxying Claude Code to a cheaper backend, using a different agentic CLI, smoke-testing it, and silencing repeat permission prompts — is covered in [`references/setup.md`](references/setup.md). Read that file only when `AGENT_CMD` does not yet exist or does not work.

## Ranking backends

Projects often have more than one delegate backend — a free-but-slow one, a paid-but-fast one, a local one. Keep them as an **ordered list, cheapest first**, each carrying the facts needed to choose between them:

| Rank | `AGENT_CMD` | `CONTEXT_WINDOW` | Cost | Typical latency |
|---|---|---|---|---|
| 1 | `<cmd>` | 200k | free | ~3 min/task |
| 2 | `<cmd>` | 200k | ~$0.01/task | ~2 min/task |

Cost-first is the default because that is the point of the skill. **Override it for the task in front of you:**

- **Someone is waiting on the result** → take the fastest backend that fits, not the cheapest. A 50% latency saving is worth a cent.
- **Background, parallel, or batch work** → keep the default order. Nobody is watching the clock, so cost wins.
- **Task needs more context than rank 1 offers** → drop to the first backend whose `CONTEXT_WINDOW` fits, rather than splitting the task into chunks that no longer make sense on their own.

### When a backend fails

**Distinguish a broken backend from a bad result** — they need opposite responses:

- **Backend-level failure** (connection refused, 5xx, gateway timeout, auth rejected): the model never ran. Drop to the next backend and re-run the *same* prompt. Don't retry the dead one — outages last longer than your patience.
- **Task-level failure** (it ran, but the output is wrong, truncated, or ignored instructions): falling back gains nothing, because a cheaper model won't do better. Fix the prompt, or split the task, or do it yourself.

Tell the user when you fall back, and say why. Silently spending money on a paid backend because a free one was down is a surprise, not a convenience.

## Writing the task prompt (most important step)

The delegate model has **zero** context from this conversation. A vague prompt is the #1 failure mode. Every prompt must be standalone:

- **Absolute paths** for every input and output file (`/Users/x/proj/src/foo.ts`, not `foo.ts`).
- **Explicit inputs, outputs, and acceptance criteria** — what to change, what "done" looks like.
- **No references** to "the file we discussed", "above", or prior turns.
- Treat the delegate as a capable-but-literal junior: spell out the steps, keep scope tight.

Bad: `clean up the imports`
Good: `In /Users/x/proj/src/api.ts, remove unused imports and sort the remaining import statements alphabetically. Do not change any other code. Confirm the file still parses.`

## Mind the context window

The delegate's context window (`CONTEXT_WINDOW`) is usually much smaller than the primary model's. The whole job — prompt + every file it reads + its own reasoning and edits — has to fit inside it:

- **Estimate the footprint** before delegating: roughly bytes of files it must read/open/write ÷ 4 ≈ tokens. If a single task would pull in large or many files, it won't fit.
- **Break large jobs into independent chunks** that each touch a bounded slice — one file (or a few small ones) per run, one directory per run, one log segment per run. Run chunks as separate invocations.
- **Don't make it read what it doesn't need.** Point it at exact files/paths; never tell it to "scan the repo."
- **Watch for context-exhaustion symptoms** when verifying: truncated edits, ignored later instructions, or a summary that omits files it was told to touch. These usually mean the task overflowed — split smaller and retry.

## Running a delegated task

```bash
$AGENT_CMD -p "<self-contained task prompt>" --allowedTools Bash Read Edit Write Glob Grep
```

Adjust flags to whatever `$AGENT_CMD`'s CLI actually supports — the flags above match Claude Code-style CLIs; other tools use different flags for headless/non-interactive mode and tool scoping.

- **Scope the tools explicitly.** This is what lets the subagent finish a menial job unattended — without it, most CLIs stall waiting for approval on the first edit or command.
- For edit-only, lower-risk tasks, some CLIs support an auto-accept-edits mode (e.g. Claude Code's `--permission-mode acceptEdits`). Shell commands still prompt under that mode — don't use it for verification/build/test runs.

**Working directory:** don't rely on cwd persisting across calls. Put absolute paths in the prompt, or pass whatever equivalent of `--add-dir /abs/path` the CLI supports to grant the subagent access to a directory.

## Return contract

- **Default (text):** the subagent's final message prints to stdout — read it directly.
- **Need to parse the result:** use the CLI's structured-output flag if it has one (e.g. Claude Code's `--output-format json`, reading the `result` field).
- **Background / parallel (run several at once):** redirect to a log and run in the background, then read the log when it finishes:

  ```bash
  $AGENT_CMD -p "<task>" --allowedTools Bash Read Edit Write Glob Grep > /tmp/delegate-<label>.log 2>&1
  ```

  Launch independent tasks as separate background runs; collect each log on completion. Use this when delegating 2+ unrelated menial jobs.
