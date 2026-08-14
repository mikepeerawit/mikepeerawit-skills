# mikepeerawit-skills

Two [Claude Code](https://claude.com/claude-code) skills for long agent sessions — one keeps the cost down, one keeps the work on-track.

A skill is a Markdown file Claude Code loads **by itself** when the situation calls for it. You install it once; you don't run it. Each one starts with a description of when it applies, and Claude pulls in the matching skill mid-task.

## The skills

### [`delegate`](skills/delegate/SKILL.md) — stop paying frontier prices for grunt work

A lot of what burns your quota is menial: renaming a symbol across 40 files, condensing a 5,000-line log, running the suite to see if it's green. `delegate` teaches Claude to spot that work, hand it to a cheaper model, and check the result cheaply — run the tests, glance at `git diff --stat` — instead of re-reading everything the cheap model produced.

The bigger win is often the context window rather than the bill: the cheap model's output never lands in your session. A 5,000-line log gets read somewhere else and comes back as three lines.

It's deliberately conservative. Architecture, debugging that needs judgment, security-sensitive edits, and work depending on a decision made earlier in the conversation all stay with the main model — as do small jobs, where writing the instructions costs more than doing the work.

**It needs [setup](#setup-delegate-only) before it can do anything.** There's no zero-setup fallback on purpose: an earlier version handed the work to a cheap Claude subagent, which still billed the quota the skill exists to protect, and kept getting picked *over* configured providers ([ADR-0001](docs/adr/0001-delegate-requires-a-configured-backend.md)). With no backend it now says so and works inline.

### [`focus`](skills/focus/SKILL.md) — keep a long task from going off the rails

Long work fails in recognizable ways: re-reading the same file a third time, reasoning in circles, wandering into work nobody asked for, quietly dropping part of what was asked, or running out of room and forgetting what it learned an hour ago.

`focus` is a short checklist to run before each step, with a specific fix for each failure, plus a handoff so the next session starts with what the last one learned. No setup. If `delegate` is also installed, the checklist spots steps worth handing off; if it isn't, that check is skipped.

## Install

Via [`npx skills`](https://skills.sh/):

```bash
npx skills add mikepeerawit/mikepeerawit-skills --all
```

Or as a Claude Code plugin, typed inside Claude Code:

```
/plugin marketplace add mikepeerawit/mikepeerawit-skills
/plugin install mikepeerawit-skills
```

Then ask Claude to "list your skills" to confirm they landed.

## Setup (`delegate` only)

You need at least one **backend**: a command that runs a coding agent headless on a cheap model. Three steps.

**1. Point a settings file at a cheap provider.** Anything speaking the Anthropic API works — a gateway, OpenRouter, something local. Save as `~/.claude-cheap.json`:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://your-provider.example/api",
    "ANTHROPIC_AUTH_TOKEN": "<your key>",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "<cheap-model-id>",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "<cheap-model-id>",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "<cheap-model-id>",
    "ANTHROPIC_DEFAULT_FABLE_MODEL": "<cheap-model-id>",
    "CLAUDE_CODE_SUBAGENT_MODEL": "<cheap-model-id>"
  }
}
```

Pin **all five** model slots. Any you leave unset falls through to Claude Code's built-in Anthropic model IDs, which a third-party provider will happily serve you at Anthropic list price — a ~6x difference, and the only symptom is Sonnet showing up in your provider's activity log.

**2. Wrap it in an executable** on your `PATH`, say `~/.local/bin/claude-cheap`:

```sh
#!/bin/sh
exec claude --settings "$HOME/.claude-cheap.json" --model=<cheap-model-id> "$@"
```

`chmod +x` it. It has to be a real executable — a shell alias won't do, because the skill invokes backends non-interactively, where aliases don't expand.

**3. List your backends, cheapest first,** in your shell profile:

```bash
export DELEGATE_BACKENDS="claude-cheap"                    # one is fine
export DELEGATE_BACKENDS="claude-free;claude-paid"         # or several
```

With several, the skill runs the first and falls through to the next only when a backend *never answers* — connection refused, 5xx, auth rejected — then tells you which one did the work. A free-but-flaky provider can sit in front of a paid-but-reliable one, and you pay only when the free one is down. A backend that runs and returns something wrong is a different failure: the next one would fail identically on the same prompt, so the skill stops instead of spending twice.

Claude Code snapshots your environment at session start, so a profile change only reaches **new** sessions. Verify:

```bash
scripts/delegate-e2e.sh --preflight   # resolves every backend, no call, free
scripts/delegate-e2e.sh               # a real delegated job, end to end
```

## Contributing

```bash
node scripts/validate.mjs
```

Checks frontmatter, that each `name` matches its directory, descriptions inside Claude Code's 1024-character limit, working relative links, and that the skill list above matches `skills/`. CI runs it on every push and PR. `delegate-e2e.sh` is deliberately excluded — it needs real backends and credentials, which CI has neither of.

One `SKILL.md` per skill, no `references/`. Everything in it costs tokens every time the skill fires, so it holds the procedure and nothing else — but a reference file the model has to *decide* to open is its own failure mode, and these are short enough not to need one. Background lives here; decisions live in [`docs/adr/`](docs/adr).

`SKILL.md` is written for Claude, not for a person — terse and imperative on purpose.

## Credits

Adapted from [`qwen-agent`](https://github.com/thananon/9arm-skills/blob/main/skills/engineering/qwen-agent/SKILL.md) and [`qwenchance`](https://github.com/thananon/9arm-skills/blob/main/skills/productivity/qwenchance/SKILL.md) in [thananon/9arm-skills](https://github.com/thananon/9arm-skills). `delegate` generalizes the original past its Qwen-specific setup and adds the backend list; `focus` is a rename of an already model-agnostic skill. All credit for the underlying design goes to 9arm.

## License

[MIT](LICENSE)
