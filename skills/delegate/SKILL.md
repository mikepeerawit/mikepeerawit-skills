---
name: delegate
description: Route work that would dump a lot of tokens into this conversation to a cheaper model instead, protecting the quota and context window for work that needs real reasoning. Use BEFORE, not after: before reading a large file/log/dump, before a repo-wide search, before a bulk mechanical edit (renames, formatting, find-replace, boilerplate, test/docstring scaffolding), or before running a build/linter/test suite you only need pass-fail from. Rule of thumb: delegate when the job would add >2k tokens to this context OR touch >5 files; do it yourself only when it is under both. Also fires on "delegate this", "send it to a cheaper model", "use <model>", or "do this cheaply". Skip for architecture, design, debugging judgment, security-sensitive edits, or work that depends on decisions made earlier in this conversation.
---

# Delegate

Offload **bulky, self-contained** work to a cheaper model, so its output never enters this conversation. Adapted from [`qwen-agent`](https://github.com/thananon/9arm-skills) by 9arm.

## Is it worth delegating?

Delegate once the job clears **either** bar: **>2k tokens** into this context, **or** **>5 files**. Under *both*, do it yourself — writing a standalone prompt and checking the result costs more than a small job does. Estimate the size (bytes ÷ 4 ≈ tokens); don't deliberate about it.

**Delegate jobs, not steps.** Prompt-and-verify is a fixed cost, so five steps sent separately pay it five times. Send the whole job they add up to.

## The backends

A `;`-separated list of shell commands, **cheapest first**. Run the command — never assume the list is empty:

```bash
printenv DELEGATE_BACKENDS      # e.g. claude-9arm;claude-openrouter
```

Empty or unset → [no backend](#no-backend). Otherwise take the first entry:

```bash
claude-9arm -p "<self-contained prompt>" --allowedTools Read Glob Grep
```

Add `Edit Write Bash` only when the job must change files or run commands — a read-only job gets read-only tools. Without `--allowedTools` at all, the run stalls on the first approval prompt. Those flags are Claude Code's; other CLIs differ.

## When a backend doesn't answer

Two kinds of failure, two responses:

- **Backend-level** — connection refused, 5xx, timeout, auth rejected, or it exits having printed nothing but an error. The model never ran, so nothing is half-done: **re-run the same prompt against the next entry in the list.** Claude Code prints API errors to *stdout* and exits 1, so judge by the text, not the exit code.
- **Task-level** — it ran, but the output is wrong, truncated, or ignored instructions. A second backend won't do better on the same bad prompt. Fix the prompt, split the job, or do it yourself.

**Check `git status` before falling through.** If the first backend got far enough to edit files before dying, the next one re-applies those edits — that case is task-level, not backend-level.

Work down the list until one answers. Whenever the backend that ran wasn't the first, say so in one line and name it.

### No backend

`DELEGATE_BACKENDS` unset, or every entry failed at backend level. Both get the same response — **do the work inline and say so**:

> No delegate backend available — doing this inline, so its output lands in this window.

Never silently, and never stop to ask. There is deliberately no built-in fallback to a Claude subagent: it would keep the bulk out of the window but still bill the quota this skill exists to protect.

## Writing the prompt

The delegate has **zero** context from this conversation. A vague prompt is the #1 failure mode. Treat it as a capable-but-literal junior.

- **Absolute paths** for every input and output (`/Users/x/proj/src/foo.ts`, not `foo.ts`).
- **Explicit inputs, outputs and acceptance criteria** — what to change, what "done" looks like.
- **No references** to "the file we discussed", "above", or prior turns.
- **A return contract**, so the result is cheap to check:

  > Write your results to `<abs-path>`. Reply with at most 5 lines: files touched, and PASS or FAIL for each acceptance criterion.

Bad: `clean up the imports`
Good: `In /Users/x/proj/src/api.ts, remove unused imports and sort the rest alphabetically. Change nothing else. Confirm the file still parses.`

## Verify cheaply

You are the check on a less reliable model — but don't pay full price for it. In order:

1. **Run the acceptance criterion** — test, build, linter. Machine-checked beats read.
2. **`git diff --stat`** — right files, plausible size?
3. **Spot-check one file** — the trickiest, not all of them.

Read the full output only when those three disagree with the delegate's own report. **A zero exit is not an acceptance signal** — it means the CLI ran, not that the work is right.

Commit or stash before delegating, so `git diff` shows exactly what the delegate did and `git checkout --` undoes it.

## Mind the context window

The whole job — prompt, every file it reads, its own reasoning and edits — must fit the backend's window, which is far smaller than yours. Estimate it (bytes ÷ 4 ≈ tokens); take the figure from what the harness reports at runtime, never from memory.

Over the window, chunk into independent slices — one directory, one log segment per run. Give exact paths; never "scan the repo." Exhaustion shows up as truncated edits or ignored late instructions, not as an error: split smaller and retry.

## When NOT to delegate

Architecture/design, debugging that needs reasoning, security-sensitive changes, work depending on **decisions made earlier in this conversation**, jobs where a wrong cheap-model edit is costly to catch, or one that can't be sliced without whole-codebase context.

That third item is narrower than it sounds: what disqualifies a job is depending on something the prompt *can't restate*. In doubt about **judgment**, keep it; about **size**, the threshold decides.

## Setup (one time)

Only needed when `DELEGATE_BACKENDS` is unset — the user sets this up, not you. Full walkthrough in the repo README; the shape:

```sh
#!/bin/sh
# ~/.local/bin/claude-cheap — an executable on PATH, not an alias
exec claude --settings "$HOME/.claude-cheap.json" --model=<cheap-model-id> "$@"
```

```bash
export DELEGATE_BACKENDS="claude-cheap"      # or "claude-free;claude-paid"
```

The `--settings` file holds that provider's base URL, key, and **all five** model slots pinned — unset slots fall through to Anthropic model IDs, which a third-party provider serves at list price. To stop per-call prompts, allow each wrapper: `"Bash(claude-cheap:*)"`.
