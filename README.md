# mikepeerawit-skills

Personal [Claude Code](https://claude.com/claude-code) skills, installable via [`npx skills`](https://skills.sh/).

## Install

```bash
npx skills add mikepeerawit/mikepeerawit-skills          # pick interactively
npx skills add mikepeerawit/mikepeerawit-skills --all     # install everything
npx skills add mikepeerawit/mikepeerawit-skills -s delegate-agent
```

## Skills

| Skill | Description |
|---|---|
| [`delegate-agent`](skills/delegate-agent/SKILL.md) | Delegate menial, well-scoped coding tasks to a cheaper subagent model to reduce the primary model's token burn, saving its tokens/quota for work that needs real reasoning. |
| [`stay-on-track`](skills/stay-on-track/SKILL.md) | Keeps a long Claude Code task on-track — breaks out of looping/circular thinking, watches the context budget, and triggers a clean handoff before the window fills. |

## Credits

`delegate-agent` and `stay-on-track` are adapted from [`qwen-agent`](https://github.com/thananon/9arm-skills/blob/main/skills/engineering/qwen-agent/SKILL.md) and [`qwenchance`](https://github.com/thananon/9arm-skills/blob/main/skills/productivity/qwenchance/SKILL.md) in [thananon/9arm-skills](https://github.com/thananon/9arm-skills) — `delegate-agent` generalizes the original beyond its Qwen-specific setup; `stay-on-track` is a direct rename since the original content was already model-agnostic. All credit for the underlying design goes to 9arm.
