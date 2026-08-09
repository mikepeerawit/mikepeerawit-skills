# Setting up `AGENT_CMD`

One-time setup, per model you want to delegate to. Read this only when `AGENT_CMD` does not yet exist for this project, or when it exists but hangs / refuses to act.

`AGENT_CMD` must be an *agentic* CLI running headless — it takes a prompt and can call tools (Bash/Read/Edit/…) without a human clicking through permission prompts. A raw chat CLI (`ollama run`, a bare chatbot REPL) is **not** enough by itself; it has no tool-calling loop.

Two ways to get there.

## A. Point Claude Code itself at a different model

This is what the original `claude-9arm` alias did, against 9arm's internal Qwen gateway.

Claude Code talks to whatever backend `ANTHROPIC_BASE_URL` points at, as long as that backend speaks the Anthropic Messages API. Put a translating proxy in front of your model of choice, then alias Claude Code to it:

1. Run a proxy that exposes an Anthropic-compatible endpoint backed by your model of choice — [LiteLLM](https://docs.litellm.ai/) is the common self-hosted option; it can front Ollama, OpenRouter, Together, vLLM, Bedrock, and others.
2. Alias Claude Code to it:

   ```bash
   alias claude-cheap='ANTHROPIC_BASE_URL=http://localhost:4000 ANTHROPIC_API_KEY=sk-litellm-key claude --model <model-id-your-proxy-serves>'
   ```

3. Set `AGENT_CMD=claude-cheap`. You now get Claude Code's full tool-execution loop (Bash/Read/Edit/…), just running on the cheaper backend model.

## B. Use a different agentic CLI that natively supports your model

Tools like `aider`, `opencode`, or a vendor CLI (`codex`, `gemini`) already talk to their own backends — some support local Ollama models directly, no proxy needed.

Install the CLI, find its non-interactive/headless flag and its way to scope tool permissions, and set `AGENT_CMD` to that invocation. These flags **won't** match Claude Code's `-p` / `--allowedTools` syntax — check that CLI's own docs.

## Smoke-test before delegating real work

Run `AGENT_CMD` standalone on a trivial throwaway prompt and confirm it actually *acts*, rather than stalling on a permission prompt or just chatting back:

```bash
$AGENT_CMD -p "create a file at /tmp/smoketest.txt containing OK" --allowedTools Bash Write
```

Then check the file exists. If it hangs, the headless/tool-scoping flags are wrong — fix that before trying to delegate real work.

## Silence repeat permission prompts (optional)

To stop per-call permission prompts on delegated runs, add a Bash allow rule for the specific command — via the `update-config` skill, or by editing settings directly:

```json
{ "permissions": { "allow": ["Bash(claude-cheap:*)"] } }
```

Swap `claude-cheap` for whatever `AGENT_CMD` actually is. Scope the rule to that one command; don't broaden it to all of `Bash`.
