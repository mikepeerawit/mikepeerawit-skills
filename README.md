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
| [`delegate-agent`](skills/delegate-agent/SKILL.md) | Delegate menial, well-scoped coding tasks to a cheaper/faster subagent model (any model — not tied to one vendor) instead of burning the primary model's tokens/quota. |
| [`stay-on-track`](skills/stay-on-track/SKILL.md) | Keeps a long Claude Code task on-track — breaks out of looping/circular thinking, watches the context budget, and triggers a clean handoff before the window fills. |
