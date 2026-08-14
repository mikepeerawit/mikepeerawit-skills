---
name: focus
description: Keeps a long Claude Code task on-track — breaks out of looping/circular thinking, catches drift from what was actually asked, bounds internal reasoning, and checkpoints work that compaction would otherwise lose. Use when the model is repeating steps, re-reading the same files, second-guessing in circles, wandering into work nobody asked for, quietly dropping part of the task, or running a long multi-step task at risk of exhausting context. Also use when the user says it is "looping", "going in circles", "stuck", "repeating itself", "off track", or asks for a handoff before running out of context.
---

# Focus

Long, multi-step work fails four ways: **looping**, **over-thinking**, **drifting off the ask**, and **losing what you learned**. Run the checklist below **before each step**. When a trigger fires, do the matching action — don't deliberate about it. Adapted from [`qwenchance`](https://github.com/thananon/9arm-skills) by 9arm.

## Before each step — run this

| Check | Trigger fires when... | Do this |
|---|---|---|
| **Looping?** | You're about to repeat an action (signals in §1) | Break the loop — pick one fix in §1 |
| **Over-thinking?** | You've reasoned past ~1000 words without acting | Stop. Act on your current best decision, or ask the user one question |
| **Still on the ask?** | You're about to do work the user didn't request, or you've dropped part of what they did | Restate the ask in one line; cut the extra or reinstate the missing part |
| **Context tight?** | A low-context reminder appeared, **or** 2+ budget signals hold (§3) | Reminder → hand off (§4). Signals → checkpoint (§3) |
| **Offloadable?** | The next step is a large read, repo-wide search, bulk mechanical edit, or pass-fail suite run (§5) | Hand it to a cheaper model so its output never enters this window |

If nothing fires, take the step.

## 1. Loops — detect and break

A step is a loop if **any** of these is true:

- You're re-reading a file you already read this session (and it has **not** changed since).
- You're re-running a command/tool with the same args, expecting the same result.
- You're returning to a hypothesis you already tried and dropped.
- You're "reconsidering from the start" with no new evidence.
- The last 2 steps gained no new information.

**Re-reading a file you just edited is NOT a loop** — that's verifying.

When a loop fires, **stop** and do exactly one:

1. State the blocker in one sentence and ask the user a specific question.
2. Write what you know vs. don't know, then take a **different** action than last time.
3. Looped 2+ times on the same sub-problem? Declare it unsolved-for-now; move on or hand off.

Never repeat a failed action hoping for a different result.

**Retry cap:** never run the same failing command a 3rd time. Can't get something working after ~3 attempts — *even varied ones* — STOP and ask the user.

**Don't edit blind** — it's the top loop source. Read enough to know the change is correct *before* editing, and verify each edit before the next step. One edit → one check.

## 2. Thinking — keep it bounded

Cap reasoning at **~1000 words per step**. Past that, you're deliberating instead of acting.

- Decide → act → observe. Don't re-derive a decision you already made.
- Can't decide in ~1000 words? The task is underspecified — **ask the user one sharp question**.
- Don't restate the whole problem to yourself. Reference what you concluded; don't rebuild it.

## 3. Context budget — checkpoint early, hand off only when told

**Authoritative:** a `<system-reminder>` about low context or approaching auto-compaction → **hand off now** (§4). Don't start new work.

**Nothing else triggers a handoff.** Compaction carries the work forward; a premature `/clear` throws away context you'd have kept for free. What compaction *does* drop is why you ruled things out — so context pressure triggers a **checkpoint**, not an exit.

Count how many are true right now:

- [ ] 20+ assistant turns into the task.
- [ ] Read 5+ files, or any one huge file/log/dump.
- [ ] Long tool outputs you keep scrolling back to.
- [ ] 3+ plan steps still left.

**0 or 1 → continue.** **2+ → checkpoint:** land durable artifacts (save the file, commit, write the result), append to the **Ruled out** list (§4), then keep going. Count first, don't judge by feel.

Before an expensive step, check whether you can offload it (§5) — cheaper than absorbing it. Then checkpoint if the count says so, offloaded or not: offloading keeps new output out of your window, but it doesn't preserve what you've already learned.

## 4. The handoff note

Compaction summarizes what happened; it does **not** preserve why you ruled things out. Write the note as you go, not once at the end.

- **Goal** — the task, in one sentence.
- **Done** — what has landed: files changed, commands that worked, decisions already made.
- **Next** — the immediate next step, concrete enough to act on without re-deriving it.
- **Ruled out** — dead ends already tried, and why. The part nothing else preserves.

Keep it in a file (`HANDOFF.md` or a scratch file) and update it at each checkpoint — chat scrollback doesn't survive compaction either.

**On the authoritative low-context reminder:** land durable artifacts, finish the note, then tell the user plainly — *"Context is getting tight. I've landed X and written the handoff to Y. Start a fresh session with `/clear`."* You cannot clear or compact the context yourself.

## 5. Offload before you spend the window

The cheapest context is the context you never fill. A large read, a repo-wide search, a bulk mechanical edit, or a suite run you only need pass-fail from can go to a cheaper model, so only its *conclusion* lands here.

**Check the skill list first.** If a `delegate`-style skill is installed, use it and follow its rules. If none is, do the step yourself — never call a skill by name on the assumption it's available, and never stall waiting for one.

Two limits, so this doesn't become its own detour:

- **Only offload work that survives losing this conversation.** The offloaded step gets a self-contained prompt and none of the discussion behind it. If restating it in full is harder than doing the step, do the step.
- **The size bar.** Offload when the step would add **>2k tokens** to this window **or** touch **>5 files**. Under *both*, take the step yourself. (A delegate skill sets its own bar; where they differ, follow that skill's.)
