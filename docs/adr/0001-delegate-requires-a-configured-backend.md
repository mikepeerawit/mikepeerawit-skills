---
status: accepted
---

# `delegate` requires a configured `AGENT_CMD`; the subagent fallback is removed

`delegate` used to rank two backends: a configured `AGENT_CMD` (rank 1+, spending an outside provider's credit) and a native cheap-model subagent (rank 0, spending the Anthropic quota the skill exists to protect). Rank 0 was documented as a fallback for three narrow cases. In practice it got picked *instead of* a configured backend, and adding emphasis to `SKILL.md` ("Never pick rank 0 over a configured backend", commit `3ca5ef5`) did not stop it. We are removing rank 0 entirely: `AGENT_CMD` is now a hard prerequisite.

## Why emphasis didn't work

The two options were never presented to the model on equal terms. The subagent tool sits in the tool list every turn, with a schema, ready to call. `AGENT_CMD` is an environment variable the model must deliberately go looking for — and `SKILL.md` never said how to look, mentioning the check only in prose 25 lines below the workflow step that needed it. The model reached the "pick a backend" step holding no evidence a backend existed and chose the one it could see. That is a structural asymmetry, and no amount of stronger wording fixes it.

The same gap made the failure invisible. Some harness configurations carry a standing instruction against spawning subagents (observed verbatim: *"Do not call the AgentTool unless the user requested it"*). When that fires, the skill can reach neither backend and silently does the work inline — indistinguishable, from the outside, from the skill never having triggered at all.

## Considered options

1. **Keep rank 0, gate it behind an explicit precondition** — make `printenv AGENT_CMD` a numbered workflow step and permit rank 0 only on an empty result. Preserves a working path for users with no setup, since rank 0 still keeps bulk output out of the main context window even though it saves no quota.
2. **Demote rank 0 to `references/setup.md`** — same effect on the default path, keeps it documented.
3. **Delete it.** Chosen.

Option 1 was recommended and rejected. The argument for it was that rank 0's context-window saving is real and worth keeping for unconfigured users; the argument against, which won, is that a skill whose entire premise is "stop spending the expensive quota" should not ship a default path that spends it. An option that only ever fires by mistake is worth less than the bug it causes.

## Consequences

- **The README's "cost to get started: nothing" claim is false and has been rewritten.** Setup is now a genuine prerequisite, not an upgrade.
- **No floor under a total outage.** If every backend behind `AGENT_CMD` is down, there is no fallback. The skill announces that and does the work inline. This is a deliberate reduction in resilience, accepted because a silent fallback to the protected quota is the worse failure.
- **Never fail silently.** Both "nothing configured" and "everything down" must produce a one-line announcement before proceeding inline. Silence is what let the original bug survive undiagnosed.
- **`printenv AGENT_CMD` is a mandatory workflow step**, not an assumption. Detection was never the broken part — the variable is visible to the Bash tool — but making the check explicit is what removes the structural asymmetry described above.
- **Ranking is the wrapper's job, not the skill's.** With one backend name in play, `SKILL.md` no longer carries a ranking apparatus; a wrapper that fronts several backends handles its own ordering and fallback, and announces on stderr when it falls through.
