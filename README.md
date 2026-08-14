# mikepeerawit-skills

Two [Claude Code](https://claude.com/claude-code) skills for long agent sessions — one keeps the cost down, one keeps the work on-track.

## New here? What a skill is

A skill is a Markdown file of instructions that Claude Code loads **by itself**, when the situation calls for it. You install it once and then forget about it. Every skill starts with a description saying when it applies; Claude reads those descriptions and pulls in the matching skill mid-task.

So you don't run these. You install them, and Claude reaches for them on its own — though you can always ask for one by name.

## The skills

### `delegate` — stop paying frontier prices for grunt work

A long coding session burns through your Claude quota, and a lot of that burn is menial: renaming a symbol across 40 files, reformatting, condensing a 5,000-line log, running the test suite to see if it's green. None of that needs an expensive model.

[`delegate`](skills/delegate/SKILL.md) teaches Claude to spot that kind of work and hand it to a cheaper model, then check the result the cheap way — running the tests, glancing at `git diff --stat` — rather than re-reading everything the cheap model produced. Checking work you delegated shouldn't cost as much as doing it yourself.

There's a second benefit that's easy to miss, and it's often the bigger one: the cheap model's output never lands in your main session. A 5,000-line log gets read somewhere else and comes back as three lines. Long sessions usually die of a full context window rather than an exhausted quota, so keeping the bulk out matters even when you aren't watching the bill.

It's deliberately conservative about what it hands off. Architecture, debugging that needs judgment, security-sensitive edits, work that depends on a decision you made earlier in the conversation — those stay with the main model. It also won't bother for small jobs, where writing the instructions and checking the result costs more than just doing the work.

**Setup is required — one time, before it can do anything.** You list your backends cheapest-first in one environment variable, and that's the whole configuration:

```bash
export DELEGATE_BACKENDS="claude-9arm;claude-openrouter"
```

Each entry is a command that runs a coding agent, headless, on a cheap model. The skill runs the first one; if that backend never answers — connection refused, 5xx, auth rejected — it re-runs the same prompt against the next, and tells you which one ended up doing the work. So a free-but-flaky provider can sit in front of a paid-but-reliable one, and you only pay when the free one is down. The last section of [`SKILL.md`](skills/delegate/SKILL.md) has the two-line wrapper scripts.

There's deliberately no zero-setup fallback. An earlier version handed the work to a cheap Claude subagent when nothing was configured, which kept the bulk out of your context window but still billed the quota the skill exists to protect — and in practice it got picked *over* a configured provider, because a subagent is a tool sitting in front of the model while the backend list is an environment variable it has to go looking for. Removing the option removed the bug ([ADR-0001](docs/adr/0001-delegate-requires-a-configured-backend.md)). With no backend the skill now says so and does the work inline, rather than quietly costing you money.

### `focus` — keep a long task from going off the rails

Long multi-step work fails in a few recognizable ways. The agent re-reads the same file for the third time. It reasons in circles without doing anything. It quietly wanders into work you never asked for, or quietly drops part of what you did ask for. Or it runs out of room and forgets what it learned an hour ago.

[`focus`](skills/focus/SKILL.md) gives Claude a short checklist to run before each step, with a specific fix for each failure. It also handles the handoff when a session is about to run out of context, so the next session starts with what the last one learned instead of from scratch.

If you install both, the checklist also spots steps worth handing to `delegate` before they fill the window — but `focus` works on its own, and skips that check when `delegate` isn't there.

## Install

The easiest way, via [`npx skills`](https://skills.sh/):

```bash
npx skills add mikepeerawit/mikepeerawit-skills          # choose from a menu
npx skills add mikepeerawit/mikepeerawit-skills --all    # install both
npx skills add mikepeerawit/mikepeerawit-skills -s delegate   # just one
```

Or as a Claude Code plugin, typed inside Claude Code:

```
/plugin marketplace add mikepeerawit/mikepeerawit-skills
/plugin install mikepeerawit-skills
```

Either way, ask Claude to "list your skills" afterwards to confirm they landed.

## Contributing

Run the checks before opening a PR:

```bash
node scripts/validate.mjs
```

It verifies every skill has well-formed frontmatter, a `name` matching its directory, a description inside Claude Code's 1024-character limit, and working relative links — plus that the skill list above matches what's actually in `skills/`. CI runs the same thing on every push and PR.

There's also a manual end-to-end check for `delegate`:

```bash
scripts/delegate-e2e.sh --preflight   # resolves the backend list, no call, free
scripts/delegate-e2e.sh               # real delegated task against your backends
```

It's kept out of `validate.mjs` on purpose — it needs a configured `DELEGATE_BACKENDS` and those providers' credentials, so CI can't run it and shouldn't try.

Layout:

```
skills/<name>/SKILL.md   # the whole skill — one file, loaded whenever it fires
```

One file per skill, on purpose. Everything in `SKILL.md` costs tokens every time the skill fires, so it holds the procedure and nothing else — but a `references/` directory the model has to decide to open is its own failure mode, and these skills are short enough not to need one. Background and rationale live here in the README, or in [`docs/adr/`](docs/adr) when a decision needs a record.

Worth knowing if you're new to writing skills: `SKILL.md` is written for Claude to read, not for a person. It's terse and imperative on purpose.

## Credits

`delegate` and `focus` are adapted from [`qwen-agent`](https://github.com/thananon/9arm-skills/blob/main/skills/engineering/qwen-agent/SKILL.md) and [`qwenchance`](https://github.com/thananon/9arm-skills/blob/main/skills/productivity/qwenchance/SKILL.md) in [thananon/9arm-skills](https://github.com/thananon/9arm-skills) — `delegate` generalizes the original beyond its Qwen-specific setup; `focus` is a rename of the original, which was already model-agnostic. All credit for the underlying design goes to 9arm.

## License

[MIT](LICENSE)
