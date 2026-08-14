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

**Cost to get started: nothing.** With no setup at all it hands the work to a cheap Claude subagent — that keeps the grunt work out of your main session's context window, and a cheap model burns fewer tokens than your main one would, but it's still your Anthropic quota paying. To move the spend off Anthropic entirely, point it at an outside provider once ([`references/setup.md`](skills/delegate/references/setup.md)); after that it always prefers that provider, and only falls back to the Claude subagent if the provider is down.

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

Layout:

```
skills/<name>/SKILL.md          # the skill itself — loaded in full whenever it fires
skills/<name>/references/*.md   # detail loaded only on demand
```

That split is the main thing to respect when editing. Everything in `SKILL.md` costs tokens every single time the skill fires, so it holds the procedure and nothing else. Anything a reader needs only once — one-time setup, background, long examples — goes in `references/` behind a link.

Worth knowing if you're new to writing skills: `SKILL.md` is written for Claude to read, not for a person. It's terse and imperative on purpose. The human-friendly explanations belong here in the README and in `references/`.

## Credits

`delegate` and `focus` are adapted from [`qwen-agent`](https://github.com/thananon/9arm-skills/blob/main/skills/engineering/qwen-agent/SKILL.md) and [`qwenchance`](https://github.com/thananon/9arm-skills/blob/main/skills/productivity/qwenchance/SKILL.md) in [thananon/9arm-skills](https://github.com/thananon/9arm-skills) — `delegate` generalizes the original beyond its Qwen-specific setup; `focus` is a rename of the original, which was already model-agnostic. All credit for the underlying design goes to 9arm.

## License

[MIT](LICENSE)
