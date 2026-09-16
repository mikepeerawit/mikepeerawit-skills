#!/bin/bash
# PreToolUse gate on Bash. Bulky commands — test, typecheck, lint, build — must
# go through the `delegate` skill, not the main thread's own context window.
# The skill fires on model judgment; this makes the command-shaped cases certain.
#
# Lets the command through when:
#   DELEGATE_CHILD=1 is set        we ARE a delegate backend (each launcher exports it)
#   it invokes a backend           e.g. `claude-cheap -p "run npm test ..."` — that IS delegating
#   it starts with DELEGATE_INLINE=1   explicit opt-out for when every backend is down
#
# Needs jq. Without it the gate lets everything through rather than blocking blindly.

command -v jq >/dev/null 2>&1 || exit 0
cmd=$(jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0
[ -n "$DELEGATE_CHILD" ] && exit 0
case "$cmd" in DELEGATE_INLINE=1*) exit 0;; esac

IFS=';' read -ra backends <<< "${DELEGATE_BACKENDS:-}"
for b in "${backends[@]}"; do
  b="${b## }"; b="${b%% }"
  [ -n "$b" ] && echo "$cmd" | grep -Eq "(^|[^A-Za-z0-9_./-])${b}([^A-Za-z0-9_-]|$)" && exit 0
done

w='[[:space:]]+'
pattern="(^|[;&|[:space:]])("
pattern+="(npm|pnpm|yarn|bun)${w}(run${w})?(test|typecheck|type-check|lint|build|check|e2e)([[:space:]:]|$)"
pattern+="|((npx|bunx)${w})?(vitest|jest|mocha|tsc|eslint|biome${w}(check|lint)|playwright${w}test|next${w}(build|typegen))([[:space:]]|$)"
pattern+="|(cargo|go)${w}(test|build)([[:space:]]|$)"
pattern+="|pytest([[:space:]]|$)"
pattern+=")"

if echo "$cmd" | grep -Eq "$pattern"; then
  first="${backends[0]:-<backend>}"
  cat >&2 <<MSG
BLOCKED: bulky command in the main thread. Send it through the delegate skill:
  ${first} -p "In $(pwd), run: ${cmd}. Reply PASS or FAIL, then only the failing lines." --allowedTools Read Glob Grep Bash
Fall through to the next entry in DELEGATE_BACKENDS on a backend-level failure. Only if every backend fails, re-run prefixed with DELEGATE_INLINE=1 and say so in one line.
MSG
  exit 2
fi
exit 0
