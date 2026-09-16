---
status: accepted
---

# Command-shaped delegation is enforced by a hook, not by emphasis

`delegate` fires on model judgment: the model reads the description, estimates the job, and decides. For the four cases the skill marks *always delegate* — test, typecheck, lint, build — that judgment was observed to fail silently for weeks. A memory note from one session recorded the backends as broken; every later session took it at face value and ran the suites inline on the frontier model. Nothing errored. Usage simply went up.

[ADR-0001](0001-delegate-requires-a-configured-backend.md) already found that stronger wording does not fix a structural asymmetry. This is the same shape: the Bash tool is in the tool list every turn, ready to run `npm test`; the skill is a description the model has to weigh first. When the two compete, Bash wins often enough to matter.

## Decision

The `orchestrator` plugin ships a `PreToolUse` hook on Bash that refuses the command-shaped cases and tells the model to delegate them instead. The hook is deterministic where the skill is probabilistic. The skill still owns *how* to delegate; the hook only guarantees *that* it happens for the cases where the answer is never in doubt.

Three escapes, each explicit:

- **`DELEGATE_CHILD=1`** — exported by every backend launcher, so the delegate's own test run passes the gate. Without it the hook would block the very command it demanded.
- **A backend name in the command** — `claude-cheap -p "run npm test …"` *is* delegating. The gate reads `DELEGATE_BACKENDS` and lets those through.
- **`DELEGATE_INLINE=1` prefix** — for the total-outage case ADR-0001 accepted. The skill's "no backend → inline, and say so" rule needs a way past the hook; the prefix is that way, and it is loud by construction.

## Considered options

1. **Stronger wording in `SKILL.md`.** Rejected on the ADR-0001 argument: it was already the strongest section of the skill.
2. **A hook in the user's own `settings.json`.** Works for one machine. Rejected as the *shipped* form because it does not travel: the point of packaging is that a second machine gets the same behaviour from one `/plugin install`.
3. **A hook shipped in the `mikepeerawit-skills` plugin itself.** Rejected: the skills plugin is opinion-free about how you run your session. A hook that blocks `npm test` is a strong opinion, and it belongs in a plugin a user chooses separately.
4. **A separate `orchestrator` plugin in the same marketplace.** Chosen.

## Consequences

- **Two plugins, one marketplace.** `mikepeerawit-skills` stays the neutral pair of skills. `orchestrator` is the opinionated layer on top and requires `delegate` to be installed and configured.
- **`SKILL.md` gains one line** in *No backend*: prefix with `DELEGATE_INLINE=1` when a gate hook blocks the inline run. The skill now knows the hook exists; it does not depend on it.
- **Launchers gain one line.** `export DELEGATE_CHILD=1` before `exec claude`. `scripts/orchestrator-settings.sh` adds it; the README shows it.
- **The hook needs `jq`.** Without it the gate lets everything through rather than block blindly. A missing dependency must degrade to "no enforcement", never to "no work".
- **Model choice stays per machine.** A plugin cannot set `model` or `CLAUDE_CODE_SUBAGENT_MODEL`; the settings script does, and the README says so.
