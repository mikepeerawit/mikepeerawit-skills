# Setting up `AGENT_CMD`

One-time setup, per model you want to delegate to. Read this only when `AGENT_CMD` does not yet exist for this project, or when it exists but hangs / refuses to act.

`AGENT_CMD` must be an *agentic* CLI running headless — it takes a prompt and can call tools (Bash/Read/Edit/…) without a human clicking through permission prompts. A raw chat CLI (`ollama run`, a bare chatbot REPL) is **not** enough by itself; it has no tool-calling loop.

Two ways to get there.

## A. Point Claude Code itself at a cheaper backend

Claude Code talks to whatever backend `ANTHROPIC_BASE_URL` points at, as long as that backend speaks the Anthropic Messages API. You get Claude Code's full tool-execution loop (Bash/Read/Edit/…), just running on a cheaper model.

Whether you need a proxy depends entirely on the backend.

### A1. Backend already speaks the Anthropic Messages API — no proxy

Prefer this. Aggregators and gateways increasingly expose a native Anthropic-compatible endpoint, so there is nothing to run locally.

[OpenRouter](https://openrouter.ai/docs/cookbook/coding-agents/claude-code-integration) is the common case — one key, hundreds of models:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://openrouter.ai/api",
    "ANTHROPIC_API_KEY": "sk-or-...",
    "ANTHROPIC_AUTH_TOKEN": "",
    "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1",

    "ANTHROPIC_DEFAULT_OPUS_MODEL": "<cheap-model-id>",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "<cheap-model-id>",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "<cheap-model-id>",
    "ANTHROPIC_DEFAULT_FABLE_MODEL": "<cheap-model-id>",
    "CLAUDE_CODE_SUBAGENT_MODEL": "<cheap-model-id>"
  }
}
```

Save that as e.g. `~/.claude-cheap.json`, then alias Claude Code to it and set `AGENT_CMD=claude-cheap`:

```bash
alias claude-cheap='claude --settings ~/.claude-cheap.json --model <cheap-model-id>'
```

A settings file beats inlining `ENV=x claude` in the alias: it keeps the key out of your shell history and out of `ps` output, and it survives being copied between machines. `chmod 600` it — it holds a key.

Four things that bite:

- **Pin every model slot, not just `--model`.** This is the expensive one. `--model` sets only the main conversation model; Claude Code keeps separate slots for background work (`ANTHROPIC_DEFAULT_HAIKU_MODEL`), subagents (`CLAUDE_CODE_SUBAGENT_MODEL`), and alias resolution (the `OPUS`/`SONNET`/`FABLE` vars). **Any slot you leave unset falls through to Claude Code's built-in Anthropic model IDs** — and an aggregator will serve those at full Anthropic price against your key. `ANTHROPIC_BASE_URL` changes *where* requests go, not *which model* answers. Measured on one setup: an identical trivial prompt cost 5.8× more with the slots unset. Symptom is a frontier model you never asked for showing up in your provider's activity log.
- **`ANTHROPIC_API_KEY` vs `ANTHROPIC_AUTH_TOKEN`** — these are separate auth paths and published guides disagree on which one a given gateway wants. Set one, explicitly empty the other, and confirm with the smoke test below. Symptom of getting it wrong: 401s, or the CLI silently using your normal Anthropic account instead of the cheap backend.
- **Already logged in?** Run `/logout` first, or your existing account credentials take precedence over the settings file.
- **Aliases don't expand in non-interactive shells.** If something invokes `AGENT_CMD` programmatically, expand it to the full `claude --settings … --model …` command.

Cap spend at the provider if it supports per-key limits. Delegated runs are unattended, so a misconfiguration like the one above surfaces as a bill rather than an error.

### A2. Backend doesn't speak the Anthropic API — translating proxy

Only needed for backends with no Anthropic-compatible endpoint of their own: local Ollama, self-hosted vLLM, a raw OpenAI-shaped API. [LiteLLM](https://docs.litellm.ai/) is the usual self-hosted option.

```bash
alias claude-cheap='ANTHROPIC_BASE_URL=http://localhost:4000 ANTHROPIC_API_KEY=sk-litellm-key claude --model <model-id-your-proxy-serves>'
```

Don't reach for this if A1 covers your backend — a proxy is one more process that can be down when you need to delegate. Several once-popular single-purpose translating proxies have been archived precisely because native support landed upstream.

## B. Use a different agentic CLI that natively supports your model

Tools like `aider`, `opencode`, or a vendor CLI (`codex`, `gemini`) already talk to their own backends — some support local Ollama models directly, no proxy needed.

Install the CLI, find its non-interactive/headless flag and its way to scope tool permissions, and set `AGENT_CMD` to that invocation. These flags **won't** match Claude Code's `-p` / `--allowedTools` syntax — check that CLI's own docs.

## Check the model can actually call tools

Delegation is tool use. A model that chats well but calls tools badly is useless here — it will narrate the edit instead of making it. Cheap models are exactly where this fails, so check before committing.

If the backend publishes model metadata, read it. On OpenRouter:

```bash
curl -s https://openrouter.ai/api/v1/models \
  | jq -r '.data[] | select(.id=="<model-id>") | {context_length, tools: (.supported_parameters | index("tools") != null), pricing}'
```

That also gives you the model's advertised `CONTEXT_WINDOW` — but treat it as an upper bound, not the answer. What the *harness* will actually use can be lower. With Claude Code, get the real figure from a live run:

```bash
$AGENT_CMD -p "hi" --output-format json </dev/null | jq '.modelUsage'
```

The `contextWindow` field there is what to size delegated tasks against. It can be several times smaller than the model's advertised window — one measured case reported 200K for a model documented at 1M. The same output gives a per-run cost, which is the quickest way to confirm the slot pinning above actually took effect.

Note that Claude Code is tuned for Anthropic models, and vendors routing it to non-Anthropic models generally say so. Metadata claiming tool support is necessary, not sufficient — the smoke test is what settles it.

## Smoke-test before delegating real work

Run `AGENT_CMD` standalone on a trivial throwaway prompt and confirm it actually *acts*, rather than stalling on a permission prompt or just chatting back:

```bash
$AGENT_CMD -p "create a file at <abs-path>/smoketest.txt containing OK" --allowedTools Bash Write
```

Use a scratch path you're happy to delete. Then check the file exists — not that the model *said* it created it. If it hangs, the headless/tool-scoping flags are wrong. If it replies describing the file without writing one, the model isn't calling tools properly; pick a different model. Fix either before trying to delegate real work.

## Silence repeat permission prompts (optional)

To stop per-call permission prompts on delegated runs, add a Bash allow rule for the specific command — via the `update-config` skill, or by editing settings directly:

```json
{ "permissions": { "allow": ["Bash(claude-cheap:*)"] } }
```

Swap `claude-cheap` for whatever `AGENT_CMD` actually is. Scope the rule to that one command; don't broaden it to all of `Bash`.
