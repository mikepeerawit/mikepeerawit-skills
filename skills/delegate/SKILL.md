---
name: delegate
description: Route work that would dump a lot of tokens into this conversation to a cheaper model instead, protecting the quota and context window for work that needs real reasoning. Use BEFORE, not after: before reading a large file/log/dump, before a repo-wide search, before a bulk mechanical edit (renames, formatting, find-replace, boilerplate, test/docstring scaffolding), or before running a build/linter/test suite you only need pass-fail from. Rule of thumb: delegate when the job would add >2k tokens to this context OR touch >5 files; do it yourself only when it is under both. Also fires on "delegate this", "send it to a cheaper model", "use <model>", or "do this cheaply". Skip for architecture, design, debugging judgment, security-sensitive edits, or work that depends on decisions made earlier in this conversation.
---

# Delegate

Offload **bulky, self-contained** work to a cheaper model, so its output never enters this conversation. Requires a configured [`AGENT_CMD`](#the-backend).

Reasoning, worked examples and post-mortems: [`references/playbook.md`](references/playbook.md). Setup: [`references/setup.md`](references/setup.md). Adapted from [`qwen-agent`](https://github.com/thananon/9arm-skills) by 9arm.

## Is it worth delegating?

Delegate once the job clears **either** bar: **>2k tokens** into this context, **or** **>5 files**. Under *both*, do it yourself. Size is a measurement — estimate it (bytes ÷ 4 ≈ tokens) rather than deliberating.

**Delegate jobs, not steps.** Prompt-and-verify is a fixed cost, so five steps sent separately pay it five times. Send the job they add up to, bounded by the [context window](#mind-the-context-window) and by whether you can describe it without referring back to this conversation.

## Workflow

1. **Catch it before you act** — the moment *before* a large read, repo-wide search, bulk mechanical edit, or a suite run you need pass-fail from. Check the [threshold](#is-it-worth-delegating), then the [keep-it list](#when-not-to-delegate).
2. **Find the backend — run the command, don't assume the answer:**

   ```bash
   printenv AGENT_CMD
   ```

   Non-empty → delegate to that. Empty → [no backend](#no-backend-available). Never conclude a backend is absent without running this.
3. **Size it** — the whole job must fit that backend's [window](#mind-the-context-window).
4. **Make it safe** — commit or stash first, so `git diff` shows what the delegate did and `git checkout --` undoes it. Grant the narrowest tool set: read-only jobs get no `Bash`, no `Write`.
5. **[Write a self-contained prompt](#writing-the-prompt)** — this step decides success.
6. **[Verify cheaply](#verify-cheaply)**.

## When NOT to delegate

Architecture/design, debugging that needs reasoning, security-sensitive changes, work depending on **decisions made earlier in this conversation**, jobs where a wrong cheap-model edit is costly to catch, or one that can't be sliced without whole-codebase context.

Read that third item [narrowly](references/playbook.md#reading-conversation-context-narrowly) — what disqualifies a job is depending on something the prompt *can't restate*. In doubt about **judgment**, keep it; about **size**, the threshold decides.

## The backend

**`AGENT_CMD`** — a headless agentic CLI on a cheaper backend. A hard prerequisite: [there is no built-in fallback](references/playbook.md#why-theres-no-fallback).

```bash
$AGENT_CMD -p "<self-contained prompt>" --allowedTools Read Glob Grep   # add Edit Write Bash only if needed
```

**You do not rank backends — `AGENT_CMD` does.** If its owner configured several, the wrapper tries them cheapest-first and handles its own fallback. Run the one command and read what comes back. Those flags are Claude Code's; other CLIs differ.

### No backend available

`printenv AGENT_CMD` empty, or every backend behind it down. Both get the same response — **do the work inline and [say so](references/playbook.md#why-a-missing-backend-gets-announced) in one line**:

> No delegate backend available — doing this inline, so its output lands in this window.

Never silently, and never stop to ask.

### When a backend fails

- **Backend-level** (connection refused, 5xx, timeout, auth rejected): the model never ran, so re-running is safe. If `AGENT_CMD` announced a fallback on stderr it already did this — [don't re-run it yourself](references/playbook.md#why-you-dont-re-run-after-a-wrapper-falls-back). If it exhausted its backends, that's [no backend](#no-backend-available).
- **Task-level** (it ran; output wrong, truncated, or ignored instructions): re-running gains nothing. Fix the prompt, split the job, or do it yourself.

Tell the user whenever a fallback happened, and why.

## Writing the prompt

The delegate has **zero** context from this conversation. A vague prompt is the #1 failure mode. Treat it as a capable-but-literal junior.

- **Absolute paths** for every input and output (`/Users/x/proj/src/foo.ts`, not `foo.ts`).
- **Explicit inputs, outputs and acceptance criteria** — what to change, what "done" looks like.
- **No references** to "the file we discussed", "above", or prior turns.
- **Describe the work, not the exercise** — never mention that you're testing it.
- **A return contract**, so the output is cheap to check:

  > Write your results to `<abs-path>`. Reply with at most 5 lines: files touched, and PASS or FAIL for each acceptance criterion.

[Worked example, with the mistakes it avoids](references/playbook.md#worked-example).

## Verify cheaply

You are the check on a cheaper, less reliable model — but don't pay full price for it. In order:

1. **Run the acceptance criterion** — test, build, linter. Machine-checked beats read.
2. **`git diff --stat`** — right files, plausible size?
3. **Spot-check one file** — the trickiest, not all of them.

Read the full output only when 1–3 disagree with the delegate's own report. **A [zero exit is not an acceptance signal](references/playbook.md#why-a-zero-exit-proves-nothing).**

## Mind the context window

The whole job — prompt, every file it reads, its own reasoning and edits — must fit. Estimate it (bytes ÷ 4 ≈ tokens); take the window figure from what the harness reports at runtime, not the model card, and **never guess it**.

Over the window, chunk into independent slices — one directory, one log segment per run. Give exact paths; never "scan the repo." [Exhaustion shows up in the result](references/playbook.md#context-window-exhaustion-seen-from-the-outside), not in an error: split smaller and retry.
