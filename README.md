# mikepeerawit-skills

Personal [Claude Code](https://claude.com/claude-code) skills for long-running agent work — keeping it cheap, and keeping it on-track.

## Install

Via [`npx skills`](https://skills.sh/):

```bash
npx skills add mikepeerawit/mikepeerawit-skills          # pick interactively
npx skills add mikepeerawit/mikepeerawit-skills --all     # install everything
npx skills add mikepeerawit/mikepeerawit-skills -s delegate
```

Or as a Claude Code plugin, from inside Claude Code:

```
/plugin marketplace add mikepeerawit/mikepeerawit-skills
/plugin install mikepeerawit-skills
```

## Skills

| Skill | Description |
|---|---|
| [`delegate`](skills/delegate/SKILL.md) | Delegate menial, well-scoped coding tasks to a cheaper subagent model to reduce the primary model's token burn, saving its tokens/quota for work that needs real reasoning. |
| [`focus`](skills/focus/SKILL.md) | Keeps a long Claude Code task on-track — breaks out of looping/circular thinking, watches the context budget, and triggers a clean handoff before the window fills. |

## Development

```bash
node scripts/validate.mjs
```

Checks every skill for well-formed frontmatter, a `name` matching its directory, a description within Claude Code's 1024-character limit, and working relative links — plus that the table above matches what's actually in `skills/`. CI runs this on every push and PR.

Layout:

```
skills/<name>/SKILL.md          # the skill itself — always loaded when it fires
skills/<name>/references/*.md   # detail loaded on demand, not on every invocation
```

Keep `SKILL.md` to the procedure. Anything a reader needs once — one-time setup, background, long examples — belongs in `references/`, linked from `SKILL.md`.

## Credits

`delegate` and `focus` are adapted from [`qwen-agent`](https://github.com/thananon/9arm-skills/blob/main/skills/engineering/qwen-agent/SKILL.md) and [`qwenchance`](https://github.com/thananon/9arm-skills/blob/main/skills/productivity/qwenchance/SKILL.md) in [thananon/9arm-skills](https://github.com/thananon/9arm-skills) — `delegate` generalizes the original beyond its Qwen-specific setup; `focus` is a rename of the original, which was already model-agnostic. All credit for the underlying design goes to 9arm.

## License

[MIT](LICENSE)
