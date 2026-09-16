#!/bin/bash
# SessionStart hook: hand the orchestration rules to the main thread as context.
# Runs on startup, resume, /clear and after compaction, so the rules survive all of them.
f="$(cd "$(dirname "$0")" && pwd)/orchestrator.md"
[ -r "$f" ] || exit 0
if command -v jq >/dev/null 2>&1; then
  jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}' "$f"
else
  cat "$f"
fi
