# Setting up a cheaper backend (`AGENT_CMD`)

One-time setup, once per model you want to delegate to. Read this only when `AGENT_CMD` does not yet exist, or when it exists but hangs or refuses to act.

## Do you actually need this?

**No** — if you just want menial work off your main model. The skill's rank 0 (a cheap Claude subagent) needs no setup, no key, no config, and works right now.

**Yes** — if you want delegated work billed to *someone other than Anthropic*, or you need a model Anthropic doesn't serve. That's the only thing this page buys you.

## What you're building

`AGENT_CMD` is an environment variable holding **the name of a command** — a command that runs a coding agent, on a cheap model, without a human watching. The skill then calls it like this:

```bash
$AGENT_CMD -p "<the whole task, spelled out>" --allowedTools Read Glob Grep
```

Three terms worth pinning down, because the rest of this page leans on them:

- **Agentic CLI** — a command-line tool that can actually *do* things: read files, edit them, run commands. Claude Code is one. A plain chat CLI (`ollama run`, a bare chatbot prompt) is **not** — it can only talk back, so it will describe the edit you asked for instead of making it.
- **Headless** — running with no interactive prompts. Nobody is there to approve "can I edit this file?", so the command has to be told its permissions up front.
- **Anthropic Messages API** — the request format Claude Code speaks. Any backend that speaks the same format can stand in for Anthropic, which is what makes this whole thing possible.

**Before you start — where your code ends up.** Any backend other than Anthropic's own means the code you delegate leaves Anthropic's boundary and lands under that provider's retention and training policy. Choose accordingly, and don't delegate work on code you can't send there.

## Step 1 — Pick a route

| Route | Use when | Effort |
|---|---|---|
| **A1. Claude Code → provider's Anthropic-compatible endpoint** | Your provider offers one (most aggregators now do) | Lowest — a config file |
| **A2. Claude Code → translating proxy → backend** | Backend speaks a different format: local Ollama, self-hosted vLLM, a raw OpenAI-shaped API | A server to run and keep up |
| **B. A different agentic CLI entirely** | `aider`, `opencode`, `codex`, `gemini` — already talks to your model | Its own flags, its own docs |

Start at A1 and only leave it if your backend forces you to. A2 means one more process that can be down at the moment you need to delegate — several once-popular translating proxies have been archived precisely because native support landed upstream.

## Step 2 — Write a settings file (route A1)

Claude Code sends its requests wherever `ANTHROPIC_BASE_URL` points, so long as that address speaks the Messages API. You keep Claude Code's full ability to run tools; only the model underneath changes.

[OpenRouter](https://openrouter.ai/docs/cookbook/coding-agents/claude-code-integration) is the common case — one key, hundreds of models. Save this as `~/.claude-cheap.json`:

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

Then `chmod 600 ~/.claude-cheap.json` — it holds an API key. A settings file beats putting `ENV=x claude` in a shell alias: the key stays out of your shell history and out of `ps` output, and the file copies cleanly between machines.

Four things bite people here:

- **Fill in every model slot, not just `--model`.** This is the expensive mistake. `--model` sets only the main conversation; Claude Code keeps *separate* slots for background work (`ANTHROPIC_DEFAULT_HAIKU_MODEL`), subagents (`CLAUDE_CODE_SUBAGENT_MODEL`), and name resolution (the `OPUS`/`SONNET`/`FABLE` entries). **Any slot left blank falls back to Claude Code's built-in Anthropic model IDs** — and your aggregator will happily serve those at full Anthropic price, on your key. `ANTHROPIC_BASE_URL` changes *where* the request goes, not *which model* answers it. Measured on one setup: the identical trivial prompt cost 5.8× more with the slots left blank. The tell is an expensive model you never asked for showing up in your provider's activity log.
- **`ANTHROPIC_API_KEY` vs `ANTHROPIC_AUTH_TOKEN`.** Two different ways to authenticate, and published guides disagree about which one any given gateway wants. Set one, explicitly leave the other empty, and let the smoke test in step 5 settle it. Getting it wrong shows up as 401 errors — or, worse, as Claude Code quietly using your normal Anthropic account instead of the cheap backend.
- **Already signed in?** Run `/logout` first. Otherwise your existing account credentials win over the settings file.
- **Cap the spend at the provider** if it offers per-key limits. Delegated runs happen unattended, so a misconfiguration surfaces as a bill rather than as an error message.

For **route A2**, the settings file is the same idea with a local address — point `ANTHROPIC_BASE_URL` at your proxy (e.g. `http://localhost:4000`) and set `ANTHROPIC_API_KEY` to whatever key the proxy expects. [LiteLLM](https://docs.litellm.ai/) is the usual self-hosted choice.

For **route B**, skip to that CLI's own docs: find its headless flag and its way to scope tool permissions. They **won't** match Claude Code's `-p` / `--allowedTools` syntax.

## Step 3 — Make it callable

`AGENT_CMD` has to be a real command on your `PATH`. A shell **alias will not work** — aliases don't expand in scripts or non-interactive shells, which is exactly how the skill calls it. Neither does a multi-word string: zsh, unlike bash, doesn't split unquoted `$VAR` into separate words, so it tries to run the whole string as one long filename.

A one-line script sidesteps both. Save as `~/.local/bin/claude-cheap` and `chmod +x` it:

```sh
#!/bin/sh
exec claude --settings "$HOME/.claude-cheap.json" --model=<cheap-model-id> "$@"
```

Then in your shell profile:

```bash
export AGENT_CMD=claude-cheap
```

Claude Code snapshots your environment when a session starts, so a profile change is invisible to the session you're in and only takes effect in new ones. Check with `zsh -ic 'echo $AGENT_CMD'` — a plain `echo` inside the current session will read empty and mislead you.

### Optional: several backends, cheapest first

If you have more than one cheap backend, the same script can try them in order. Fall through **only** when the first backend never really ran. If it got far enough to edit files before dying, re-running the same prompt elsewhere does the work twice.

The obvious test for that — "exited nonzero and printed nothing" — **does not work.** Claude Code prints API and auth errors to **stdout**, not stderr, and exits 1. A backend that is flatly refusing every request still produces output, so the obvious test never fires and the fallback silently becomes dead code. What actually identifies a dead backend is stdout holding an error message *and nothing else*:

```sh
#!/bin/sh
out=$(mktemp); trap 'rm -f "$out"' EXIT
claude --settings "$HOME/.claude-free.json" --model=<free-model-id> "$@" >"$out"
status=$?

# Dead backend: nonzero exit, and stdout is an error message and nothing more.
if [ $status -ne 0 ] &&
   { [ ! -s "$out" ] || { [ "$(wc -c <"$out")" -le 2000 ] &&
     grep -qiE 'API Error|Failed to authenticate|Connection error|fetch failed|ECONNREFUSED' "$out"; }; }
then
  echo "free backend down — falling back to paid" >&2
  claude --settings "$HOME/.claude-cheap.json" --model=<cheap-model-id> "$@" </dev/null
  exit $?
fi
cat "$out"; exit $status
```

The size cap is the double-run guard: a run that did real work prints far more than an error line, so it fails the test and is returned as-is even though it also errored.

Two things worth knowing if you adapt this:

- **Test it against a genuinely broken backend, not a fake one.** A stub script that fails the way you *assume* the CLI fails will happily confirm a broken condition — that is exactly how the stdout-vs-stderr bug above survives review. Point the config at a model your key can't access and watch what really happens.
- **Buffer output, never input.** Capturing stdout is what makes the test possible. Reading *stdin* into a file the same way hangs forever whenever nothing is piped in.

## Step 4 — Confirm the model can use tools

Delegation *is* tool use. A model that chats well but calls tools badly is useless here — it will narrate the edit instead of making it. Cheap models are exactly where this breaks, so check before you rely on it.

If your provider publishes model metadata, read it first. On OpenRouter:

```bash
curl -s https://openrouter.ai/api/v1/models \
  | jq -r '.data[] | select(.id=="<model-id>") | {context_length, tools: (.supported_parameters | index("tools") != null), pricing}'
```

That also reports the model's advertised **context window** — how much text it can hold at once, which the skill uses to size tasks. Treat the advertised figure as an upper bound, not the answer. What Claude Code actually gives the model is often lower, and the real number comes from a live run:

```bash
$AGENT_CMD -p "hi" --output-format json </dev/null | jq '.modelUsage'
```

The `contextWindow` field there is the one to size against — it can be several times smaller than advertised (one measured case reported 200K for a model documented at 1M). The same output includes a per-run cost, which is the fastest way to confirm your model-slot pinning actually took effect.

Metadata claiming tool support is necessary but not sufficient. The smoke test is what settles it.

## Step 5 — Smoke-test before trusting it with real work

Run `AGENT_CMD` on a throwaway prompt and confirm it *acts*:

```bash
$AGENT_CMD -p "create a file at <abs-path>/smoketest.txt containing OK" --allowedTools Bash Write
```

Use a scratch path you're happy to delete. Then check the file exists — not that the model *said* it created one. Two failure modes, two different causes:

- **It hangs** → the headless or tool-scoping flags are wrong.
- **It replies describing the file, but no file appears** → the model isn't calling tools properly. Pick a different model; nothing else will fix this.

Fix either before delegating real work.

## Invocation mechanics

The flags a delegated run needs. This syntax is Claude Code's; other CLIs have their own equivalents.

```bash
$AGENT_CMD -p "<self-contained prompt>" --allowedTools Read Glob Grep
```

- **Always scope the tools.** This is what lets a run finish unattended — without it, most CLIs stall waiting for approval on the first edit. Add `Edit Write Bash` only when the task genuinely needs them.
- **Auto-accepting edits.** For edit-only, lower-risk tasks, some CLIs offer a mode like Claude Code's `--permission-mode acceptEdits`. Shell commands still prompt under it, so it won't help for build or test runs.
- **Working directory.** Don't assume the current directory carries across calls. Use absolute paths in the prompt, or pass the CLI's equivalent of `--add-dir /abs/path`.
- **Reading the result.** By default the final message prints to stdout. To parse it instead, use a structured-output flag (Claude Code: `--output-format json`, then read the `result` field).
- **Background and parallel runs.** Give each job its own log and collect them at the end. Worth doing for 2+ unrelated menial jobs:

  ```bash
  $AGENT_CMD -p "<task>" --allowedTools Read Glob Grep > /tmp/delegate-<label>.log 2>&1
  ```

## Optional: stop the repeated permission prompts

If Claude Code asks permission every time it calls your backend, add a Bash allow rule for that one command — through the `update-config` skill, or by editing settings directly:

```json
{ "permissions": { "allow": ["Bash(claude-cheap:*)"] } }
```

Swap `claude-cheap` for whatever `AGENT_CMD` actually is, and keep the rule scoped to that single command rather than widening it to all of `Bash`.
