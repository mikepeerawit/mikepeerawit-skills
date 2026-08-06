---
name: delegate-agent
description: Delegate menial, well-scoped coding tasks to a cheaper/faster subagent model (any model, not just Qwen) instead of burning the primary model's tokens/quota. Use when the work is mechanical and low-risk — bulk renames, formatting, boilerplate, find-replace, grep-style search & summarization, reading/condensing logs or files, test/docstring/comment scaffolding, or running builds/linters/tests and reporting pass-fail. Also use when the user says "delegate this", "send it to a cheaper model", "use <model>", or "do this cheaply". Do NOT use for architecture, design, debugging judgment, security-sensitive edits, or anything needing this conversation's context.
---

# delegate-agent

> Adapted from [`qwen-agent`](https://github.com/thananon/9arm-skills/blob/main/skills/engineering/qwen-agent/SKILL.md) in [thananon/9arm-skills](https://github.com/thananon/9arm-skills), generalized beyond its original Qwen-specific setup. Credit to 9arm for the underlying design.

Offload **menial, self-contained** tasks to a cheaper/faster model running headless, so the primary model's context and quota stay reserved for work that actually needs reasoning.

## Configuration — resolve this once per model you delegate to

This skill is model-agnostic by design. Before the first delegation, resolve two things:

- **`AGENT_CMD`** — the shell command that runs the target model headless with a prompt. Examples:
  - A `claude --model <id>` alias routed through a gateway (e.g. `claude-9arm` → `claude --model qwen3.6-35b-a3b`)
  - `ollama run <model>` for a local model
  - Any other CLI agent (codex, gemini-cli, aider, etc.) that accepts a prompt and can run tools headless
- **`CONTEXT_WINDOW`** — that model's context window in tokens, used to size delegated tasks.

**If either is unknown, ask the user which command/alias to use and what its context window is — never guess.** Once known for this project, treat them as fixed for the rest of the task. If this becomes a repeat pattern, worth noting the alias in a project `CLAUDE.md` so future sessions don't have to ask again.

## Setting up `AGENT_CMD` (one-time, per model)

`AGENT_CMD` must be an *agentic* CLI running headless — it takes a prompt and can call tools (Bash/Read/Edit/…) without a human clicking through permission prompts. A raw chat CLI (`ollama run`, a bare chatbot REPL) is **not** enough by itself; it has no tool-calling loop.

Two ways to get there:

**A. Point Claude Code itself at a different model** (this is what the original `claude-9arm` alias did, against 9arm's internal Qwen gateway)

Claude Code talks to whatever backend `ANTHROPIC_BASE_URL` points at, as long as that backend speaks the Anthropic Messages API. Put a translating proxy in front of your model of choice, then alias Claude Code to it:

1. Run a proxy that exposes an Anthropic-compatible endpoint backed by your model of choice — [LiteLLM](https://docs.litellm.ai/) is the common self-hosted option; it can front Ollama, OpenRouter, Together, vLLM, Bedrock, and others.
2. Alias Claude Code to it:
   ```bash
   alias claude-cheap='ANTHROPIC_BASE_URL=http://localhost:4000 ANTHROPIC_API_KEY=sk-litellm-key claude --model <model-id-your-proxy-serves>'
   ```
3. Set `AGENT_CMD=claude-cheap`. You now get Claude Code's full tool-execution loop (Bash/Read/Edit/…), just running on the cheaper backend model.

**B. Use a different agentic CLI that natively supports your model**

Tools like `aider`, `opencode`, or a vendor CLI (`codex`, `gemini`) already talk to their own backends — some support local Ollama models directly, no proxy needed. Install the CLI, find its non-interactive/headless flag and its way to scope tool permissions (these won't match Claude Code's `-p` / `--allowedTools` syntax — check that CLI's own docs), and set `AGENT_CMD` to that invocation.

**Before delegating anything, smoke-test `AGENT_CMD` standalone**: run it on a trivial throwaway prompt (e.g. "create a file at /tmp/smoketest.txt containing OK") and confirm it actually acts, rather than stalling on a permission prompt or just chatting back. If it hangs, the headless/tool-scoping flags are wrong — fix that before trying to delegate real work.

## Running a delegated task

```bash
$AGENT_CMD -p "<self-contained task prompt>" --allowedTools Bash Read Edit Write Glob Grep
```

Adjust flags to whatever `$AGENT_CMD`'s CLI actually supports — the flags above match Claude Code-style CLIs; other tools use different flags for headless/non-interactive mode and tool scoping.

- **Scope the tools explicitly.** This is what lets the subagent finish a menial job unattended — without it, most CLIs stall waiting for approval on the first edit or command.
- For edit-only, lower-risk tasks, some CLIs support an auto-accept-edits mode (e.g. Claude Code's `--permission-mode acceptEdits`). Shell commands still prompt under that mode — don't use it for verification/build/test runs.

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

If a job is inherently too big to slice cleanly (it needs whole-codebase context to do correctly), that's a sign it isn't a delegate task — keep it yourself.

## Working directory

Don't rely on cwd persisting across calls:

- Put **absolute paths in the prompt**, or
- Pass whatever equivalent of `--add-dir /abs/path` the CLI supports to grant the subagent access to a directory.

## Return contract

- **Default (text):** the subagent's final message prints to stdout — read it directly.
- **Need to parse the result:** use the CLI's structured-output flag if it has one (e.g. Claude Code's `--output-format json`, reading the `result` field).
- **Background / parallel (run several at once):** redirect to a log and run in the background, then read the log when it finishes:

  ```bash
  $AGENT_CMD -p "<task>" --allowedTools Bash Read Edit Write Glob Grep > /tmp/delegate-<label>.log 2>&1
  ```

  Launch independent tasks as separate background runs; collect each log on completion. Use this when delegating 2+ unrelated menial jobs.

## Workflow checklist

1. Confirm the task is menial and low-risk (see description). If it needs design judgment or this chat's context, **do it yourself** — don't delegate.
2. Confirm `AGENT_CMD` and `CONTEXT_WINDOW` are known for this project — ask the user if not.
3. Check the task fits the context window; split large jobs into bounded per-file/per-dir chunks.
4. Write a fully self-contained prompt with absolute paths and acceptance criteria.
5. Run `$AGENT_CMD -p "..." --allowedTools Bash Read Edit Write Glob Grep` (foreground), or background-redirect for parallel jobs.
6. **Verify the output yourself** — the delegate is cheaper and less reliable than the primary model. Check the file/result actually meets the acceptance criteria before reporting success.

## One-time setup (optional, removes repeated prompts)

To stop per-call permission prompts on delegated runs, add a Bash allow rule for the specific command (via the `update-config` skill, or by editing settings), e.g.:

```json
{ "permissions": { "allow": ["Bash(claude-9arm:*)"] } }
```

(swap `claude-9arm` for whatever `AGENT_CMD` actually is.)

## When NOT to delegate

Architecture/design, debugging that needs reasoning, security-sensitive changes, anything requiring this conversation's context, or tasks where a wrong cheap-model edit is costly to catch. When in doubt, keep it.
